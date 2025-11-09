#!/usr/bin/env bash
# encode_for_youtube.sh
# Usage: ./encode_for_youtube.sh "clip_000_8K60_10bit_CQ12.mov"
# Targets: safe chunked encoding, prefer NVENC (RTX 3050). Fallback to libx265 with AQ.
#
# Notes:
# - Adjust TARGET_W and TARGET_H to keep desired upload resolution.
# - Segments are encoded individually to limit memory/VRAM usage.
# - Requires ffmpeg with NVENC support (ffmpeg -encoders | grep nvenc) for hardware path.
# - Runs on WSL/Ubuntu assuming drivers + CUDA/NVENC support are installed when using hardware path.

set -euo pipefail

INPUT="$1"
WORKDIR="./workdir_encode"
OUT="output_for_youtube.mp4"
SEG_PREFIX="seg"
SEG_DIR="$WORKDIR/segments"
ENC_DIR="$WORKDIR/encoded"
SEG_DURATION=8               # seconds per chunk; small chunks reduce memory spikes
TARGET_W=3840                # change if you want different target (e.g., 2160)
TARGET_H=2160
GPU_DEVICE=0                 # GPU index for nvenc (usually 0)

mkdir -p "$SEG_DIR" "$ENC_DIR"

echo "1) Check ffmpeg for nvenc"
if ffmpeg -hide_banner -encoders 2>/dev/null | grep -iE "hevc_nvenc|nvenc" >/dev/null 2>&1; then
  NVENC_AVAILABLE=1
  echo " -> NVENC appears available. Will try hardware encode (hevc_nvenc)."
else
  NVENC_AVAILABLE=0
  echo " -> NVENC not found. Falling back to software x265 (libx265)."
fi

# create short segment list using ffmpeg's segmenter (safe, minimal memory)
echo "2) Splitting input into ${SEG_DURATION}s segments (container copy for speed)"
ffmpeg -hide_banner -y -i "$INPUT" -c copy -map 0 -f segment -segment_time "${SEG_DURATION}" -reset_timestamps 1 "$SEG_DIR/${SEG_PREFIX}_%04d.mkv"

echo "3) Encode each segment individually"

encode_nvenc() {
  local in="$1" out="$2"
  # NVENC HEVC 10-bit (p010le) pipeline, VBR high quality. Tune params to avoid VRAM explosion.
  ffmpeg -hide_banner -y -hwaccel nvdec -hwaccel_device "$GPU_DEVICE" -i "$in" \
    -vf "zscale=transfer=bt2020_ncl:primaries=bt2020:matrix=bt2020nc, \
         zscale=transfer=bt709:primaries=bt709:matrix=bt709, \
         scale=w=${TARGET_W}:h=${TARGET_H}:flags=lanczos,format=p010le" \
    -c:v hevc_nvenc \
      -preset p4 \
      -rc vbr_hq \
      -cq 19 \
      -b:v 0 \
      -profile:v main10 \
      -pix_fmt p010le \
      -rc-lookahead 20 \
      -surfaces 4 \
    -c:a copy \
    -movflags +faststart \
    "$out"
}

encode_x265() {
  local in="$1" out="$2"
  # Software x265 10-bit with strong adaptive quantization (best per-pixel allocation).
  # Uses small slice threading to keep per-process memory modest.
  ffmpeg -hide_banner -y -i "$in" \
    -vf "zscale=transfer=bt2020_ncl:primaries=bt2020:matrix=bt2020nc, \
         zscale=transfer=bt709:primaries=bt709:matrix=bt709, \
         scale=w=${TARGET_W}:h=${TARGET_H}:flags=lanczos,format=yuv420p10le" \
    -c:v libx265 \
      -preset slower \
      -x265-params "crf=18:aq-mode=3:aq-strength=0.8:vbv-maxrate=0:vbv-bufsize=0" \
      -threads 0 \
    -c:a copy \
    -movflags +faststart \
    "$out"
}

count=0
for seg in "$SEG_DIR"/${SEG_PREFIX}_*.mkv; do
  count=$((count+1))
  outseg="$ENC_DIR/enc_$(printf "%04d" "$count").mp4"
  echo " Encoding segment $count -> $(basename "$outseg")"
  if [ "$NVENC_AVAILABLE" -eq 1 ]; then
    # try nvenc; if it fails for any reason, fallback to x265 for that segment
    if ! encode_nvenc "$seg" "$outseg"; then
      echo "  NVENC encode failed for $seg — falling back to libx265 for this chunk."
      encode_x265 "$seg" "$outseg"
    fi
  else
    encode_x265 "$seg" "$outseg"
  fi
done

echo "4) Create concat list"
CONCAT_LIST="$WORKDIR/concat_list.txt"
rm -f "$CONCAT_LIST"
for f in "$ENC_DIR"/enc_*.mp4; do
  # ensure safe path quoting for ffmpeg concat demuxer
  echo "file '$PWD/$f'" >> "$CONCAT_LIST"
done

echo "5) Concatenating encoded segments"
ffmpeg -hide_banner -y -f concat -safe 0 -i "$CONCAT_LIST" -c copy -movflags +faststart "$OUT"

echo "Done. Output: $OUT"
echo "Cleanup: you can remove $WORKDIR if successful."
