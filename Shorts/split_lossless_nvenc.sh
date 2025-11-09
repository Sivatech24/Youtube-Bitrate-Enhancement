#!/bin/bash
# True-lossless NVENC 4:4:4 10-bit split encoder

SRC="input.mov"
OUT_FOLDER="ETS2_4K_444_10bit_NVENC_LOSSLESS"
TMP_FOLDER="tmp_segments"

mkdir -p "$TMP_FOLDER" "$OUT_FOLDER"

# --- Split the source into 30-second chunks (fast copy) ---
ffmpeg -y -i "$SRC" -c copy -map 0 \
  -f segment -segment_time 30 -reset_timestamps 1 \
  "$TMP_FOLDER/clip_%03d.mov"

# --- Re-encode each segment in lossless 10-bit 4:4:4 ---
for f in "$TMP_FOLDER"/clip_*.mov; do
  base=$(basename "$f" .mov)
  echo "Encoding $base.mov ..."
  ffmpeg -y -i "$f" \
  -map 0:v -map 0:a? \
  -c:v hevc_nvenc \
    -pix_fmt yuv444p10le \
    -profile:v rext \
    -preset p7 \
    -tune hq \
    -rc vbr_hq \
    -cq 12 \
    -b:v 1G \
    -color_primaries bt709 -color_trc bt709 -colorspace bt709 \
  -c:a copy \
  "$OUT_FOLDER/${base}_444_10bit_nvenc_1G.mov"
done

echo "All lossless clips saved in $OUT_FOLDER"

