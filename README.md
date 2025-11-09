# Youtube-Bitrate-Enhancement

Here’s a clean, professional **`README.md`** you can include with your FFmpeg + CUDA video enhancement workflow project it explains **v1**, **v2**, and the **YouTube-optimized version**, including what improvements each version brings, the rationale behind pixel-level processing, and how it achieves better clarity and compression results when uploaded to YouTube.

---

````markdown
# 🎥 FFmpeg + CUDA Video Enhancement Pipeline

GPU-accelerated FFmpeg pipeline for **enhancing video detail, precision, and color fidelity** using NVIDIA RTX GPUs (tested on RTX 3050).  
Designed to maximize **clarity and visual depth** before YouTube upload, ensuring **higher quality playback** and less compression artifacting.

---

## 🚀 Overview

Modern YouTube encoding pipelines apply aggressive compression that often reduces color precision, sharpness, and fine details especially in high-motion or dark scenes.

This project provides an **FFmpeg + CUDA** workflow that:
- Enhances every pixel using **4:4:4 chroma** and **10-bit color depth**.
- Uses **NVIDIA NVENC** for efficient GPU encoding.
- Maintains **constant bitrate (CBR)** for predictable, high-quality output.
- Optimizes the color space (BT.2020 + PQ curve) for HDR-accurate YouTube uploads.

---

## ⚙️ Version History

### 🔹 **Version 1 — Base GPU Enhancement**
- Uses CUDA for upscaling and decoding.
- Converts video to **YUV444P10LE** (10-bit 4:4:4).
- Applies mild contrast, brightness, and saturation adjustments.
- Encodes with **HEVC Main10 profile** at 120–150 Mbps CBR.

**Command Example:**
```bash
ffmpeg -hwaccel cuda -hwaccel_output_format cuda -i "input.mov" \
-vf "scale_cuda=format=yuv444p16le,hwdownload,format=yuv444p16le,eq=contrast=1.1:brightness=0.02:saturation=1.1" \
-c:v hevc_nvenc -pix_fmt yuv444p10le -preset p7 -tune hq \
-b:v 150M -maxrate 150M -bufsize 150M -rc cbr -profile:v main10 \
-colorspace bt2020nc -color_primaries bt2020 -color_trc smpte2084 \
"enhanced_v1_10bit444.mp4"
````

---

### 🔹 **Version 2 — Advanced Pixel Fidelity**

* Improves the **per-pixel processing chain** with CUDA precision scaling.
* Enhances sharpness and local contrast using tuned filters.
* Produces a **visually lossless intermediate master** for editing and color grading.
* Suitable for **post-production pipelines** before final export.

**Command Example:**

```bash
ffmpeg -hwaccel cuda -hwaccel_output_format cuda -i "input.mov" \
-vf "scale_cuda=format=yuv444p16le,hwdownload,format=yuv444p16le,unsharp=5:5:0.6,eq=contrast=1.15:saturation=1.1" \
-c:v hevc_nvenc -pix_fmt yuv444p10le -preset p7 -tune hq \
-b:v 150M -maxrate 150M -bufsize 150M -rc cbr -profile:v main10 \
-colorspace bt2020nc -color_primaries bt2020 -color_trc smpte2084 \
"enhanced_v2_pixelmaster.mp4"
```

---

### 🔹 **YouTube Upload Enhancement Mode**

This version is tuned for **optimal YouTube encoding results**:

* Keeps every pixel distinct (no chroma subsampling).
* Uses **CBR 150 Mbps** to preserve clarity before YouTube re-encoding.
* Outputs in **HDR (BT.2020, PQ)** forcing YouTube to allocate a higher bitrate on processing.
* Delivers sharper, richer detail and smoother gradients after upload.

**Command Example:**

```bash
ffmpeg -hwaccel cuda -hwaccel_output_format cuda -i "input.mov" \
-vf "scale_cuda=format=yuv444p16le,hwdownload,format=yuv444p16le,eq=contrast=1.1:brightness=0.02:saturation=1.1" \
-c:v hevc_nvenc -pix_fmt yuv444p10le -preset p7 -tune hq \
-b:v 150M -maxrate 150M -bufsize 150M -rc cbr -profile:v main10 \
-colorspace bt2020nc -color_primaries bt2020 -color_trc smpte2084 \
"enhanced_youtube_master.mp4"
```

---

## 🧠 Why It Looks Better on YouTube

1. **4:4:4 chroma sampling** prevents color bleeding between pixels.
2. **10-bit depth** reduces banding and preserves smooth gradients.
3. **CBR encoding** ensures consistent quality per frame (preferred for high-end content).
4. **BT.2020 + PQ HDR metadata** forces YouTube to assign higher transcoding bitrates.
5. **GPU pipeline** ensures zero CPU bottlenecks during processing.

---

## 📈 Recommended Upload Workflow

1. Edit or color-grade the original source (if needed).
2. Export or enhance using Version 2 or YouTube mode.
3. Upload directly to YouTube (keep file name simple and HDR metadata intact).
4. Wait until the **VP9 or AV1** 4K version becomes available (YouTube’s high-quality encode).

---

## 💡 Tips

* For 8K or high-motion footage, increase bitrate to `200M`.
* For archive masters, use **ProRes 4444 XQ** instead of HEVC.
* For GPU load balancing, add `-rc-lookahead 32` and `-spatial-aq 1` for adaptive quality.

---

## 🖥️ Tested Hardware

* **GPU:** NVIDIA RTX 3050 8GB
* **CPU:** Intel Core i3-9100F
* **OS:** Windows 10 / Windows 11
* **FFmpeg Build:** `ffmpeg-n5.1+cuda` or later (with `hevc_nvenc`, `scale_cuda`)

---

## 🏁 Result

After re-encoding with CUDA + FFmpeg:

* The resulting 10-bit 4:4:4 master maintains **pixel-level detail**.
* YouTube’s re-encode (VP9 or AV1) retains **significantly more texture, depth, and dynamic range**.
* Ideal for cinematic driving videos, gameplay recordings, and HDR content creation.

---

**© 2025 Video Enhancement Pipeline by [Coding Master 24]**
Licensed under MIT — use freely for research, creative, and professional video enhancement.

```

---
