#!/bin/bash
SRC="input.mov"
OUT="ETS2_8K60_MASTER_UPLOAD"
mkdir -p "$OUT"

# 8K 10-bit upscale and HDR tagging using NVIDIA GPU
ffmpeg -y \
  -hwaccel cuda -hwaccel_output_format cuda \
  -i "$SRC" \
  -vf "
    scale_cuda=4320:7680:interp_algo=lanczos,
    colorspace_cuda=bt709:bt2020,
    format=p010le,
    fps=60
  " \
  -map 0:v -map 0:a? \
  -c:v hevc_nvenc \
    -pix_fmt p010le \
    -profile:v main10 \
    -preset p5 \
    -tune hq \
    -rc constqp -qp 10 \
    -bf 2 -refs 2 \
    -spatial-aq 1 -aq-strength 15 \
    -temporal-aq 1 \
    -color_primaries bt2020 \
    -color_trc smpte2084 \
    -colorspace bt2020nc \
  -c:a aac -b:a 320k \
  -f segment -segment_time 30 -reset_timestamps 1 \
  "$OUT/clip_%03d_8K60_MASTER_HEVC10.mov"

echo "✅ 8K60 10-bit HDR upload clips ready in: $OUT"
