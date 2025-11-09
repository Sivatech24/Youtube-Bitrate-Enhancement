#!/bin/bash
# ==========================================================
# ETS2 8K60 HDR MASTER UPLOAD (Adaptive GPU/CPU Scaling)
# ==========================================================

SRC="input.mov"
OUT="ETS2_8K60_HDR_MASTER_$(date +%Y%m%d_%H%M%S)"
CHUNK_DURATION=30   # seconds per segment
BITRATE=500M
MAXRATE=600M
BUFSIZE=800M
HDR_META="-color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc"
mkdir -p "$OUT"

echo "------------------------------------------------------"
echo "🎬 Input:  $SRC"
echo "📁 Output Folder: $OUT"
echo "⚙️  Processing video in ${CHUNK_DURATION}s segments"
echo "------------------------------------------------------"

# ==========================================================
# Detect GPU scaling capability
# ==========================================================
if ffmpeg -hide_banner -filters | grep -q scale_cuda; then
  echo "✅ GPU scaling (scale_cuda) is supported."
  USE_GPU_SCALE=true
else
  echo "⚠️ GPU scaling not available. Falling back to CPU scaling."
  USE_GPU_SCALE=false
fi

# ==========================================================
# Get video duration
# ==========================================================
DURATION=$(ffprobe -v error -select_streams v:0 -show_entries stream=duration \
  -of default=noprint_wrappers=1:nokey=1 "$SRC")
DURATION=${DURATION%.*}  # integer seconds
SEGMENTS=$(( (DURATION + CHUNK_DURATION - 1) / CHUNK_DURATION ))

echo "⏱ Total duration: ${DURATION}s -> ${SEGMENTS} segment(s)"

# ==========================================================
# Process each segment
# ==========================================================
for ((i=0; i<SEGMENTS; i++)); do
  START=$((i * CHUNK_DURATION))
  OUTSEG="${OUT}/clip_${i}_8K60_HDR10.mov"
  
  echo "------------------------------------------------------"
  echo "▶️  Segment $((i+1)) / $SEGMENTS: Start=$STARTs -> ${OUTSEG}"
  echo "------------------------------------------------------"

  if [ "$USE_GPU_SCALE" = true ]; then
    # ===================== GPU PATH =====================
    ffmpeg -y \
      -ss "$START" -t "$CHUNK_DURATION" \
      -hwaccel cuda -hwaccel_output_format cuda \
      -i "$SRC" \
      -vf "scale_cuda=w=7680:h=4320:interp_algo=lanczos,format=p010le" \
      -c:v hevc_nvenc \
      -preset p7 -tune hq \
      -profile:v main10 \
      -pix_fmt p010le \
      -b:v $BITRATE -maxrate $MAXRATE -bufsize $BUFSIZE \
      -rc vbr -rc-lookahead 32 -spatial-aq 1 -aq-strength 10 -temporal-aq 1 \
      -g 120 -bf 3 \
      $HDR_META \
      -metadata title="ETS2 8K60 HDR Master Upload (GPU)" \
      "$OUTSEG"
  else
    # ===================== CPU PATH =====================
    ffmpeg -y \
      -ss "$START" -t "$CHUNK_DURATION" \
      -hwaccel cuda -hwaccel_output_format cuda \
      -i "$SRC" \
      -filter_complex "
        [0:v]hwdownload,format=nv12,
        scale=7680:4320:flags=lanczos,
        format=p010le,hwupload_cuda
      " \
      -c:v hevc_nvenc \
      -preset p7 -tune hq \
      -profile:v main10 \
      -pix_fmt p010le \
      -b:v $BITRATE -maxrate $MAXRATE -bufsize $BUFSIZE \
      -rc vbr -rc-lookahead 32 -spatial-aq 1 -aq-strength 10 -temporal-aq 1 \
      -g 120 -bf 3 \
      $HDR_META \
      -metadata title="ETS2 8K60 HDR Master Upload (CPU Chunked)" \
      "$OUTSEG"
  fi

  if [ $? -ne 0 ]; then
    echo "❌ Segment $((i+1)) failed — skipping."
  else
    echo "✅ Segment $((i+1)) completed successfully."
  fi
done

# ==========================================================
# Merge all segments into final HDR master
# ==========================================================
LIST_FILE="$OUT/segments.txt"
rm -f "$LIST_FILE"
for f in "$OUT"/clip_*.mov; do
  echo "file '$f'" >> "$LIST_FILE"
done

FINAL="$OUT/clip_8K60_HDR10_MASTER.mov"
echo "------------------------------------------------------"
echo "🔗 Merging all segments into: $FINAL"
echo "------------------------------------------------------"

ffmpeg -y -f concat -safe 0 -i "$LIST_FILE" -c copy "$FINAL"

if [ $? -eq 0 ]; then
  echo "✅ Final HDR master successfully created!"
  echo "📁 Output: $FINAL"
else
  echo "❌ Merge failed."
fi
