#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# ETS2 8K60 10-bit HEVC444 Split Script (CUDA Accelerated)
# For: i3-9100F + RTX 3050
# ==========================================================

# ---------------- CONFIG ----------------
SRC="input.mov"                    # input file
OUT_BASE="ETS2_8K60_44410_clips"   # base name for output folder

# Target bitrate — you can go up to 1000M (1 Gbps)
TARGET_BITRATE="500M"

# NVENC preset (p1=best quality, p7=fastest)
NVENC_PRESET="p1"

# Use constqp (nearly lossless)? Set to true only if you want pixel-perfect results (very large files)
USE_CONSTQP=false
CONSTQP_QP=0

# Use GPU scaling? true = CUDA scale; false = CPU scale
USE_GPU_SCALE=true

# Vertical 8K output resolution
OUT_W=4320
OUT_H=7680

# Output frame rate (keep consistent with input)
OUT_FPS=60

# Segment split times (30s each until 5:42)
SEG_TIMES="30,60,90,120,150,180,210,240,270,300,342.10"

# Output pattern
OUT_PATTERN="clip_%02d.mov"
# ----------------------------------------

# Timestamped output directory
TS=$(date +"%Y%m%d_%H%M%S")
OUT_DIR="${OUT_BASE}_${OUT_W}x${OUT_H}_${TARGET_BITRATE}_${TS}"
mkdir -p "$OUT_DIR"

# ----------------------------------------
# Build encoder arguments
# ----------------------------------------
COMMON_VENC_ARGS=( -c:v hevc_nvenc -preset "$NVENC_PRESET" -pix_fmt yuv444p10le )

if [ "$USE_CONSTQP" = true ]; then
  COMMON_VENC_ARGS+=( -rc constqp -qp "$CONSTQP_QP" )
else
  COMMON_VENC_ARGS+=( -rc vbr_hq -b:v "$TARGET_BITRATE" -maxrate "$TARGET_BITRATE" -bufsize 2000M )
  # Optional: Uncomment to enforce target quality
  # COMMON_VENC_ARGS+=( -cq 18 )
fi

# ----------------------------------------
# Audio settings (copy original AAC)
# ----------------------------------------
AUDIO_ARGS=( -c:a copy )

# ----------------------------------------
# Build video filter chain
# ----------------------------------------
if [ "$USE_GPU_SCALE" = true ]; then
  # ✅ CUDA scaling (no interp — not supported)
  VF_FILTER="scale_cuda=${OUT_W}:${OUT_H}:format=yuv444p10le,fps=${OUT_FPS}"
else
  # CPU scaling (fallback)
  VF_FILTER="scale=${OUT_W}:${OUT_H}:flags=lanczos,format=yuv444p10le,fps=${OUT_FPS}"
fi

# ----------------------------------------
# Run FFmpeg
# ----------------------------------------
ffmpeg -y \
  -hwaccel cuda -hwaccel_output_format cuda -extra_hw_frames 8 \
  -i "$SRC" \
  -filter_hw_device cuda \
  -vf "$VF_FILTER" \
  "${COMMON_VENC_ARGS[@]}" \
  -profile:v main444_10 \
  -g 60 \
  -color_range pc \
  -colorspace bt709 \
  -color_primaries bt709 \
  -color_trc bt709 \
  -map 0:v -map 0:a? \
  "${AUDIO_ARGS[@]}" \
  -f segment \
  -segment_times "$SEG_TIMES" \
  -reset_timestamps 1 \
  "$OUT_DIR/$OUT_PATTERN"

# ----------------------------------------
# Done
# ----------------------------------------
echo
echo "✅ All done!"
echo "📁 Output directory: $OUT_DIR"
echo "🎞️  Files: $OUT_PATTERN"
