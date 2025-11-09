#!/usr/bin/env python3
"""
enhance_with_cuda_stream.py
Usage:
    python enhance_with_cuda_stream.py input.mov [output.mov]

Requirements:
 - ffmpeg (with NVENC + cuvid/cuvid decoder) in PATH
 - nvcc-built cuda_detail_boost_stream.exe in same folder or PATH
 - Python 3.7+
"""

import subprocess
import json
import os
import sys
import shutil
import math

FFMPEG = "ffmpeg"       # or full path to ffmpeg.exe
FFPROBE = "ffprobe"
CUDA_TOOL = "cuda_detail_boost_stream.exe"  # compiled from above

def probe_video(path):
    cmd = [
        FFPROBE, "-v", "error", "-select_streams", "v:0",
        "-show_entries", "stream=width,height,r_frame_rate,pix_fmt,sample_aspect_ratio",
        "-of", "json", path
    ]
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError("ffprobe failed: " + p.stderr)
    info = json.loads(p.stdout)
    stream = info["streams"][0]
    width = int(stream["width"])
    height = int(stream["height"])
    fps_raw = stream.get("r_frame_rate", "0/1")
    # convert fps fraction to float (safe)
    if "/" in fps_raw:
        a,b = fps_raw.split("/")
        fps = float(a)/float(b) if float(b) != 0 else 0.0
    else:
        fps = float(fps_raw)
    pix_fmt = stream.get("pix_fmt", "")
    sar = stream.get("sample_aspect_ratio", "1:1")
    return width, height, fps, pix_fmt, sar

def main(input_path, output_path):
    if not os.path.exists(input_path):
        print("Input not found:", input_path); sys.exit(1)
    if shutil.which(FFMPEG) is None:
        print("ffmpeg not found in PATH"); sys.exit(1)
    if shutil.which(FFPROBE) is None:
        print("ffprobe not found in PATH"); sys.exit(1)
    if not os.path.exists(CUDA_TOOL) and shutil.which(CUDA_TOOL) is None:
        print("CUDA tool not found:", CUDA_TOOL); sys.exit(1)

    w,h,fps,pix_fmt,sar = probe_video(input_path)
    print(f"Detected: {w}x{h} @ {fps} fps, pix_fmt={pix_fmt}, SAR={sar}")

    # Use rgba64le for high precision throughput (16-bit per channel)
    pix_in = "rgba64le"
    pix_out = "rgba64le"

    # ffmpeg decode command: try GPU decode (cuvid/hevc_cuvid) if available, otherwise CPU decode.
    # We'll ask FFmpeg to produce rawvideo RGBA64LE to stdout.
    # Use -vsync 0 to preserve frames.
    decode_cmd = [
    FFMPEG,
    "-hide_banner", "-loglevel", "error",
    "-hwaccel", "cuda",
    "-i", input_path,
    "-vf", "hwdownload,format=rgba64le",
    "-pix_fmt", "rgba64le",
    "-f", "rawvideo",
    "-vsync", "0",
    "-"
    ]

    # cuda tool args: width, height, sharpen, sat, dither, seed
    cuda_args = [CUDA_TOOL, str(w), str(h), "1.15", "1.35", "80", "12345"]

    # ffmpeg encode command reading raw frames from stdin
    encode_cmd = [
        FFMPEG,
        "-hide_banner", "-loglevel", "error",
        "-f", "rawvideo",
        "-pix_fmt", pix_out,
        "-s", f"{w}x{h}",
        "-r", str(round(fps,3)),
        "-i", "-",   # read from stdin
        "-map", "0:v",
        "-c:v", "hevc_nvenc",
        "-profile:v", "rext",               # Range extensions for 4:4:4 10/16-bit
        "-pix_fmt", "yuv444p16le",
        "-preset", "p7",
        "-tune", "hq",
        "-rc", "vbr_hq",
        "-cq", "18",
        "-b:v", "0",
        "-maxrate", "200M",
        "-bufsize", "400M",
        "-c:a", "copy",   # copy audio (this will require mapping audio separately; we will remap)
        output_path
    ]

    # Because we want to preserve audio too, we'll run a separate ffmpeg step to mux audio
    # Option A: Use a temporary output video without audio and then copy audio from input.
    tmp_video = output_path + ".temp_no_audio.mp4"

    # Launch decode -> cuda -> encode pipeline:
    print("Starting pipeline: [ffmpeg decode] -> [cuda tool] -> [ffmpeg encode]")
    # Start decoder process (stdout pipe)
    p_decode = subprocess.Popen(decode_cmd, stdout=subprocess.PIPE)

    # Start cuda tool reading from decoder stdout, writing to stdout
    p_cuda = subprocess.Popen(cuda_args, stdin=p_decode.stdout, stdout=subprocess.PIPE)

    # Start encoder reading from cuda stdout and writing to temporary file (no audio)
    p_encode = subprocess.Popen(encode_cmd[:-3] + [tmp_video], stdin=p_cuda.stdout)

    # Close parent's references to pipes so processes get EOF correctly
    p_decode.stdout.close()
    p_cuda.stdout.close()

    rc_encode = p_encode.wait()
    rc_cuda = p_cuda.wait()
    rc_decode = p_decode.wait()

    if rc_encode != 0 or rc_cuda != 0 or rc_decode != 0:
        print("One of the pipeline processes failed. rc_decode", rc_decode, "rc_cuda", rc_cuda, "rc_encode", rc_encode)
        sys.exit(1)

    # Now mux audio from original input into final output (copy audio)
    print("Muxing audio from original into final file...")
    mux_cmd = [
        FFMPEG, "-hide_banner", "-loglevel", "error",
        "-i", tmp_video,
        "-i", input_path,
        "-c", "copy",
        "-map", "0:v",
        "-map", "1:a?",
        output_path
    ]
    subprocess.run(mux_cmd, check=True)

    # remove temporary file
    os.remove(tmp_video)
    print("Done. Output written to:", output_path)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python enhance_with_cuda_stream.py input.mov [output.mov]")
        sys.exit(1)
    input_path = sys.argv[1]
    output_path = sys.argv[2] if len(sys.argv) >= 3 else "enhanced_output.mp4"
    main(input_path, output_path)
