param(
    [string]$Input = "input.mp4",
    [string]$Output = "output_boosted.mp4"
)

# --- Get width/height ---
$ffprobe = "C:\ffmpeg\bin\ffprobe.exe"   # adjust path
$ffmpeg = "C:\ffmpeg\bin\ffmpeg.exe"     # adjust path
$cudaexe = "C:\Users\tech\Desktop\VideoEnhancement\cuda_detail_boost.exe"

$dim = & $ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 $Input
$width, $height = $dim -split ","

Write-Host "Detected: ${width}x${height}`n"

# --- Run pipeline ---
& $ffmpeg -hide_banner -y -i $Input `
  -f rawvideo -pix_fmt rgba -vsync 0 -map 0:v - `
| & $cudaexe $width $height 1.1 1.3 0.6 `
| & $ffmpeg -hide_banner -y `
  -f rawvideo -pix_fmt rgba64le -s "${width}x${height}" -r 30 -i - `
  -c:v hevc_nvenc -pix_fmt yuv444p16le -preset slow -rc vbr_hq -b:v 0 `
  -color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc `
  $Output
