import subprocess
import sys
import os
import shutil

def enhance_video(input_file, output_file="enhanced_output.mp4"):
    if not os.path.exists(input_file):
        print(f"[ERROR] File not found: {input_file}")
        sys.exit(1)

    if shutil.which("ffmpeg") is None:
        print("[ERROR] FFmpeg not found in PATH. Install from https://ffmpeg.org")
        sys.exit(1)

    # ✅ Pipeline explanation:
    #   1. Decode video on GPU  → CUDA surfaces
    #   2. Download frames to CPU  → hwdownload
    #   3. Apply enhancement filters (CPU)
    #   4. Re-upload to GPU for NVENC encode

    ffmpeg_cmd = [
        "ffmpeg",
        "-y",
        "-hwaccel", "cuda",
        "-hwaccel_output_format", "cuda",
        "-i", input_file,

        # ---- Processing filters ----
        "-vf",
        (
            "hwdownload,format=yuv444p10le,"  # move from GPU to CPU RAM
            "unsharp=lx=5:ly=5:la=1.5:cx=3:cy=3:ca=0.8,"
            "eq=contrast=1.1:brightness=0.03:saturation=1.07,"
            "zscale=transfer=bt709:matrix=bt709:primaries=bt709,"
            "tonemap=reinhard:desat=0,"
            "hwupload_cuda,format=yuv444p10le"  # move back to GPU
        ),

        # ---- Encoding ----
        "-c:v", "hevc_nvenc",
        "-profile:v", "rext",          # HEVC Range Extensions (4:4:4 10-bit)
        "-pix_fmt", "yuv444p10le",
        "-preset", "p7",               # high quality
        "-tune", "hq",
        "-rc:v", "vbr_hq",
        "-b:v", "75M",
        "-maxrate", "100M",
        "-bufsize", "200M",

        # ---- Audio ----
        "-c:a", "copy",

        output_file
    ]

    print("[INFO] Running FFmpeg enhancement pipeline...")
    print(" ".join(ffmpeg_cmd))

    process = subprocess.run(ffmpeg_cmd)
    if process.returncode == 0:
        print(f"[SUCCESS] Enhanced video saved as: {output_file}")
    else:
        print("[ERROR] FFmpeg process failed!")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python cuda_enhance_video_final.py input.mov")
        sys.exit(1)
    enhance_video(sys.argv[1])
