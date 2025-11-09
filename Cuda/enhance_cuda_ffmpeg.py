
import sys
import subprocess
import shlex
import json
import math
import numpy as np
from tqdm import tqdm

# Try to import pycuda
try:
    import pycuda.autoinit
    import pycuda.driver as cuda
    from pycuda.compiler import SourceModule
except Exception as e:
    print("ERROR: pycuda import failed. Install pycuda and ensure CUDA drivers are available.")
    raise e

if len(sys.argv) < 3:
    print("Usage: python enhance_cuda_ffmpeg.py input.mov output.mp4")
    sys.exit(1)

INPUT = sys.argv[1]
OUTPUT = sys.argv[2]

# ---------- Helper: ffprobe to get metadata ----------
def ffprobe_get_stream_info(path):
    cmd = [
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "stream=width,height,avg_frame_rate,pix_fmt,sample_aspect_ratio",
        "-of", "json", path
    ]
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    data = json.loads(p.stdout)
    s = data.get("streams", [])[0]
    w = int(s["width"])
    h = int(s["height"])
    fps = 30.0
    if "avg_frame_rate" in s and s["avg_frame_rate"] != "0/0":
        num, den = map(int, s["avg_frame_rate"].split("/"))
        fps = num / den if den != 0 else fps
    sar = s.get("sample_aspect_ratio", "1:1")
    pix_fmt = s.get("pix_fmt", "")
    return dict(width=w, height=h, fps=fps, sar=sar, pix_fmt=pix_fmt)

info = ffprobe_get_stream_info(INPUT)
W, H, FPS = info['width'], info['height'], info['fps']
print(f"Probed: {W}x{H} @ {FPS:.3f} fps, sar={info['sar']}, src_pix_fmt={info['pix_fmt']}")

# ---------- CUDA kernel: enhance + tiny dither for banding prevention ----------
cuda_kernel = r"""
#include <stdint.h>

// input and output are uint16_t per component (RGB48: R,G,B each 16-bit)
extern "C" {
__global__ void enhance_kernel(unsigned short *img_in, unsigned short *img_out, int width, int height, float sharpen_strength, float contrast_boost, unsigned int seed) {
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x >= width || y >= height) return;
    int idx = (y * width + x) * 3;

    // load as floats in [0, 65535]
    float r = (float)img_in[idx + 0];
    float g = (float)img_in[idx + 1];
    float b = (float)img_in[idx + 2];

    // Simple local contrast-ish operation:
    // compute a crude local average using immediate neighbors (clamp at edges)
    float avgR = 0.0, avgG = 0.0, avgB = 0.0;
    int count = 0;
    for (int oy = -1; oy <= 1; ++oy) {
        int yy = y + oy;
        if (yy < 0 || yy >= height) continue;
        for (int ox = -1; ox <= 1; ++ox) {
            int xx = x + ox;
            if (xx < 0 || xx >= width) continue;
            int idn = (yy * width + xx) * 3;
            avgR += (float)img_in[idn + 0];
            avgG += (float)img_in[idn + 1];
            avgB += (float)img_in[idn + 2];
            count++;
        }
    }
    avgR /= max(1, count);
    avgG /= max(1, count);
    avgB /= max(1, count);

    // Unsharp-ish: boost difference from local average
    float rr = r + sharpen_strength * (r - avgR);
    float gg = g + sharpen_strength * (g - avgG);
    float bb = b + sharpen_strength * (b - avgB);

    // Contrast boost (simple gain around mid)
    float mid = 32768.0f;
    rr = (rr - mid) * contrast_boost + mid;
    gg = (gg - mid) * contrast_boost + mid;
    bb = (bb - mid) * contrast_boost + mid;

    // Clamp
    if (rr < 0.0f) rr = 0.0f;
    if (gg < 0.0f) gg = 0.0f;
    if (bb < 0.0f) bb = 0.0f;
    if (rr > 65535.0f) rr = 65535.0f;
    if (gg > 65535.0f) gg = 65535.0f;
    if (bb > 65535.0f) bb = 65535.0f;

    // Simple blue-noise-ish dithering to avoid blocks: add tiny pseudorandom jitter in [-4,4]
    // xorshift32
    unsigned int n = seed ^ (y*width + x);
    n ^= n << 13; n ^= n >> 17; n ^= n << 5;
    float jitter = ((float)(n & 0xFF) / 255.0f - 0.5f) * 8.0f; // [-4,4]

    // Apply jitter scaled down to 10-bit quantization step (16-bit->10-bit step=64)
    rr += jitter;
    gg += jitter;
    bb += jitter;

    // Save
    img_out[idx + 0] = (unsigned short) (rr + 0.5f);
    img_out[idx + 1] = (unsigned short) (gg + 0.5f);
    img_out[idx + 2] = (unsigned short) (bb + 0.5f);
}
}
"""

mod = SourceModule(cuda_kernel)
enhance_kernel = mod.get_function("enhance_kernel")

# ---------- Setup FFmpeg decode process (rawvideo rgb48le) ----------
# We choose rgb48le (uint16 per channel) so we keep high bit depth in the pipeline.
ffmpeg_dec_cmd = [
    "ffmpeg",
    "-y",
    "-hwaccel", "cuda",           # use cuda hwaccel if available (helps with some formats)
    "-i", INPUT,
    "-f", "rawvideo",
    "-pix_fmt", "rgb48le",        # 48-bit RGB (16bpc) -> numpy dtype uint16
    "-vsync", "0",
    "-vcodec", "rawvideo",
    "-",                          # pipe out
]

dec_proc = subprocess.Popen(ffmpeg_dec_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=10**8)

# ---------- Setup FFmpeg encode process (NVENC HEVC 10-bit 4:4:4, CBR) ----------
# We'll feed rgb48le frames back: ffmpeg will convert from rgb48le to yuv444p10le for the encoder.
# Use hevc_nvenc with profile main444-10 (10-bit 4:4:4).
bitrate = "80M"   # adjust as you like (CBR)
maxrate = bitrate
bufsize = "160M"
ffmpeg_enc_cmd = [
    "ffmpeg",
    "-y",
    "-f", "rawvideo",
    "-pix_fmt", "rgb48le",
    "-s", f"{W}x{H}",
    "-r", f"{FPS:.6f}",
    "-i", "-",                     # read our processed raw frames from stdin
    # Request NVENC encode in 10-bit 4:4:4
    "-c:v", "hevc_nvenc",
    "-profile:v", "main444-10",
    "-pix_fmt", "yuv444p10le",
    "-rc", "cbr",
    "-b:v", bitrate,
    "-maxrate", maxrate,
    "-bufsize", bufsize,
    # Tune options (change according to your GPU & ffmpeg build)
    "-rc-lookahead", "20",
    "-preset", "p7",               # NVENC preset (p1 fastest ... p7 slower/higher quality); change as desired
    OUTPUT
]
enc_proc = subprocess.Popen(ffmpeg_enc_cmd, stdin=subprocess.PIPE, stderr=subprocess.PIPE)

# Frame sizes for rgb48le
frame_bytes = W * H * 3 * 2  # 3 channels * 2 bytes per channel (uint16)

# Create GPU buffers
# we'll allocate two GPU buffers sized for one frame in uint16
frame_nbytes = frame_bytes
d_in = cuda.mem_alloc(frame_nbytes)
d_out = cuda.mem_alloc(frame_nbytes)

# Tiling/block config
block_x = 16
block_y = 16
grid_x = (W + block_x - 1) // block_x
grid_y = (H + block_y - 1) // block_y

# Parameters for kernel
sharpen_strength = np.float32(0.8)   # tune: 0.0..2.0
contrast_boost = np.float32(1.05)    # small contrast boost

# Read frames loop
frame_count = 0
try:
    # Optionally show progress if input file has known duration; we skip here and just stream.
    with tqdm(desc="Frames processed", unit="fr") as pbar:
        while True:
            raw = dec_proc.stdout.read(frame_bytes)
            if not raw or len(raw) < frame_bytes:
                break
            # Convert raw to numpy uint16 (little-endian)
            frame = np.frombuffer(raw, dtype=np.uint16).reshape((H, W, 3))
            # Upload to GPU
            cuda.memcpy_htod(d_in, frame)
            # Launch kernel
            seed = np.uint32((frame_count * 2654435761) & 0xFFFFFFFF)
            enhance_kernel(d_in, d_out, np.int32(W), np.int32(H), sharpen_strength, contrast_boost, seed,
                           block=(block_x, block_y, 1), grid=(grid_x, grid_y, 1))
            # Download
            out_frame = np.empty_like(frame)
            cuda.memcpy_dtoh(out_frame, d_out)
            # Write processed frame to encoder stdin
            enc_proc.stdin.write(out_frame.tobytes())
            frame_count += 1
            pbar.update(1)
finally:
    dec_proc.stdout.close()
    dec_proc.stderr.close()
    enc_proc.stdin.close()
    enc_proc.stderr.close()

# wait for processes to finish
enc_proc.wait()
dec_ret = dec_proc.wait()
print(f"Done. Frames processed: {frame_count}. ffmpeg decode exit code: {dec_ret}, encoder exit: {enc_proc.returncode}")
