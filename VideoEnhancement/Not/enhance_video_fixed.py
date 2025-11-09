import subprocess
import sys
import os

def enhance_video(input_file, output_file="output_enhanced.mp4"):
    if not os.path.exists(input_file):
        print(f"[ERROR] File not found: {input_file}")
        sys.exit(1)

    ffmpeg_cmd = [
        "ffmpeg",
        "-y",
        "-hwaccel", "cuda",
        "-hwaccel_output_format", "cuda",
        "-i", input_file,

        # Use software zscale to handle 10-bit 4:4:4 correctly
        "-vf", "zscale=transfer=bt709:matrix=bt709:primaries=bt709,format=yuv444p10le",

        "-c:v", "h264_nvenc",
        "-profile:v", "high444p",
        "-pix_fmt", "yuv444p10le",
        "-preset", "p7",
        "-rc:v", "vbr_hq",
        "-b:v", "50M",
        "-maxrate", "75M",
        "-tune", "hq",

        "-c:a", "copy",  # keep original audio
        output_file
    ]

    print("[INFO] Running FFmpeg command:")
    print(" ".join(ffmpeg_cmd))
    process = subprocess.run(ffmpeg_cmd)
    if process.returncode == 0:
        print(f"[SUCCESS] Output saved as {output_file}")
    else:
        print("[ERROR] FFmpeg failed!")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python enhance_video_fixed.py input.mov")
        sys.exit(1)
    enhance_video(sys.argv[1])
