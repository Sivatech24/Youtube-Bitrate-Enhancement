import subprocess
import os
import sys

def enhance_video(input_file, output_file="output_enhanced.mp4"):
    # Ensure input exists
    if not os.path.exists(input_file):
        print(f"[ERROR] Input file not found: {input_file}")
        sys.exit(1)

    # Get video info (resolution + aspect ratio)
    probe_cmd = [
        "ffprobe", "-v", "error",
        "-select_streams", "v:0",
        "-show_entries", "stream=width,height,display_aspect_ratio",
        "-of", "csv=p=0:s=x",
        input_file
    ]
    try:
        probe_result = subprocess.run(probe_cmd, capture_output=True, text=True, check=True)
        width, height, aspect = probe_result.stdout.strip().split("x")
        print(f"[INFO] Resolution: {width}x{height}, Aspect Ratio: {aspect}")
    except Exception as e:
        print("[WARNING] Could not read video info. Using default scaling.")
        width, height = None, None

    # FFmpeg enhancement pipeline:
    # -hwaccel cuda : use NVIDIA GPU acceleration
    # -pix_fmt yuv444p : use 4:4:4 chroma subsampling (more color detail)
    # -vf scale_cuda : upscale (optional), or just preserve original size
    # -c:v h264_nvenc : NVIDIA encoder
    # -rc:v vbr_hq : high quality variable bitrate
    # -b:v 50M : strong bitrate for better detail retention
    # -profile:v high444p : enable full color profile
    # -preset p7 : maximum quality
    # -tune hq : tuned for high quality

    ffmpeg_cmd = [
        "ffmpeg",
        "-y",  # overwrite
        "-hwaccel", "cuda",
        "-i", input_file,
        "-vf", f"scale_cuda={width}:{height},format=yuv444p",
        "-c:v", "h264_nvenc",
        "-profile:v", "high444p",
        "-rc:v", "vbr_hq",
        "-b:v", "50M",
        "-maxrate", "75M",
        "-preset", "p7",
        "-tune", "hq",
        "-pix_fmt", "yuv444p",
        "-c:a", "copy",  # copy original audio
        output_file
    ]

    print("[INFO] Starting video enhancement...")
    process = subprocess.run(ffmpeg_cmd, text=True)
    if process.returncode == 0:
        print(f"[SUCCESS] Enhanced video saved as: {output_file}")
    else:
        print("[ERROR] FFmpeg processing failed.")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python enhance_video.py <input.mp4 or input.mov>")
        sys.exit(1)

    input_path = sys.argv[1]
    enhance_video(input_path)
