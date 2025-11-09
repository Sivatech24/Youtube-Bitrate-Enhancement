#!/bin/bash
set -euo pipefail

SRC="input.mov"
TMP_SEGMENTS="tmp_segments_8k"
TMP_CHUNKS="tmp_chunks_8k"
OUT_FOLDER="ETS2_8K_VERTICAL_NVENC"

CHUNK_DURATION=1   # 1-second chunks to avoid OOM on 8K60
OUT_W=4320
OUT_H=7680
FPS=60
PIX_FMT="p010le"   # 10-bit 4:2:0 GPU-friendly
PROFILE="main10"
PRESET="p5"        # safer on 8K60
CQ=10
MASTERING_DISPLAY="G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1)"
MAX_CLL="1000,400"

mkdir -p "$TMP_SEGMENTS" "$TMP_CHUNKS" "$OUT_FOLDER"

# ---------------- STEP 1: Split into 30s segments ----------------
echo "🔹 Splitting input into 30s segments..."
ffmpeg -y -i "$SRC" -c copy -map 0 -f segment -segment_time 30 -reset_timestamps 1 "$TMP_SEGMENTS/clip_%03d.mov"

# ---------------- STEP 2: Process each 30s segment in 1s chunks ----------------
for SEG in "$TMP_SEGMENTS"/clip_*.mov; do
    BASE=$(basename "$SEG" .mov)
    echo "→ Processing 30s segment: $BASE"

    # Split into 1s chunks
    ffmpeg -y -i "$SEG" -c copy -map 0 -f segment -segment_time "$CHUNK_DURATION" -reset_timestamps 1 "$TMP_CHUNKS/${BASE}_part_%03d.mov"

    # Encode each chunk
    for CHUNK in "$TMP_CHUNKS"/${BASE}_part_*.mov; do
        CHUNK_BASE=$(basename "$CHUNK" .mov)
        echo "→ Encoding chunk: $CHUNK_BASE"

        ffmpeg -y -hwaccel cuda -i "$CHUNK" \
          -vf "scale=${OUT_W}:${OUT_H}:flags=lanczos,fps=${FPS},format=${PIX_FMT}" \
          -c:v hevc_nvenc \
            -pix_fmt $PIX_FMT \
            -profile:v $PROFILE \
            -preset $PRESET \
            -tune hq \
            -rc constqp \
            -cq $CQ \
            -color_primaries bt2020 \
            -color_trc smpte2084 \
            -colorspace bt2020nc \
            -metadata:s:v:0 mastering-display="$MASTERING_DISPLAY" \
            -metadata:s:v:0 max-cll="$MAX_CLL" \
          -c:a copy \
          "$TMP_CHUNKS/${CHUNK_BASE}_encoded.mov"

        # Pause to free GPU memory
        sleep 2
    done

    # ---------------- STEP 3: Concatenate encoded chunks ----------------
    CONCAT_FILE="$TMP_CHUNKS/${BASE}_concat.txt"
    rm -f "$CONCAT_FILE"
    for FINAL_CHUNK in "$TMP_CHUNKS"/${BASE}_part_*_encoded.mov; do
        if [[ -f "$FINAL_CHUNK" ]]; then
            echo "file '$(realpath "$FINAL_CHUNK")'" >> "$CONCAT_FILE"
        fi
    done

    ffmpeg -y -f concat -safe 0 -i "$CONCAT_FILE" -c copy "$OUT_FOLDER/${BASE}_8K60_vertical_final.mov"

    # Clean up temp chunks for this segment
    rm -f "$TMP_CHUNKS"/${BASE}_part_*.mov "$CONCAT_FILE"
done

echo "✅ Done. All 8K60 vertical HDR10 segments saved in: $OUT_FOLDER"
