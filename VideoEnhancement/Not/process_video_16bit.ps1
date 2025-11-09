# process_video_16bit.ps1
# Usage:  .\process_video_16bit.ps1 -Input "input.mov" -Output "output.mov"

param(
    [string]$Input = "input.mov",
    [string]$Output = "enhanced.mov"
)

# Paths (edit if needed)
$ffmpeg  = "C:\Users\tech\Desktop\VideoEnhancement\ffmpeg.exe"
$ffprobe = "C:\Users\tech\Desktop\VideoEnhancement\ffprobe.exe"
$cudaexe = "C:\Users\tech\Desktop\VideoEnhancement\cuda_detail_boost_16bit.exe"

if (!(Test-Path $Input)) {
    Write-Host "❌ Input file not found: $Input"
    exit 1
}

# --- Probe width, height, fps ---
$meta = & $ffprobe -v error -select_streams v:0 `
    -show_entries stream=width,height,r_frame_rate,pix_fmt,sample_aspect_ratio `
    -of default=noprint_wrappers=1:nokey=1 $Input

if (-not $meta) {
    Write-Host "❌ ffprobe failed to read metadata"
    exit 1
}

$lines = $meta -split "`n"
$width  = $lines[0].Trim()
$height = $lines[1].Trim()
$fps_raw = $lines[2].Trim()
$pix_fmt = $lines[3].Trim()
$sar     = $lines[4].Trim()

# Convert "60/1" → 60
if ($fps_raw -match "/") {
    $parts = $fps_raw -split "/"
    $fps = [math]::Round([double]$parts[0] / [double]$parts[1], 3)
} else {
    $fps = [double]$fps_raw
}

Write-Host "📺 Detected ${width}x${height} ${fps}fps  ($pix_fmt SAR=$sar)"

# --- Launch FFmpeg + CUDA pipeline ---
# Make sure to use cmd /c to properly handle stdin/stdout pipes on Windows

$ffmpeg_decode = "`"$ffmpeg`" -hide_banner -loglevel error -i `"$Input`" -f rawvideo -pix_fmt rgba64le -vsync 0 -map 0:v -"
$cuda_run = "`"$cudaexe`" $width $height 1.15 1.35 80"
$ffmpeg_encode = "`"$ffmpeg`" -hide_banner -loglevel error -y -f rawvideo -pix_fmt rgba64le -s ${width}x${height} -r $fps -i - -c:v hevc_nvenc -preset slow -pix_fmt yuv444p16le -color_primaries bt709 -color_trc bt709 -colorspace bt709 -map 0:v -map 0:a? -c:a copy `"$Output`""

# Combine pipeline using cmd.exe (PowerShell pipes don’t stream binary properly)
$cmd = "$ffmpeg_decode | $cuda_run | $ffmpeg_encode"

Write-Host "🚀 Running pipeline..."
cmd /c $cmd
Write-Host "✅ Done. Output written to $Output"
