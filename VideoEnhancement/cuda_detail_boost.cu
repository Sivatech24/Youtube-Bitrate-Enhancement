// cuda_detail_boost.cu
// Compile: nvcc -O3 -arch=sm_60 -o cuda_detail_boost cuda_detail_boost.cu
//
// Usage: ./cuda_detail_boost <width> <height>
// Reads raw RGBA (8-bit per channel) frames from stdin, writes RGBA64LE (uint16_t per channel, little-endian) to stdout.
//
// Notes:
// - Input frame format: width*height*4 bytes (R,G,B,A) each 8-bit
// - Output frame format: width*height*8 bytes (R,G,B,A) each uint16_t (little-endian)
// - Kernel performs: simple 3x3 blur -> unsharp mask sharpening, saturation boost, slight per-pixel jitter/dither,
//   then scales 8-bit range to 16-bit (value*257) for richer encoding precision.

#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cuda_runtime.h>
#include <cmath>
#include <string>
#include <iostream>

#define CHECK_CUDA(call) do { cudaError_t err = (call); if (err != cudaSuccess) { \
    fprintf(stderr, "CUDA error %s:%d '%s'\n", __FILE__, __LINE__, cudaGetErrorString(err)); exit(1);} } while(0)

__device__ inline float clampf(float v, float a, float b) {
    return v < a ? a : (v > b ? b : v);
}

// kernel: input 8-bit RGBA (uchar4). Output 16-bit RGBA (uint16_t per component).
// We read image in uchar4 packed array, perform processing and write uint16_t RGBA in output buffer.
__global__ void detail_boost_kernel(const uint8_t* in, uint16_t* out, int w, int h,
                                    float sharpen_amt, float sat_amt, float dither_amp, uint32_t frame_seed)
{
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x >= w || y >= h) return;
    int idx = (y * w + x) * 4;

    // read center pixel
    float cr = in[idx + 0];
    float cg = in[idx + 1];
    float cb = in[idx + 2];
    float ca = in[idx + 3];

    // compute simple 3x3 blur (average of neighbors including self) for unsharp mask
    float br = 0.0f, bg = 0.0f, bb = 0.0f;
    int count = 0;
    for (int oy=-1; oy<=1; ++oy) {
        int yy = y + oy;
        if (yy < 0 || yy >= h) continue;
        for (int ox=-1; ox<=1; ++ox) {
            int xx = x + ox;
            if (xx < 0 || xx >= w) continue;
            int i2 = (yy * w + xx) * 4;
            br += in[i2 + 0];
            bg += in[i2 + 1];
            bb += in[i2 + 2];
            count++;
        }
    }
    br /= count; bg /= count; bb /= count;

    // high-frequency component
    float hr = cr - br;
    float hg = cg - bg;
    float hb = cb - bb;

    // sharpened color: original + amount * highfreq
    float sr = cr + sharpen_amt * hr;
    float sg = cg + sharpen_amt * hg;
    float sb = cb + sharpen_amt * hb;

    // convert to luminance-like and boost saturation:
    // simple per-pixel "increase-chroma" via: lum + (color - lum)*sat_amt
    float lum = 0.2989f * sr + 0.5870f * sg + 0.1141f * sb;
    float rr = lum + (sr - lum) * sat_amt;
    float gg = lum + (sg - lum) * sat_amt;
    float bb2 = lum + (sb - lum) * sat_amt;

    // add tiny dithering/jitter to reduce blockiness and make compression less uniform
    // generate fast per-pixel pseudo-random using x,y,frame_seed
    uint32_t seed = (x * 73856093u) ^ (y * 19349663u) ^ (frame_seed + 0x9e3779b9u);
    seed = (seed ^ (seed << 13));
    seed = (seed ^ (seed >> 17));
    seed = (seed ^ (seed << 5));
    float rnd = ((seed & 0xFFFF) / 65535.0f) - 0.5f; // [-0.5,0.5)
    float jitter = rnd * dither_amp; // scale

    rr += jitter;
    gg += jitter * 0.8f;
    bb2 += jitter * 0.6f;

    // contrast boosting (gentle): scale away from 128
    float contrast = 1.06f; // small; already modified by sharpening
    rr = (rr - 128.0f) * contrast + 128.0f;
    gg = (gg - 128.0f) * contrast + 128.0f;
    bb2 = (bb2 - 128.0f) * contrast + 128.0f;

    // clamp to 0..255
    rr = clampf(rr, 0.0f, 255.0f);
    gg = clampf(gg, 0.0f, 255.0f);
    bb2 = clampf(bb2, 0.0f, 255.0f);

    // Expand to 16-bit: map 0..255 -> 0..65535 by multiply 257 (0->0, 255->65535)
    uint16_t outr = (uint16_t) (rr * 257.0f + 0.5f);
    uint16_t outg = (uint16_t) (gg * 257.0f + 0.5f);
    uint16_t outb = (uint16_t) (bb2 * 257.0f + 0.5f);
    uint16_t outa = (uint16_t) (ca * 257.0f + 0.5f);

    // write out in RGBA 16-bit little-endian layout
    int oidx = (y * w + x) * 4;
    out[oidx + 0] = outr;
    out[oidx + 1] = outg;
    out[oidx + 2] = outb;
    out[oidx + 3] = outa;
}

int main(int argc, char** argv) {
    if (argc < 3) {
        fprintf(stderr, "Usage: %s <width> <height> [sharpen=1.0] [saturation=1.25] [dither=0.8] [frame_seed]\n", argv[0]);
        return 1;
    }
    int w = atoi(argv[1]);
    int h = atoi(argv[2]);
    float sharpen = 1.0f;
    float sat = 1.25f;
    float dither = 0.6f;
    uint32_t frame_seed = 12345u;
    if (argc >= 4) sharpen = atof(argv[3]);
    if (argc >= 5) sat = atof(argv[4]);
    if (argc >= 6) dither = atof(argv[5]);
    if (argc >= 7) frame_seed = (uint32_t)atoi(argv[6]);

    size_t in_frame_bytes = (size_t)w * h * 4;           // RGBA 8-bit input
    size_t out_frame_pixels = (size_t)w * h * 4;         // RGBA 16-bit output (uint16_t per component)
    size_t out_frame_bytes = out_frame_pixels * sizeof(uint16_t);

    // host buffers (pinned for speed)
    uint8_t* h_in = nullptr;
    uint16_t* h_out = nullptr;
    CHECK_CUDA(cudaMallocHost(&h_in, in_frame_bytes));   // pinned
    CHECK_CUDA(cudaMallocHost(&h_out, out_frame_bytes)); // pinned

    uint8_t* d_in = nullptr;
    uint16_t* d_out = nullptr;
    CHECK_CUDA(cudaMalloc(&d_in, in_frame_bytes));
    CHECK_CUDA(cudaMalloc(&d_out, out_frame_bytes));

    // set up kernel launch
    dim3 threads(16, 16);
    dim3 blocks((w + threads.x - 1) / threads.x, (h + threads.y - 1) / threads.y);

    // We'll read frames from stdin in a loop
    while (true) {
        size_t read = fread(h_in, 1, in_frame_bytes, stdin);
        if (read != in_frame_bytes) {
            if (feof(stdin)) break;
            fprintf(stderr, "Short read from stdin: expected %zu got %zu\n", in_frame_bytes, read);
            break;
        }

        // copy to device
        CHECK_CUDA(cudaMemcpy(d_in, h_in, in_frame_bytes, cudaMemcpyHostToDevice));

        // run kernel
        detail_boost_kernel<<<blocks, threads>>>(d_in, d_out, w, h, sharpen, sat, dither, frame_seed);
        cudaError_t kerr = cudaGetLastError();
        if (kerr != cudaSuccess) {
            fprintf(stderr, "Kernel launch failed: %s\n", cudaGetErrorString(kerr));
            break;
        }

        // copy back
        CHECK_CUDA(cudaMemcpy(h_out, d_out, out_frame_bytes, cudaMemcpyDeviceToHost));

        // write to stdout (raw RGBA64LE)
        size_t written = fwrite(h_out, 1, out_frame_bytes, stdout);
        if (written != out_frame_bytes) {
            fprintf(stderr, "Short write to stdout: expected %zu wrote %zu\n", out_frame_bytes, written);
            break;
        }

        // optional: update seed slightly per-frame to get frame-varying dithers (if piping many frames)
        frame_seed = frame_seed + 1u;
    }

    fflush(stdout);
    // cleanup
    if (d_in) cudaFree(d_in);
    if (d_out) cudaFree(d_out);
    if (h_in) cudaFreeHost(h_in);
    if (h_out) cudaFreeHost(h_out);

    return 0;
}
