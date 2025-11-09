#!/bin/bash
set -euo pipefail

# ---------------- CONFIG ----------------
SRC="input.mov"                                # input file
OUT_FOLDER="ETS2_4K_VERTICAL_444_10bit_NVENC"
mkdir -p "$OUT_FOLDER"

OUT_W=2160
OUT_H=3840
FPS=60
PIX_FMT="yuv444p10le"
PROFILE="rext"
PRESET="p5"            # high quality, safe preset
CQ=12                  # constant quality
MASTERING_DISPLAY="G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1)"
MAX_CLL="1000,400"

# ---------------- STEP 1: Split input into 30s segments ----------------
echo "🔹 Splitting input into 30s segments..."
mkdir -p tmp_segments
ffmpeg -y -i "$SRC" -c copy -map 0 -f segment -segment_time 30 -reset_timestamps 1 tmp_segments/clip_%03d.mov

# ---------------- STEP 2: Encode each 30s segment ----------------
for SEG in tmp_segments/clip_*.mov; do
    BASE=$(basename "$SEG" .mov)
    echo "→ Processing clip: $BASE"

    ffmpeg -y -hwaccel cuda -i "$SEG" \
      -vf "scale=${OUT_W}:${OUT_H}:flags=lanczos,fps=${FPS},format=${PIX_FMT}" \
      -c:v hevc_nvenc \
        -pix_fmt $PIX_FMT \
        -profile:v $PROFILE \
        -preset $PRESET \
        -tune hq \
        -rc constqp \
        -cq $CQ \
        -b_ref_mode middle \
        -spatial-aq 1 -temporal-aq 1 -aq-strength 15 \
        -color_primaries bt2020 \
        -color_trc smpte2084 \
        -colorspace bt2020nc \
        -metadata:s:v:0 mastering-display="$MASTERING_DISPLAY" \
        -metadata:s:v:0 max-cll="$MAX_CLL" \
      -c:a copy \
      "$OUT_FOLDER/${BASE}_4K60_vertical_444_10bit_CQ${CQ}.mov"

    # Small pause to free GPU memory between clips
    sleep 1
done

echo "✅ Done. All 4K60 vertical HDR10 clips saved in: $OUT_FOLDER"
