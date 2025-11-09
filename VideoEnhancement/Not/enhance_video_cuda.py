import subprocess
import json
import shlex
import os
import sys

def get_video_info(input_file):
    """Extract resolution and pixel format using ffprobe"""
    cmd = [
        "ffprobe", "-v", "error",
        "-select_streams", "v:0",
        "-show_entries", "stream=width,height,pix_fmt",
        "-of", "json",
        input_file
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    info = json.loads(result.stdout)
    stream = info["streams"][0]
    width = stream["width"]
    height = stream["height"]
    pix_fmt = stream["pix_fmt"]
    return width, height, pix_fmt

def enhance_video(input_file, output_file):
    width, height, pix_fmt = get_video_info(input_file)

    print(f"Detected Resolution: {width}x{height}")
    print(f"Detected Pixel Format: {pix_fmt}")

    # Ensure pixel format is supported by CUDA (yuv444p16le for high depth)
    target_pix_fmt = "yuv444p16le" if "10" in pix_fmt or "16" in pix_fmt else "yuv444p"

    # Construct FFmpeg CUDA enhancement command
    cmd = [
        "ffmpeg",
        "-y",                            # Overwrite output
        "-hwaccel", "cuda",
        "-hwaccel_output_format", "cuda",
        "-c:v", "hevc_cuvid",            # Decode using NVIDIA HEVC
        "-i", input_file,
        "-vf", (
            f"hwupload_cuda,"
            f"scale_npp={width}:{height}:interp_algo=lanczos,"
            f"format={target_pix_fmt}"
        ),
        "-c:v", "hevc_nvenc",            # Encode using NVIDIA GPU
        "-profile:v", "main444_10",      # 10-bit 4:4:4 profile
        "-pix_fmt", target_pix_fmt,
        "-preset", "p7",                 # High-quality preset
        "-tune", "hq",
        "-rc", "vbr",
        "-cq", "18",                     # Quality target
        "-b:v", "0",                     # No fixed bitrate
        "-maxrate", "300M",
        "-bufsize", "600M",
        "-color_range", "pc",
        "-colorspace", "bt709",
        "-color_primaries", "bt709",
        "-color_trc", "bt709",
        output_file
    ]

    print("\n[INFO] Running CUDA enhancement...")
    print(" ".join(shlex.quote(c) for c in cmd))
    subprocess.run(cmd, check=True)
    print(f"\n✅ Enhanced video saved as: {output_file}")

def main():
    if len(sys.argv) < 2:
        print("Usage: python enhance_video_cuda.py <input_video>")
        sys.exit(1)

    input_file = sys.argv[1]
    if not os.path.exists(input_file):
        print(f"Error: File not found - {input_file}")
        sys.exit(1)

    base, ext = os.path.splitext(input_file)
    output_file = f"{base}_enhanced.mp4"
    enhance_video(input_file, output_file)

if __name__ == "__main__":
    main()
