import subprocess
import sys
import os
import shutil

def enhance_video(input_file, output_file="enhanced_output.mp4"):
    if not os.path.exists(input_file):
        print(f"[ERROR] File not found: {input_file}")
        sys.exit(1)

    if shutil.which("ffmpeg") is None:
        print("[ERROR] FFmpeg not found in PATH.")
        sys.exit(1)

    # 🧠 CUDA decode + zscale enhancement + HEVC NVENC encode (4:4:4 10-bit)
    ffmpeg_cmd = [
        "ffmpeg",
        "-y",
        "-hwaccel", "cuda",
        "-hwaccel_output_format", "cuda",
        "-i", input_file,

        # Enhancement chain — sharper, higher local contrast, better tone
        "-vf",
        (
            "format=yuv444p16le,"
            "unsharp=lx=5:ly=5:la=1.0:cx=3:cy=3:ca=0.5,"
            "eq=contrast=1.1:brightness=0.02:saturation=1.05,"
            "zscale=transfer=bt709:matrix=bt709:primaries=bt709,"
            "tonemap=reinhard:desat=0"
        ),

        # ✅ Correct NVENC encoder profile for 10-bit 4:4:4 (Rext)
        "-c:v", "hevc_nvenc",
        "-profile:v", "rext",
        "-pix_fmt", "yuv444p10le",
        "-preset", "p7",
        "-tune", "hq",
        "-rc:v", "vbr_hq",
        "-b:v", "75M",
        "-maxrate", "100M",
        "-bufsize", "200M",

        # Keep audio
        "-c:a", "copy",

        output_file
    ]

    print("[INFO] Executing FFmpeg command:")
    print(" ".join(ffmpeg_cmd))
    process = subprocess.run(ffmpeg_cmd)
    if process.returncode == 0:
        print(f"[SUCCESS] Enhanced video saved as: {output_file}")
    else:
        print("[ERROR] FFmpeg process failed!")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python cuda_enhance_video_fixed.py input.mov")
        sys.exit(1)
    enhance_video(sys.argv[1])
