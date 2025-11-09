#!/bin/bash

SRC="input.mov"
OUT_FOLDER="ETS2_8K60_VERTICAL_444_10bit_NVENC_CQ"
mkdir -p tmp_segments "$OUT_FOLDER"

# Step 1: Split source into 30-second segments
echo "🔹 Splitting input into 30s segments..."
ffmpeg -y -i "$SRC" -c copy -map 0 -f segment -segment_time 30 -reset_timestamps 1 tmp_segments/clip_%03d.mov

# Step 2: Encode each 30s segment (vertical 8K, 60 FPS, 10-bit)
echo "🔹 Encoding each segment to 8K vertical 60 FPS..."

for f in tmp_segments/clip_*.mov; do
  base=$(basename "$f" .mov)
  echo "→ Processing $base..."

  ffmpeg -y -hwaccel cuda -i "$f" \
    -vf "scale=4320:7680:flags=lanczos,fps=60,format=yuv444p10le" \
    -c:v hevc_nvenc \
      -pix_fmt yuv444p10le \
      -profile:v rext \
      -preset p7 \
      -tune hq \
      -rc constqp \
      -qp 10 \
      -b_ref_mode middle \
      -spatial-aq 1 -temporal-aq 1 -aq-strength 15 \
      -color_primaries bt2020 \
      -color_trc smpte2084 \
      -colorspace bt2020nc \
      -metadata:s:v:0 mastering-display="G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1)" \
      -metadata:s:v:0 max-cll="1000,400" \
    -c:a copy \
    "$OUT_FOLDER/${base}_8K60_VERTICAL_444_10bit_CQ10.mov"

done

echo "✅ Done. All 8K60 vertical HDR10 segments saved in: $OUT_FOLDER"
