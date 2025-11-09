import os
import subprocess
import sys
import shutil
from pathlib import Path

# -----------------------------
# CONFIGURATION
# -----------------------------
FFMPEG = "ffmpeg"  # Ensure ffmpeg is in PATH
CUDA_TOOL = "cuda_detail_boost.exe"  # Your custom CUDA enhancement executable
FRAME_DIR = "frames_input"
ENHANCED_DIR = "frames_enhanced"
OUTPUT_VIDEO = "enhanced_output.mp4"
TMP_EXT = ".png"  # use 16-bit PNG for max detail

# -----------------------------
# UTILITIES
# -----------------------------
def run(cmd):
    """Run a shell command safely."""
    print(f"\n[RUN] {' '.join(cmd)}")
    result = subprocess.run(cmd, stderr=subprocess.STDOUT)
    if result.returncode != 0:
        print("[ERROR] Command failed!")
        sys.exit(result.returncode)

# -----------------------------
# MAIN PIPELINE
# -----------------------------
def main(input_video):
    # Clean folders
    for d in [FRAME_DIR, ENHANCED_DIR]:
        if os.path.exists(d):
            shutil.rmtree(d)
        os.makedirs(d)

    # 1️⃣ Extract video frames using ffmpeg (preserve color & bit depth)
    print("\n[STEP 1] Extracting frames...")
    run([
        FFMPEG, "-hide_banner",
        "-i", input_video,
        "-pix_fmt", "rgb48le",   # 16-bit precision
        os.path.join(FRAME_DIR, "frame_%06d" + TMP_EXT)
    ])

    # 2️⃣ Run CUDA enhancement on each frame
    print("\n[STEP 2] Enhancing frames with CUDA...")
    for frame in sorted(Path(FRAME_DIR).glob(f"*{TMP_EXT}")):
        out_path = Path(ENHANCED_DIR) / frame.name
        cmd = [CUDA_TOOL, str(frame), str(out_path)]
        run(cmd)

    # 3️⃣ Get input video FPS
    print("\n[STEP 3] Getting original FPS...")
    probe = subprocess.run(
        [FFMPEG, "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=r_frame_rate",
         "-of", "default=noprint_wrappers=1:nokey=1", input_video],
        capture_output=True, text=True
    )
    fps_raw = probe.stdout.strip()
    fps_val = eval(fps_raw) if '/' in fps_raw else float(fps_raw)
    print(f"Detected FPS: {fps_val}")

    # 4️⃣ Recombine frames into final enhanced video
    print("\n[STEP 4] Re-encoding enhanced frames...")
    run([
        FFMPEG,
        "-framerate", str(fps_val),
        "-i", os.path.join(ENHANCED_DIR, "frame_%06d" + TMP_EXT),
        "-c:v", "hevc_nvenc",
        "-profile:v", "main444_10",
        "-pix_fmt", "yuv444p16le",
        "-preset", "p7",
        "-tune", "hq",
        "-b:v", "0",
        "-cq", "17",
        OUTPUT_VIDEO
    ])

    print(f"\n✅ Done! Enhanced video saved as: {OUTPUT_VIDEO}")

# -----------------------------
# ENTRY POINT
# -----------------------------
if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python enhance_pipeline.py <input_video>")
        sys.exit(1)

    input_video = sys.argv[1]
    if not os.path.exists(input_video):
        print(f"Error: Input file not found - {input_video}")
        sys.exit(1)

    main(input_video)
