#!/bin/bash
SRC="input.mov"
OUT="ETS2_8K60_MASTER_UPLOAD"
mkdir -p "$OUT"

# 8K upscale and 10-bit HEVC master using NVIDIA hardware
ffmpeg -y \
  -hwaccel cuda -hwaccel_output_format cuda \
  -i "$SRC" \
  -vf "
    scale_npp=7680:4320:format=p010le:interp_algo=lanczos,
    unsharp=5:5:1.2:5:5:0.0,
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
  "$OUT/clip_8K60_MASTER_HEVC10.mov"

echo "✅ 8K60 10-bit HDR upload master ready: $OUT"
