#!/bin/bash
SRC="input.mov"
OUT_FOLDER="ETS2_4K_444_10bit_nvenc_500Mbps"
mkdir -p tmp_segments "$OUT_FOLDER"

# 1) Split into 30s segments (copies, fast). This yields clips: tmp_segments/clip_000.mov ... clip_011.mov
ffmpeg -y -i "$SRC" -c copy -map 0 -f segment -segment_time 30 -reset_timestamps 1 tmp_segments/clip_%03d.mov

# 2) Re-encode each segment with NVENC to 10-bit 4:4:4 HEVC
#    -pix_fmt yuv444p10le ensures 4:4:4 10-bit pixel format
#    -color metadata preserved (bt709)
#    Adjust -b:v to 500M (change if you want up to 1G)
for f in tmp_segments/clip_*.mov; do
  base=$(basename "$f" .mov)
  ffmpeg -y -hwaccel cuda -i "$f" \
    -map 0:v -map 0:a? \
    -c:v hevc_nvenc \
      -pix_fmt yuv444p10le \
      -profile:v main444_10 \
      -preset p4 \
      -rc vbr_hq \
      -cq 18 \
      -b:v 500M \
      -color_primaries bt709 -color_trc bt709 -colorspace bt709 \
    -c:a copy \
    "$OUT_FOLDER/${base}_444_10bit_nvenc_500M.mov"
done

echo "Done. Processed clips in ./$OUT_FOLDER"
