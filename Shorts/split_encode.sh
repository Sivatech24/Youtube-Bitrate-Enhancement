#!/bin/bash

# --- Configuration ---
INPUT_FILE="input.mov"
OUTPUT_DIR="Processed_ETS2_Clips_4K_to_8K"
CLIP_DURATION=30
TOTAL_CLIPS=10
FINAL_DURATION="00:00:42.10"

# --- Output and Encoding Options ---
# -s 4320x7680: Sets the output resolution (bypassing the failing 'scale' filter)
# -c:v hevc_nvenc: CUDA HEVC Encoder
# -pix_fmt yuv444p10msble: Compatible 10-bit 4:4:4 format
# -preset p7: Slowest/Highest Quality Preset
# -rc constqp -cq 5: Near-lossless Constant Quantization Parameter (CQ 5)
FFMPEG_OPTIONS="-s 4320x7680 -c:v hevc_nvenc -pix_fmt yuv444p10msble -preset p7 -rc constqp -cq 5 -qmin 0 -qmax 51 -vsync 0 -map 0:v -map 0:a -c:a copy"

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

echo "Starting high-quality 8K vertical video segmentation (Attempt 1: Using -s option)..."

# --- Loop for 30-Second Clips (Clips 1 to 11) ---
for i in $(seq 0 $TOTAL_CLIPS); do
    CLIP_NUMBER=$((i + 1))
    OFFSET_TIME=$((i * CLIP_DURATION))
    START_TIME=$(printf '%02d:%02d:%02d.00' $((OFFSET_TIME / 3600)) $(((OFFSET_TIME / 60) % 60)) $((OFFSET_TIME % 60)))

    if [ $i -lt $TOTAL_CLIPS ]; then
        OUTPUT_FILE="${OUTPUT_DIR}/ETS2_Clip_$(printf "%02d" $CLIP_NUMBER).mov"
        echo "Processing Clip $CLIP_NUMBER (Start: $START_TIME, Duration: $CLIP_DURATION sec)..."
        
        ffmpeg -y -hide_banner \
            -ss $START_TIME -i "$INPUT_FILE" -t $CLIP_DURATION \
            $FFMPEG_OPTIONS "$OUTPUT_FILE"
            
    elif [ $i -eq $TOTAL_CLIPS ]; then
        LAST_START_TIME="00:05:00.00"
        OUTPUT_FILE="${OUTPUT_DIR}/ETS2_Clip_$(printf "%02d" $CLIP_NUMBER)_FINAL.mov"
        echo "Processing Final Clip $CLIP_NUMBER (Start: $LAST_START_TIME, Duration: $FINAL_DURATION)..."
        
        ffmpeg -y -hide_banner \
            -ss $LAST_START_TIME -i "$INPUT_FILE" -t $FINAL_DURATION \
            $FFMPEG_OPTIONS "$OUTPUT_FILE"
    fi
    
    if [ $? -ne 0 ]; then
        echo "❌ ERROR: FFmpeg failed on clip $CLIP_NUMBER. Stopping."
        exit 1
    fi
    echo "✅ Clip $CLIP_NUMBER finished."
done

echo "🎉 All clips have been processed and saved to the '$OUTPUT_DIR' folder."