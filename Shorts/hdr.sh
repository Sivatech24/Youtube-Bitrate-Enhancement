#!/bin/bash
SRC="input.mov"
OUT_FOLDER="ETS2_4K_444_10bit_NVENC_CQP"
mkdir -p tmp_segments "$OUT_FOLDER"

# Step 1: Split the video into 30s segments
ffmpeg -y -i "$SRC" -c copy -map 0 -f segment -segment_time 30 -reset_timestamps 1 tmp_segments/clip_%03d.mov

# Step 2: Encode each segment using NVENC Constant QP (CQP)
for f in tmp_segments/clip_*.mov; do
  base=$(basename "$f" .mov)
  ffmpeg -y -i "$f" \
  -vf "scale=7680:4320:flags=lanczos,fps=60" \
  -map 0:v -map 0:a? \
  -c:v hevc_nvenc \
    -pix_fmt yuv420p10le \
    -profile:v main10 \
    -preset p7 \
    -tune hq \
    -rc constqp -qp 12 \
    -spatial-aq 1 -aq-strength 15 \
    -temporal-aq 1 \
    -color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc \
  -c:a copy \
  "$OUT_FOLDER/${base}_8K60_10bit_CQ12.mov"
done

echo "Done. Processed clips saved in: $OUT_FOLDER"
