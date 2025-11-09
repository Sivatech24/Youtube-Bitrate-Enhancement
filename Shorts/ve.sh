#!/bin/bash

SRC="input.mov"
OUT_FOLDER="ETS2_8K60_VERTICAL_MASTER"
mkdir -p tmp_segments "$OUT_FOLDER"

# Step 1: Split video into 30-second segments
ffmpeg -y -i "$SRC" -c copy -map 0 -f segment -segment_time 30 -reset_timestamps 1 tmp_segments/clip_%03d.mov

# Step 2: Encode each segment
for f in tmp_segments/clip_*.mov; do
  base=$(basename "$f" .mov)

  ffmpeg -y -hwaccel cuda -i "$f" \
    -vf "scale=4320:7680:flags=lanczos,format=p010le" \
    -c:v hevc_nvenc \
      -preset p5 \
      -profile:v main10 \
      -pix_fmt p010le \
      -rc constqp \
      -qp 10 \
      -rc-lookahead 0 \
      -no-scenecut 1 \
      -spatial-aq 0 \
      -temporal-aq 0 \
      -color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc \
    -c:a copy \
    "$OUT_FOLDER/${base}_8K60_VERTICAL_MASTER.mov"

  # Let GPU release resources between segments
  sleep 2
done

echo "✅ Done. All 8K60 vertical segments saved in: $OUT_FOLDER"
