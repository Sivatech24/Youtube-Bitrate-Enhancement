#!/bin/bash
set -euo pipefail

SRC="input.mov"
TMP="tmp_segments"
OUT="ETS2_8K_10bit_safe"
mkdir -p "$TMP" "$OUT"

# Step 1: Split into 30s segments (fast copy)
echo "Splitting source into 30s segments..."
ffmpeg -y -i "$SRC" -c copy -map 0 \
  -f segment -segment_time 30 -reset_timestamps 1 \
  "$TMP/clip_%03d.mov"

# function to encode single segment safely
encode_segment() {
  in="$1"
  base=$(basename "$in" .mov)
  out="$OUT/${base}_8k_10bit_safe.mov"

  echo "Encoding $in -> $out"

  # Upscale (high-quality Lanczos) to 7680x4320 and encode with NVENC (10-bit 4:2:0)
  # Tunings chosen to reduce VRAM usage:
  #  - pix_fmt yuv420p10le (much less memory than yuv444p10le)
  #  - preset p4 (good quality / less resource pressure than p7)
  #  - limit refs and b-frames (-refs 1 -bf 2)
  #  - rc constqp + qp 6 gives very high quality without exploding bitrate
  #  - surfaces=2 requests minimal NVENC input surfaces (may be ignored on some builds)
  ffmpeg -y -hwaccel cuda -hwaccel_output_format cuda -i "$in" \
    -vf "scale=7680:4320:flags=lanczos,fps=60" \
    -map 0:v -map 0:a? \
    -c:v hevc_nvenc \
      -pix_fmt yuv420p10le \
      -profile:v main10 \
      -preset p4 \
      -tune hq \
      -rc constqp -qp 6 \
      -bf 2 -refs 1 \
      -spatial-aq 1 -aq-strength 12 \
      -surfaces 2 \
    -c:a copy \
    "$out"

  # Give GPU a short breather so resources are released
  sleep 2
}

# loop and encode each segment one at a time
for seg in "$TMP"/clip_*.mov; do
  encode_segment "$seg"
done

echo "All segments processed -> $OUT"
