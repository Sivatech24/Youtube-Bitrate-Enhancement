#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# ETS2 8K60 HDR SEGMENT EXPORT
# Splits into 30-second segments → upscale → encode each clip
# ==========================================================

SRC="input.mov"
OUT_DIR="ETS2_8K60_HDR_SEGMENTS_$(date +%Y%m%d_%H%M%S)"
CHUNK_DURATION=30
OUT_W=7680
OUT_H=4320
BITRATE="500M"
MAXRATE="600M"
BUFSIZE="800M"
FPS=60

HDR_META="-color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc"

mkdir -p "$OUT_DIR"

echo "------------------------------------------------------"
echo "🎬 Input:  $SRC"
echo "📁 Output Folder: $OUT_DIR"
echo "🎞️  Splitting every ${CHUNK_DURATION}s into HDR10 8K segments"
echo "------------------------------------------------------"

# Detect GPU scaling filter
if ffmpeg -hide_banner -filters | grep -q scale_cuda; then
  echo "✅ Using GPU scaling (scale_cuda)"
  USE_GPU_SCALE=true
else
  echo "⚠️ scale_cuda not found. Falling back to CPU scaling."
  USE_GPU_SCALE=false
fi

# Get duration (integer seconds)
DURATION=$(ffprobe -v error -select_streams v:0 -show_entries stream=duration \
  -of default=noprint_wrappers=1:nokey=1 "$SRC")
DURATION=${DURATION%.*}
SEGMENTS=$(( (DURATION + CHUNK_DURATION - 1) / CHUNK_DURATION ))

echo "⏱ Duration: ${DURATION}s  →  $SEGMENTS segments of ${CHUNK_DURATION}s"
echo

# ==========================================================
# Encode each 30-second segment
# ==========================================================
for ((i=0; i<SEGMENTS; i++)); do
  START=$((i * CHUNK_DURATION))
  OUT_SEG="${OUT_DIR}/clip_$(printf "%02d" "$i")_8K60_HDR10.mov"

  echo "▶️  Processing segment $((i+1)) / $SEGMENTS (Start ${START}s → ${CHUNK_DURATION}s)"

  if [ "$USE_GPU_SCALE" = true ]; then
    # ---------- GPU scaling path ----------
    ffmpeg -y \
      -ss "$START" -t "$CHUNK_DURATION" \
      -hwaccel cuda -hwaccel_output_format cuda -extra_hw_frames 8 \
      -i "$SRC" \
      -vf "scale_cuda=${OUT_W}:${OUT_H},format=p010le" \
      -r "$FPS" \
      -c:v hevc_nvenc -preset p7 -profile:v main10 -pix_fmt p010le \
      -b:v "$BITRATE" -maxrate "$MAXRATE" -bufsize "$BUFSIZE" \
      -rc vbr -rc-lookahead 32 -spatial-aq 1 -aq-strength 10 -temporal-aq 1 \
      -g 120 -bf 3 $HDR_META \
      -c:a copy \
      -metadata title="ETS2 8K60 HDR10 Segment $((i+1))" \
      "$OUT_SEG"
  else
    # ---------- CPU scaling fallback ----------
    ffmpeg -y \
      -ss "$START" -t "$CHUNK_DURATION" \
      -hwaccel cuda -hwaccel_output_format cuda -extra_hw_frames 8 \
      -i "$SRC" \
      -vf "scale=${OUT_W}:${OUT_H}:flags=lanczos,format=p010le" \
      -r "$FPS" \
      -c:v hevc_nvenc -preset p7 -profile:v main10 -pix_fmt p010le \
      -b:v "$BITRATE" -maxrate "$MAXRATE" -bufsize "$BUFSIZE" \
      -rc vbr -rc-lookahead 32 -spatial-aq 1 -aq-strength 10 -temporal-aq 1 \
      -g 120 -bf 3 $HDR_META \
      -c:a copy \
      -metadata title="ETS2 8K60 HDR10 Segment $((i+1))" \
      "$OUT_SEG"
  fi

  if [ $? -eq 0 ]; then
    echo "✅ Saved → $OUT_SEG"
  else
    echo "❌ Failed → segment $((i+1))"
  fi
  echo
done

echo "------------------------------------------------------"
echo "✅ All segments processed successfully!"
echo "📁 Output folder: $OUT_DIR"
echo "------------------------------------------------------"
