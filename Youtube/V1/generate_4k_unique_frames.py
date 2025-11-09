import sys
import subprocess
import numpy as np
from shutil import which
from math import ceil

# ---------- CONFIG ----------
W = 3840
H = 2160
FRAMES = 600          # 60 fps * 10 seconds
FPS = 60
OUTFILE = sys.argv[1] if len(sys.argv) > 1 else "out_4k_unique.mp4"
# Choose multiplier and add as odd integers for modulo 2^24 arithmetic
MULT = np.uint32(1664525)   # odd multiplier
ADD = np.uint32(1013904223) # increment
MASK24 = np.uint32((1 << 24) - 1)
# A per-frame key multiply (keeps bijection)
KEY_MULT = np.uint32(2654435761)  # Knuth's constant
# ffmpeg encoding choice: try NVENC first, fallback to libx264
FFMPEG_NVENC_CMD = [
    "ffmpeg", "-y",
    "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
    "-c:v", "h264_nvenc", "-preset", "p4", "-rc", "vbr_hq", "-cq", "19",
    "-pix_fmt", "yuv420p", "-movflags", "+faststart",
    OUTFILE
]
FFMPEG_X264_CMD = [
    "ffmpeg", "-y",
    "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
    "-c:v", "libx264", "-preset", "slow", "-crf", "18",
    "-pix_fmt", "yuv420p", "-movflags", "+faststart",
    OUTFILE
]
# ----------------------------

def ffmpeg_available(cmd):
    """Return True if ffmpeg exists and the specified encoder seems usable.
       We do a lightweight check: ffmpeg must exist in PATH."""
    return which("ffmpeg") is not None

def choose_ffmpeg_cmd():
    if not ffmpeg_available("ffmpeg"):
        raise RuntimeError("ffmpeg not found in PATH. Install ffmpeg first.")
    # Try NVENC first by checking if ffmpeg supports h264_nvenc
    try:
        proc = subprocess.run(["ffmpeg", "-encoders"], capture_output=True, text=True, check=False)
        encoders = proc.stdout
        if "h264_nvenc" in encoders:
            print("Using h264_nvenc (NVidia hardware encoder).")
            return FFMPEG_NVENC_CMD
        else:
            print("NVENC not found; falling back to libx264 (CPU encoder).")
            return FFMPEG_X264_CMD
    except Exception:
        print("Could not check encoders; using libx264 fallback.")
        return FFMPEG_X264_CMD

def generate_frame_values(n_pixels, mult, add, mask, frame_key):
    """
    Vectorized generation:
    For index i (0..n_pixels-1) compute value = (i * mult + add) & mask
    Then XOR with frame_key (still bijection in 24-bit space).
    Returns numpy uint32 array of length n_pixels with values in [0, 2^24).
    """
    # arange fits in memory: n_pixels * 4 bytes ~ 33 MB for 8.3M -> okay
    idx = np.arange(n_pixels, dtype=np.uint32)
    vals = (idx * mult + add) & mask
    # Apply per-frame bijection (XOR mix)
    vals = vals ^ (np.uint32(frame_key) & mask)
    return vals

def vals_to_rgb_bytes(vals, width, height):
    """
    Convert the 1D uint32 vals to an HxWx3 uint8 RGB array and return bytes.
    vals are 24-bit values: R = bits[23:16], G = bits[15:8], B = bits[7:0]
    """
    # Extract channels
    r = ((vals >> np.uint32(16)) & np.uint32(0xFF)).astype(np.uint8)
    g = ((vals >> np.uint32(8)) & np.uint32(0xFF)).astype(np.uint8)
    b = (vals & np.uint32(0xFF)).astype(np.uint8)
    # reshape to H,W
    r = r.reshape((height, width))
    g = g.reshape((height, width))
    b = b.reshape((height, width))
    # Stack to H,W,3
    rgb = np.empty((height, width, 3), dtype=np.uint8)
    rgb[:, :, 0] = r
    rgb[:, :, 1] = g
    rgb[:, :, 2] = b
    return rgb.tobytes()

def main():
    n_pixels = W * H
    cmd = choose_ffmpeg_cmd()
    print(f"Output file: {OUTFILE}")
    print(f"Resolution: {W}x{H}, Frames: {FRAMES}, FPS: {FPS}")
    print("Starting ffmpeg...")

    # Start ffmpeg subprocess
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE)

    try:
        for frame_idx in range(FRAMES):
            # Frame key: multiply index by constant and mask. Keeps per-frame bijection.
            frame_key = (np.uint32(frame_idx) * KEY_MULT) & MASK24

            # Generate color values (vectorized)
            vals = generate_frame_values(n_pixels, MULT, ADD, MASK24, frame_key)

            # Convert to RGB bytes
            rgb_bytes = vals_to_rgb_bytes(vals, W, H)

            # Write raw frame to ffmpeg stdin
            p.stdin.write(rgb_bytes)

            # free memory more quickly
            del vals
            del rgb_bytes

            if (frame_idx + 1) % 10 == 0 or frame_idx == FRAMES - 1:
                print(f"Wrote frame {frame_idx + 1}/{FRAMES}")

    except BrokenPipeError:
        print("ffmpeg pipe closed unexpectedly.")
    finally:
        if p.stdin:
            p.stdin.close()
        p.wait()
        print("ffmpeg finished, return code:", p.returncode)
        if p.returncode == 0:
            print("Video written successfully.")
        else:
            print("ffmpeg returned non-zero exit code. Check ffmpeg console output for details.")

if __name__ == "__main__":
    main()
