#!/usr/bin/env bash
set -euo pipefail

# ==============================================================
# 8K60 10-Bit 4:4:4 HEVC Master Upload Script (auto GPU/CPU fallback)
# ==============================================================

SRC="input.mov"
OUT_BASE="ETS2_8K60_44410_MASTER_UPLOAD"
OUT_W=4320
OUT_H=7680
FPS=60
BITRATE="500M"
PRESET="p1"              # highest quality
OUT_PATTERN="clip_%02d.mov"
SEG_TIMES="30,60,90,120,150,180,210,240,270,300,342.10"

TS=$(date +%Y%m%d_%H%M%S)
OUT_DIR="${OUT_BASE}_${OUT_W}x${OUT_H}_${BITRATE}_${TS}"
mkdir -p "$OUT_DIR"

echo "=============================================================="
echo "🎬 Input:  $SRC"
echo "📁 Output: $OUT_DIR"
echo "=============================================================="

# detect scale_cuda
if ffmpeg -filters 2>/dev/null | grep -q scale_cuda; then
    echo "✅ Using GPU scaling (scale_cuda)"
    VF="scale_cuda=${OUT_W}:${OUT_H}:interp=lanczos,format=yuv444p10le"
else
    echo "⚠️ scale_cuda not available — falling back to CPU scale"
    VF="scale=${OUT_W}:${OUT_H}:flags=lanczos,format=yuv444p10le"
fi

ffmpeg -y \
  -hwaccel cuda \
  -hwaccel_output_format cuda \
  -i "$SRC" \
  -vf "$VF" \
  -c:v hevc_nvenc \
  -preset $PRESET \
  -pix_fmt yuv444p10le \
  -rc vbr_hq \
  -b:v $BITRATE \
  -maxrate $BITRATE \
  -bufsize 1000M \
  -tune hq \
  -spatial-aq 1 \
  -temporal-aq 1 \
  -aq-strength 10 \
  -rc-lookahead 32 \
  -g 120 \
  -bf 2 \
  -r $FPS \
  -c:a copy \
  -f segment \
  -segment_times "$SEG_TIMES" \
  -reset_timestamps 1 \
  "$OUT_DIR/$OUT_PATTERN"

EXIT=$?
echo
if [ $EXIT -eq 0 ]; then
    echo "=============================================================="
    echo "✅ Encoding complete — clips saved in:"
    echo "   $OUT_DIR"
    echo "=============================================================="
else
    echo "❌ Encoding failed (exit code: $EXIT)"
fi
