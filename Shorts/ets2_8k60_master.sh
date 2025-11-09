#!/bin/bash
# ==========================================================
# ETS2 8K60 MASTER UPLOAD - CPU upscale + NVIDIA HEVC encode
# ==========================================================

SRC="input.mov"
OUT="ETS2_8K60_MASTER_UPLOAD_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT"

echo "------------------------------------------------------"
echo "Input:  $SRC"
echo "Output: $OUT/clip_8K60_MASTER_HEVC10.mov"
echo "Process: CPU upscale (8K) + NVIDIA HEVC 10-bit encode"
echo "------------------------------------------------------"

# Perform upscale + 10-bit HEVC encode
ffmpeg -y \
  -hwaccel cuda \
  -hwaccel_output_format cuda \
  -extra_hw_frames 8 \
  -i "$SRC" \
  -vf "scale=7680:4320:flags=lanczos,format=p010le" \
  -c:v hevc_nvenc \
  -preset p7 \
  -profile:v main10 \
  -pix_fmt p010le \
  -tune hq \
  -b:v 500M \
  -maxrate 600M \
  -bufsize 800M \
  -rc vbr \
  -rc-lookahead 32 \
  -spatial-aq 1 \
  -aq-strength 10 \
  -temporal-aq 1 \
  -g 120 \
  -bf 3 \
  -color_primaries bt2020 \
  -color_trc smpte2084 \
  -colorspace bt2020nc \
  -metadata title="ETS2 8K60 HDR Master Upload" \
  -metadata comment="Generated with FFmpeg - CPU upscale, HEVC NVENC 10-bit encode" \
  "$OUT/clip_8K60_MASTER_HEVC10.mov"

# ==========================================================
# Completion message
# ==========================================================
if [ $? -eq 0 ]; then
  echo "✅ 8K60 10-bit master video successfully created!"
  echo "📁 Output saved in: $OUT"
else
  echo "❌ FFmpeg encountered an error during processing."
fi
