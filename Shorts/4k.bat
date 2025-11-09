@echo off
SETLOCAL ENABLEDELAYEDEXPANSION

REM ---------------- CONFIG ----------------
set "SRC=input.mov"
set "OUT_FOLDER=ETS2_4K_VERTICAL_444_10bit_NVENC_1G"
if not exist "%OUT_FOLDER%" mkdir "%OUT_FOLDER%"

set "OUT_W=2160"
set "OUT_H=3840"
set "FPS=60"
set "PIX_FMT=yuv444p10le"
set "PROFILE=rext"
set "PRESET=p5"
set "TARGET_BITRATE=1000M"
set "MASTERING_DISPLAY=G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1)"
set "MAX_CLL=1000,400"

REM Temporary folder for 30s clips
if not exist "tmp_segments" mkdir "tmp_segments"

REM ---------------- STEP 1: Split into 30s segments ----------------
echo 🔹 Splitting input into 30s segments...
ffmpeg -y -i "%SRC%" -c copy -map 0 -f segment -segment_time 30 -reset_timestamps 1 tmp_segments\clip_%%03d.mov

REM ---------------- STEP 2: Encode each segment ----------------
for %%F in (tmp_segments\clip_*.mov) do (
    set "BASE=%%~nF"
    echo → Processing clip: !BASE!

    ffmpeg -y -hwaccel cuda -i "%%F" ^
      -vf "scale=%OUT_W%:%OUT_H%:flags=lanczos,fps=%FPS%,format=%PIX_FMT%" ^
      -c:v hevc_nvenc ^
        -pix_fmt %PIX_FMT% ^
        -profile:v %PROFILE% ^
        -preset %PRESET% ^
        -tune hq ^
        -rc cbr_hq ^
        -b:v %TARGET_BITRATE% ^
        -maxrate %TARGET_BITRATE% ^
        -bufsize 2000M ^
        -b_ref_mode middle ^
        -spatial-aq 1 -temporal-aq 1 -aq-strength 15 ^
        -color_primaries bt2020 ^
        -color_trc smpte2084 ^
        -colorspace bt2020nc ^
        -metadata:s:v:0 mastering-display="%MASTERING_DISPLAY%" ^
        -metadata:s:v:0 max-cll="%MAX_CLL%" ^
      -c:a copy ^
      "%OUT_FOLDER%\!BASE!_4K60_vertical_444_10bit_1G.mov"

    REM Pause 1s to free GPU memory
    timeout /t 1 >nul
)

echo ✅ Done. All 4K60 vertical HDR10 clips saved in: %OUT_FOLDER%
pause
