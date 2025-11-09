#!/bin/bash
set -euo pipefail

SRC="input.mov"
TMP_FOLDER="tmp_segments"
TMP_ENCODED="tmp_encoded"
OUT_FOLDER="ETS2_8K60_VERTICAL_SAFE"

mkdir -p "$TMP_FOLDER" "$TMP_ENCODED" "$OUT_FOLDER"

# Step 1: Split source into 30-second segments
echo "🔹 Splitting input into 30s segments..."
ffmpeg -y -i "$SRC" -c copy -map 0 -f segment -segment_time 30 -reset_timestamps 1 "$TMP_FOLDER/clip_%03d.mov"

# Step 2: Process each 30s segment in 5s chunks
for SEG in "$TMP_FOLDER"/clip_*.mov; do
    BASE=$(basename "$SEG" .mov)
    echo "→ Processing 30s segment: $BASE"

    # Step 2a: Split 30s clip into 5s chunks
    ffmpeg -y -i "$SEG" -c copy -map 0 -f segment -segment_time 5 -reset_timestamps 1 "$TMP_ENCODED/${BASE}_part_%03d.mov"

    # Step 2b: Encode each 5s chunk safely with GPU
    for CHUNK in "$TMP_ENCODED"/${BASE}_part_*.mov; do
        CHUNK_BASE=$(basename "$CHUNK" .mov)
        echo "→ Encoding 5s chunk: $CHUNK_BASE"

        ffmpeg -y -hwaccel cuda -i "$CHUNK" \
          -vf "scale=4320:7680:flags=lanczos,fps=60,format=yuv420p10le" \
          -c:v hevc_nvenc \
            -pix_fmt p010le \
            -profile:v main10 \
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
          "$TMP_ENCODED/${CHUNK_BASE}_encoded.mov"

        # Free GPU memory between chunks
        sleep 5
    done

    # Step 2c: Concatenate encoded 5s chunks into final 30s segment
    CONCAT_FILE="$TMP_ENCODED/${BASE}_concat.txt"
    rm -f "$CONCAT_FILE"
    for FINAL_CHUNK in "$TMP_ENCODED"/${BASE}_part_*_encoded.mov; do
        echo "file '$FINAL_CHUNK'" >> "$CONCAT_FILE"
    done

    ffmpeg -y -f concat -safe 0 -i "$CONCAT_FILE" -c copy "$OUT_FOLDER/${BASE}_8K60_vertical_final.mov"

    # Clean up temp chunks for this segment
    rm -f "$TMP_ENCODED"/${BASE}_part_*.mov "$CONCAT_FILE"
done

echo "✅ Done. All 8K60 vertical HDR10 segments saved in: $OUT_FOLDER"
