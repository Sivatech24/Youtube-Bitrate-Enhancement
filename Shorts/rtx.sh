#!/bin/bash
set -euo pipefail

SRC="input.mov"
OUT_FOLDER="ETS2_8K60_VERTICAL_444_10bit_NVENC_CQ"
TMP_FOLDER="tmp_segments"

# Create necessary folders
mkdir -p "$TMP_FOLDER" "$OUT_FOLDER"

# Step 1: Split source into 30-second segments
echo "🔹 Splitting input into 30s segments..."
ffmpeg -y -i "$SRC" -c copy -map 0 -f segment -segment_time 30 -reset_timestamps 1 "$TMP_FOLDER/clip_%03d.mov"

# Step 2: Encode each segment safely
echo "🔹 Encoding each 30s segment to 8K vertical 60 FPS 10-bit 4:4:4..."

SEG_COUNT=0
for SEG in "$TMP_FOLDER"/clip_*.mov; do
    BASE=$(basename "$SEG" .mov)
    echo "→ Processing segment: $BASE"

    # Encode segment (CPU scaling to avoid GPU memory overflow)
    ffmpeg -y -i "$SEG" \
      -vf "scale=4320:7680:flags=lanczos,fps=60,format=yuv444p10le" \
      -c:v hevc_nvenc \
        -pix_fmt yuv444p10le \
        -profile:v rext \
        -preset p7 \
        -tune hq \
        -rc constqp \
        -qp 10 \
        -color_primaries bt2020 \
        -color_trc smpte2084 \
        -colorspace bt2020nc \
        -metadata:s:v:0 mastering-display="G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1)" \
        -metadata:s:v:0 max-cll="1000,400" \
      -c:a copy \
      "$OUT_FOLDER/${BASE}_8K60_VERTICAL_444_10bit_CQ10.mov"

    # Increment segment counter
    SEG_COUNT=$((SEG_COUNT+1))

    # Pause to allow GPU memory cleanup
    echo "🧹 Cleaning up GPU memory... (wait 10s)"
    sleep 10

    # Optional: reset NVENC every 3 segments (safe on Linux with nvidia-smi)
    if [ $SEG_COUNT -ge 3 ]; then
        echo "⚡ Resetting NVENC session to free GPU memory..."
        nvidia-smi --gpu-reset -i 0 > /dev/null 2>&1 || true
        sleep 5
        SEG_COUNT=0
    fi

done

echo "✅ Done. All 8K60 vertical HDR10 segments saved in: $OUT_FOLDER"
