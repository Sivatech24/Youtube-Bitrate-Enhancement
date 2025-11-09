import subprocess
import sys
import shlex

def enhance_stream(input_video, output_video):
    # ffmpeg decodes input -> rawvideo pipe -> cuda_detail_boost.exe -> ffmpeg encodes output
    cmd = f"""
    ffmpeg -hide_banner -loglevel error -hwaccel cuda -hwaccel_output_format cuda -i "{input_video}" ^
    -pix_fmt rgb48le -f rawvideo pipe: ^
    | cuda_detail_boost.exe ^
    | ffmpeg -y -f rawvideo -pix_fmt rgb48le -s $(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "{input_video}") -r $(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 "{input_video}") -i pipe: ^
    -c:v hevc_nvenc -profile:v main444_10 -pix_fmt yuv444p16le -preset p7 -tune hq -cq 18 "{output_video}"
    """

    print("[INFO] Running streaming enhancement...")
    subprocess.run(cmd, shell=True)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python enhance_stream_cuda.py <input_video>")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = "enhanced_output.mp4"
    enhance_stream(input_file, output_file)
    print(f"\n✅ Done! Enhanced video saved as {output_file}")
