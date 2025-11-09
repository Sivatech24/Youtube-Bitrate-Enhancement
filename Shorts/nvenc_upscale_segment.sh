#!/usr/bin/env bash
set -euo pipefail

# ---------------- CONFIG ----------------
SRC="input.mov"                    # input file
OUT_BASE="ETS2_8K60_44410_clips"   # base name for output folder
# Bitrate (change to "1000M" for 1 Gbit/s if you have storage/bandwidth)
TARGET_BITRATE="500M"
# NVENC preset: p1 (best/slower) ... p7 (fast). p1 is highest quality.
NVENC_PRESET="p1"
# Use lossless style? If true, will try constqp QP=0 (very large files). Set to true only if you want pixel-perfect and have disk.
USE_CONSTQP=false
CONSTQP_QP=0
# Use GPU scaling if your ffmpeg supports the CUDA "scale_cuda" filter.
# If true and filter exists, scale will be done on GPU. If not available ffmpeg will fail; switch to false.
USE_GPU_SCALE=true
# Output resolution for vertical 8K (width x height). For vertical orientation:
OUT_W=4320
OUT_H=7680
# Output fps (should match input 60fps; we'll set -r to ensure)
OUT_FPS=60
# Segment split times (30s increments until 300s, then final 342.10s)
SEG_TIMES="30,60,90,120,150,180,210,240,270,300,342.10"
# Filename pattern inside output folder
OUT_PATTERN="clip_%02d.mov"
# ----------------------------------------

# Create timestamped dir
TS=$(date +"%Y%m%d_%H%M%S")
OUT_DIR="${OUT_BASE}_${OUT_W}x${OUT_H}_${TARGET_BITRATE}_${TS}"
mkdir -p "$OUT_DIR"

# Build encoder args
COMMON_VENC_ARGS=( -c:v hevc_nvenc -preset "$NVENC_PRESET" -pix_fmt yuv444p10le )
if [ "$USE_CONSTQP" = true ]; then
  COMMON_VENC_ARGS+=( -rc constqp -qp "$CONSTQP_QP" )
else
  COMMON_VENC_ARGS+=( -rc vbr_hq -b:v "$TARGET_BITRATE" -maxrate "$TARGET_BITRATE" -bufsize 2000M )
  # Optional quality control value for vbr_hq:
  # COMMON_VENC_ARGS+=( -cq 18 )
fi

# Audio: copy original AAC
AUDIO_ARGS=( -c:a copy )

# Build vf (scaling + format)
if [ "$USE_GPU_SCALE" = true ]; then
  # GPU scaling (scale_cuda). Many ffmpeg + cuda builds have scale_cuda or scale_npp.
  # We're intentionally avoiding scale_npp (per your request) and using scale_cuda if available.
  VF_FILTER="scale_cuda=${OUT_W}:${OUT_H}:interp=lanczos,format=yuv444p10le"
else
  # CPU scaling fallback (lanczos) — more RAM/CPU usage but compatible.
  VF_FILTER="scale=${OUT_W}:${OUT_H}:flags=lanczos,format=yuv444p10le"
fi

# Run. This command:
# - uses hwaccel cuda for decoding where possible
# - forces output framerate to OUT_FPS
# - filters to requested size+pixelformat
# - encodes with hevc_nvenc 4:4:4 10-bit profile
ffmpeg -y \
  -hwaccel cuda -hwaccel_output_format cuda -extra_hw_frames 8 \
  -i "$SRC" \
  -r "$OUT_FPS" \
  -vf "$VF_FILTER" \
  "${COMMON_VENC_ARGS[@]}" \
  -map 0:v -map 0:a \
  "${AUDIO_ARGS[@]}" \
  -f segment \
  -segment_times "$SEG_TIMES" \
  -reset_timestamps 1 \
  "$OUT_DIR/$OUT_PATTERN"

echo
echo "Done. Clips are in: $OUT_DIR"
echo "Files named: $OUT_DIR/$OUT_PATTERN"
