import os
import sys
import subprocess
from shutil import which
import numpy as np
import argparse
from tqdm import tqdm
import math
import tempfile
import cv2

# ----------------- Defaults (you can override via CLI) -----------------
DEFAULT_W = 3840
DEFAULT_H = 2160
DEFAULT_FRAMES = 600   # 60fps * 10s
DEFAULT_FPS = 60
# 24-bit arithmetic constants (bijective within 24-bit)
MULT = np.uint32(1664525)
ADD = np.uint32(1013904223)
MASK24 = np.uint32((1 << 24) - 1)
KEY_MULT = np.uint32(2654435761)  # per frame key
# -----------------------------------------------------------------------

def ffmpeg_exists():
    return which("ffmpeg") is not None

def available_encoders():
    try:
        out = subprocess.run(["ffmpeg", "-encoders"], capture_output=True, text=True)
        return out.stdout
    except Exception:
        return ""

def choose_encoder(use_nvenc_if_available=True):
    encs = available_encoders()
    has_nvenc = ("hevc_nvenc" in encs) or ("h264_nvenc" in encs)
    if use_nvenc_if_available and has_nvenc:
        return "nvenc"
    return "libx265"

def compute_bitrate_for_size_gb(size_gb, duration_sec):
    """Return bitrate in bits per second required to reach target size."""
    if size_gb is None:
        return None
    bytes_target = float(size_gb) * (1024**3)
    bits = bytes_target * 8.0
    return bits / duration_sec

def generate_frame_values(n_pixels, mult, add, mask, frame_key):
    """
    Vectorized 24-bit mapping per pixel index -> 24-bit color value
    vals = (i * mult + add) & mask
    then XOR with frame_key (different per frame) to ensure per-position inter-frame difference.
    """
    idx = np.arange(n_pixels, dtype=np.uint32)
    vals = (idx * mult + add) & mask
    vals = vals ^ (np.uint32(frame_key) & mask)
    return vals

def vals_to_rgb48_uint16(vals, width, height):
    """Convert 24-bit vals into an HxWx3 uint16 array where each channel is 16-bit.
       We expand 8-bit to 16-bit by duplication: R16 = (R8<<8)|R8 (preserves color identity).
    """
    r8 = ((vals >> np.uint32(16)) & np.uint32(0xFF)).astype(np.uint8)
    g8 = ((vals >> np.uint32(8)) & np.uint32(0xFF)).astype(np.uint8)
    b8 = (vals & np.uint32(0xFF)).astype(np.uint8)
    r16 = ((r8.astype(np.uint16) << 8) | r8.astype(np.uint16)).reshape((height, width))
    g16 = ((g8.astype(np.uint16) << 8) | g8.astype(np.uint16)).reshape((height, width))
    b16 = ((b8.astype(np.uint16) << 8) | b8.astype(np.uint16)).reshape((height, width))
    rgb16 = np.empty((height, width, 3), dtype=np.uint16)
    rgb16[:, :, 0] = r16
    rgb16[:, :, 1] = g16
    rgb16[:, :, 2] = b16
    return rgb16

def write_png_uint16(path, arr_uint16):
    """
    Write a HxWx3 uint16 array to a PNG using OpenCV.
    We request minimal compression to slightly speed up and keep file larger (level 0).
    """
    # OpenCV expects BGR order for saving PNGs.
    bgr = arr_uint16[:, :, ::-1]
    # PNG compression level param: IMWRITE_PNG_COMPRESSION (0..9)
    cv2.imwrite(path, bgr, [cv2.IMWRITE_PNG_COMPRESSION, 0])

def create_frames(folder, width, height, frames, start_index=0):
    """Generate frames into folder as 16-bit PNGs named frame_000001.png ..."""
    os.makedirs(folder, exist_ok=True)
    n_pixels = width * height
    print(f"Generating {frames} frames of {width}x{height} into {folder}")
    for i in tqdm(range(frames), desc="Generating frames", unit="frame"):
        frame_idx = start_index + i
        frame_key = (np.uint32(frame_idx + 1) * KEY_MULT) & MASK24  # +1 to avoid zero key
        vals = generate_frame_values(n_pixels, MULT, ADD, MASK24, frame_key)
        rgb16 = vals_to_rgb48_uint16(vals, width, height)
        filename = os.path.join(folder, f"frame_{frame_idx:06d}.png")
        write_png_uint16(filename, rgb16)
        # release memory
        del vals
        del rgb16
    print("Frame generation done.")

def build_ffmpeg_encode_cmd(input_pattern, fps, encoder_choice, bitrate_bps, outfile, prefer_10bit=True, extra_args=None):
    """
    Build ffmpeg command to read PNG sequence and encode.
    input_pattern: e.g. /path/frame_%06d.png
    encoder_choice: 'nvenc' or 'libx265'
    bitrate_bps: None for CRF/lossless mode, otherwise bits/sec target
    prefer_10bit: request 10-bit output pixfmt when possible
    """
    cmd = ["ffmpeg", "-y", "-framerate", str(fps), "-i", input_pattern]
    if encoder_choice == "nvenc":
        # Use hevc_nvenc - set vbr with bitrate or lossless constqp
        if bitrate_bps is None:
            # lossless with nvenc
            cmd += ["-c:v", "hevc_nvenc", "-preset", "p1", "-rc", "constqp", "-qp", "0"]
        else:
            kbps = int(bitrate_bps / 1000)
            cmd += [
                "-c:v", "hevc_nvenc", "-preset", "p1", "-rc", "vbr_hq",
                "-b:v", f"{kbps}k", "-maxrate", f"{kbps}k", "-bufsize", f"{kbps*2}k"
            ]
        pix_out = "yuv420p10le" if prefer_10bit else "yuv420p"
        cmd += ["-pix_fmt", pix_out, outfile]
    else:
        # libx265
        if bitrate_bps is None:
            # not bitrate-targeted: use low CRF for very high quality
            cmd += ["-c:v", "libx265", "-preset", "veryslow", "-crf", "14"]
        else:
            kbps = int(bitrate_bps / 1000)
            cmd += ["-c:v", "libx265", "-preset", "veryslow", "-b:v", f"{kbps}k", "-maxrate", f"{kbps}k", "-bufsize", f"{kbps*2}k"]
        pix_out = "yuv420p10le" if prefer_10bit else "yuv420p"
        cmd += ["-pix_fmt", pix_out, outfile]
    if extra_args:
        # inject extra arguments before outfile if needed
        # (This is a simple append; for more precise placement modify as needed.)
        cmd = cmd[:-1] + extra_args + [cmd[-1]]
    return cmd

def run_ffmpeg(cmd):
    print("Running ffmpeg:")
    print(" ".join(cmd[:8]) + " ... " + " ".join(cmd[-6:]))
    p = subprocess.Popen(cmd)
    p.wait()
    return p.returncode

def parse_args():
    p = argparse.ArgumentParser(description="Generate 4K 16-bit PNG frames and encode to high-quality video.")
    p.add_argument("outfile", help="Output video file (mkV/mp4).")
    p.add_argument("--frames", type=int, default=DEFAULT_FRAMES)
    p.add_argument("--width", type=int, default=DEFAULT_W)
    p.add_argument("--height", type=int, default=DEFAULT_H)
    p.add_argument("--fps", type=int, default=DEFAULT_FPS)
    p.add_argument("--tmpdir", default=None, help="Temporary folder for frames (default: system temp).")
    p.add_argument("--target-size-gb", type=float, default=None, help="Desired video file size in GB (e.g. 10, 20). If omitted, uses high-quality CRF/lossless.")
    p.add_argument("--prefer-nvenc", action="store_true", help="Prefer NVENC (hevc_nvenc) if available.")
    p.add_argument("--cleanup", action="store_true", help="Delete PNG frames after encoding (IMPORTANT: make sure encode succeeded).")
    p.add_argument("--start-index", type=int, default=0, help="Start index for frame numbering (default 0).")
    return p.parse_args()

def main():
    args = parse_args()

    if not ffmpeg_exists():
        print("Error: ffmpeg not found in PATH. Install ffmpeg and retry.", file=sys.stderr)
        sys.exit(1)

    width = args.width
    height = args.height
    frames = args.frames
    fps = args.fps
    outfile = args.outfile
    target_gb = args.target_size_gb
    prefer_nvenc_flag = args.prefer_nvenc
    start_idx = args.start_index

    duration = frames / float(fps)
    bitrate_bps = compute_bitrate_for_size_gb(target_gb, duration) if target_gb else None

    encoder_choice = choose_encoder(use_nvenc_if_available=prefer_nvenc_flag)
    print(f"Encoder chosen: {encoder_choice} (prefer_nvenc={prefer_nvenc_flag})")
    if target_gb:
        print(f"Target size: {target_gb} GB -> target bitrate {bitrate_bps/1e9:.6f} Gbit/s")

    tmpdir = args.tmpdir or os.path.join(tempfile.gettempdir(), "v2_frames_" + next(tempfile._get_candidate_names()))
    print("Frames temporary folder:", tmpdir)
    # warn about disk space
    print("WARNING: PNG frames (16-bit) will be large. Ensure you have plenty of disk space.")

    # Create frames
    try:
        create_frames(tmpdir, width, height, frames, start_index=start_idx)
    except Exception as e:
        print("Frame generation failed:", e, file=sys.stderr)
        sys.exit(1)

    # Build ffmpeg command using the PNG sequence
    input_pattern = os.path.join(tmpdir, "frame_%06d.png")
    cmd = build_ffmpeg_encode_cmd(input_pattern, fps, encoder_choice, bitrate_bps, outfile, prefer_10bit=True)
    rc = run_ffmpeg(cmd)
    if rc != 0:
        print("ffmpeg failed with return code", rc, file=sys.stderr)
        print("You can try switching encoder (--prefer-nvenc), lowering preset, or changing target size.", file=sys.stderr)
        sys.exit(rc)
    else:
        print("Encoding finished. Output:", outfile)
        if args.cleanup:
            print("Cleaning up frame files...")
            for f in os.listdir(tmpdir):
                try:
                    os.remove(os.path.join(tmpdir, f))
                except Exception:
                    pass
            try:
                os.rmdir(tmpdir)
            except Exception:
                pass
            print("Cleanup done.")

if __name__ == "__main__":
    main()
