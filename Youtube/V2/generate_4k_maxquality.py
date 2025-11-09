import sys
import subprocess
from shutil import which
import numpy as np
import argparse
from math import ceil

# --------------------- Default configuration ---------------------
W = 3840
H = 2160
FPS = 60
FRAMES = 600         # 60 * 10s
DURATION_SEC = FRAMES / FPS
# Multipliers / masks for 24-bit color arithmetic
MULT = np.uint32(1664525)
ADD = np.uint32(1013904223)
MASK24 = np.uint32((1 << 24) - 1)
KEY_MULT = np.uint32(2654435761)  # per-frame key mixing
# -----------------------------------------------------------------

def ffmpeg_exists():
    return which("ffmpeg") is not None

def get_available_encoders():
    try:
        proc = subprocess.run(["ffmpeg", "-encoders"], capture_output=True, text=True, check=False)
        return proc.stdout
    except Exception:
        return ""

def build_ffmpeg_cmd(outfile, pix_fmt_input, use_nvenc, lossless, bitrate_bps=None, profile10=False):
    """
    Construct ffmpeg command list.
    - pix_fmt_input: 'rgb24' or 'rgb48le'
    - use_nvenc: True -> prefer hevc_nvenc
    - lossless: True -> instruct encoder for lossless
    - bitrate_bps: if provided, set bitrate targeting mode
    - profile10: request 10-bit profile when possible
    """
    size_str = f"{W}x{H}"
    base = [
        "ffmpeg", "-y",
        "-f", "rawvideo", "-pix_fmt", pix_fmt_input, "-s", size_str, "-r", str(FPS), "-i", "-"
    ]

    if use_nvenc:
        # Use hevc_nvenc (NVidia) options
        # prefer high-quality presets; when lossless -> constqp qp 0
        if lossless:
            enc = ["-c:v", "hevc_nvenc", "-preset", "p1", "-rc", "constqp", "-qp", "0"]
            # profile/main10 not meaningful with constqp=0 but we can request main10
            if profile10:
                enc += ["-profile:v", "main10"]
        elif bitrate_bps:
            # set vbr with requested bitrate (attempt)
            kbps = int(bitrate_bps / 1000)
            enc = ["-c:v", "hevc_nvenc", "-preset", "p1", "-rc", "vbr_hq", "-b:v", f"{kbps}k", "-maxrate", f"{kbps}k"]
            if profile10:
                enc += ["-profile:v", "main10"]
        else:
            enc = ["-c:v", "hevc_nvenc", "-preset", "p1", "-rc", "vbr_hq", "-cq", "18"]
            if profile10:
                enc += ["-profile:v", "main10"]
        # ensure YUV 4:2:0 10-bit if profile10
        pix_out = "yuv420p10le" if profile10 else "yuv420p"
        enc += ["-pix_fmt", pix_out, "-movflags", "+faststart", outfile]
        return base + enc
    else:
        # Fallback to libx265 (software)
        if lossless:
            enc = ["-c:v", "libx265", "-preset", "slow", "-x265-params", "lossless=1"]
        elif bitrate_bps:
            kbps = int(bitrate_bps / 1000)
            enc = ["-c:v", "libx265", "-preset", "slow", "-b:v", f"{kbps}k", "-maxrate", f"{kbps}k"]
        else:
            enc = ["-c:v", "libx265", "-preset", "slow", "-crf", "16"]
        # choose 10-bit pixfmt for libx265 if profile10
        pix_out = "yuv420p10le" if profile10 else "yuv420p"
        enc += ["-pix_fmt", pix_out, "-movflags", "+faststart", outfile]
        return base + enc

def compute_bitrate_bps(target_size_gb, duration_sec):
    if target_size_gb is None:
        return None
    target_bytes = float(target_size_gb) * (1024 ** 3)
    bitrate_bps = (target_bytes * 8.0) / float(duration_sec)
    return bitrate_bps

def choose_encoder_and_cmd(outfile, pix_fmt_input, target_size_gb, lossless, prefer_10bit):
    if not ffmpeg_exists():
        raise RuntimeError("ffmpeg not found in PATH. Install ffmpeg.")
    encs = get_available_encoders()
    use_nvenc = "hevc_nvenc" in encs or "h264_nvenc" in encs
    bitrate_bps = compute_bitrate_bps(target_size_gb, DURATION_SEC)
    cmd = build_ffmpeg_cmd(outfile, pix_fmt_input, use_nvenc, lossless, bitrate_bps, profile10=prefer_10bit)
    print("Using encoder:", "hevc_nvenc" if use_nvenc else "libx265 (software)")
    if bitrate_bps:
        print(f"Target size {target_size_gb} GB -> target bitrate {bitrate_bps/1e9:.3f} Gbit/s ({int(bitrate_bps/1000)} kb/s)")
    elif lossless:
        print("Lossless encoding requested.")
    return cmd

def generate_frame_values(n_pixels, mult, add, mask, frame_key):
    """
    Compute 24-bit unique values per pixel: vals = (i * mult + add) & mask,
    then mix with frame_key using XOR. This guarantees per-frame uniqueness
    and also guarantees vals ^ k1 != vals ^ k2 when k1 != k2.
    """
    idx = np.arange(n_pixels, dtype=np.uint32)
    vals = (idx * mult + add) & mask
    vals = vals ^ (np.uint32(frame_key) & mask)
    return vals

def vals_to_rgb48_bytes(vals, width, height):
    """
    Convert 24-bit vals into rgb48le bytes (uint16 little-endian per channel).
    We expand each 8-bit channel into 16-bit by duplication:
      e.g., R8 -> R16 = (R8 << 8) | R8
    This keeps color identity while providing the encoder higher bit depth input.
    """
    # Extract 8-bit channels
    r8 = ((vals >> np.uint32(16)) & np.uint32(0xFF)).astype(np.uint8)
    g8 = ((vals >> np.uint32(8)) & np.uint32(0xFF)).astype(np.uint8)
    b8 = (vals & np.uint32(0xFF)).astype(np.uint8)

    # Expand to uint16 by duplication to fill 16 bits (R8 -> R16 = R8<<8 | R8)
    r16 = ((r8.astype(np.uint16) << 8) | r8.astype(np.uint16)).reshape((height, width))
    g16 = ((g8.astype(np.uint16) << 8) | g8.astype(np.uint16)).reshape((height, width))
    b16 = ((b8.astype(np.uint16) << 8) | b8.astype(np.uint16)).reshape((height, width))

    # Stack (H,W,3) as uint16 and return little-endian bytes
    rgb16 = np.empty((height, width, 3), dtype=np.uint16)
    rgb16[:, :, 0] = r16
    rgb16[:, :, 1] = g16
    rgb16[:, :, 2] = b16
    # Ensure little-endian ordering for ffmpeg
    return rgb16.tobytes()

def vals_to_rgb24_bytes(vals, width, height):
    r = ((vals >> np.uint32(16)) & np.uint32(0xFF)).astype(np.uint8).reshape((height, width))
    g = ((vals >> np.uint32(8)) & np.uint32(0xFF)).astype(np.uint8).reshape((height, width))
    b = (vals & np.uint32(0xFF)).astype(np.uint8).reshape((height, width))
    rgb = np.empty((height, width, 3), dtype=np.uint8)
    rgb[:, :, 0] = r
    rgb[:, :, 1] = g
    rgb[:, :, 2] = b
    return rgb.tobytes()

def main():
    parser = argparse.ArgumentParser(description="Generate 4K frames with unique pixels and encode to high-quality HEVC")
    parser.add_argument("outfile", help="Output video file (mp4/mkv recommended)")
    parser.add_argument("--frames", type=int, default=FRAMES, help="Number of frames (default 600)")
    parser.add_argument("--width", type=int, default=W)
    parser.add_argument("--height", type=int, default=H)
    parser.add_argument("--fps", type=int, default=FPS)
    parser.add_argument("--pixfmt", choices=["rgb24", "rgb48le"], default="rgb48le", help="Input pixel format to ffmpeg (rgb48le gives higher precision)")
    parser.add_argument("--target-size-gb", type=float, default=None, help="Desired final file size in GB (e.g. 40). If set, encoder will be bitrate-targeted.")
    parser.add_argument("--lossless", action="store_true", help="Request lossless encode (overrides target-size).")
    parser.add_argument("--prefer-10bit", action="store_true", help="Request main10/p10 output (if encoder supports).")
    args = parser.parse_args()

    out = args.outfile
    frames = args.frames
    width = args.width
    height = args.height
    fps = args.fps
    pixfmt = args.pixfmt
    target_gb = args.target_size_gb
    lossless = args.lossless
    prefer10 = args.prefer_10bit

    n_pixels = width * height
    duration = frames / float(fps)
    print(f"Configuration: {width}x{height} @ {fps}fps, frames={frames}, duration={duration:.2f}s, pixfmt={pixfmt}")
    cmd = choose_encoder_and_cmd(out, pixfmt, target_gb, lossless, prefer10)
    print("ffmpeg command preview:")
    print(" ".join(cmd[:8]) + " ... " + " ".join(cmd[-6:]))
    print("Starting ffmpeg...")

    p = subprocess.Popen(cmd, stdin=subprocess.PIPE)

    try:
        for frame_idx in range(frames):
            # create a unique non-zero per-frame key (guaranteed different for each frame)
            frame_key = (np.uint32(frame_idx + 1) * KEY_MULT) & MASK24  # +1 avoids zero for frame 0

            vals = generate_frame_values(n_pixels, MULT, ADD, MASK24, frame_key)

            if pixfmt == "rgb48le":
                raw_bytes = vals_to_rgb48_bytes(vals, width, height)
            else:
                raw_bytes = vals_to_rgb24_bytes(vals, width, height)

            # write to ffmpeg stdin
            try:
                p.stdin.write(raw_bytes)
            except BrokenPipeError:
                print("ffmpeg pipe closed unexpectedly. Aborting.")
                break

            # explicit delete to free memory
            del vals
            del raw_bytes

            if (frame_idx + 1) % 10 == 0 or frame_idx == frames - 1:
                print(f"Wrote frame {frame_idx + 1}/{frames}")

    finally:
        if p.stdin:
            p.stdin.close()
        p.wait()
        print("ffmpeg finished with return code:", p.returncode)
        if p.returncode == 0:
            print("Video written successfully:", out)
        else:
            print("ffmpeg returned non-zero exit code. Check ffmpeg console log above for details.")

if __name__ == "__main__":
    main()
