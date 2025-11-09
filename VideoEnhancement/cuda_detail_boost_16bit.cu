// cuda_detail_boost_16bit.cu
// Compile: nvcc -O3 -arch=sm_75 -o cuda_detail_boost_16bit.exe cuda_detail_boost_16bit.cu
// Usage: cuda_detail_boost_16bit.exe <width> <height> [sharpen=1.1] [saturation=1.3] [dither=64]
// Reads RGBA64LE (uint16_t R,G,B,A) frames from stdin, processes, writes RGBA64LE to stdout.

#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cuda_runtime.h>
#include <cmath>

#define CHECK_CUDA(call) do { cudaError_t err = (call); if (err != cudaSuccess) { \
    fprintf(stderr,"CUDA error %s:%d '%s'\n", __FILE__, __LINE__, cudaGetErrorString(err)); exit(1);} } while(0)

__device__ inline float clampf(float v, float a, float b) {
    return v < a ? a : (v > b ? b : v);
}

// Input: uint16_t per channel RGBA (range 0..65535).
// Do processing in float, but stay in 0..65535 range.
// sharpen_amt: multiplies high-frequency (same scale as 16-bit values).
// sat_amt: saturation multiplier (1.0 = no change).
// dither_amp: amplitude of random jitter in 16-bit units (e.g. 32..256).
__global__ void detail_boost_kernel16(const uint16_t* in, uint16_t* out, int w, int h,
                                      float sharpen_amt, float sat_amt, float dither_amp, uint32_t frame_seed)
{
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x >= w || y >= h) return;

    int p = (y * w + x) * 4;
    float cr = in[p + 0];
    float cg = in[p + 1];
    float cb = in[p + 2];
    float ca = in[p + 3];

    // 3x3 average blur (16-bit domain)
    float br = 0.0f, bg = 0.0f, bb = 0.0f;
    int count = 0;
    for (int oy=-1; oy<=1; ++oy) {
        int yy = y + oy;
        if (yy < 0 || yy >= h) continue;
        for (int ox=-1; ox<=1; ++ox) {
            int xx = x + ox;
            if (xx < 0 || xx >= w) continue;
            int q = (yy * w + xx) * 4;
            br += in[q + 0];
            bg += in[q + 1];
            bb += in[q + 2];
            count++;
        }
    }
    br /= count; bg /= count; bb /= count;

    // high freq
    float hr = cr - br;
    float hg = cg - bg;
    float hb = cb - bb;

    // sharpen
    float sr = cr + sharpen_amt * hr;
    float sg = cg + sharpen_amt * hg;
    float sb = cb + sharpen_amt * hb;

    // convert to "luma" (using 8-bit-ish coefficients but in 16-bit range)
    // coefficients are independent of bit depth; result range equals input range.
    float lum = 0.2989f * sr + 0.5870f * sg + 0.1141f * sb;

    // saturation boost in linear/light-approx domain: lum + (color - lum)*sat
    float rr = lum + (sr - lum) * sat_amt;
    float gg = lum + (sg - lum) * sat_amt;
    float bb2 = lum + (sb - lum) * sat_amt;

    // per-pixel pseudo-random jitter (in 16-bit units)
    uint32_t seed = (x * 73856093u) ^ (y * 19349663u) ^ (frame_seed + 0x9e3779b9u);
    seed ^= (seed << 13); seed ^= (seed >> 17); seed ^= (seed << 5);
    float rnd = ((seed & 0xFFFF) / 65535.0f) - 0.5f; // [-0.5,0.5)
    float jitter = rnd * dither_amp;
    rr += jitter;
    gg += jitter * 0.8f;
    bb2 += jitter * 0.6f;

    // small contrast boost around midpoint (midpoint approx 32768)
    float contrast = 1.02f;
    rr = (rr - 32768.0f) * contrast + 32768.0f;
    gg = (gg - 32768.0f) * contrast + 32768.0f;
    bb2 = (bb2 - 32768.0f) * contrast + 32768.0f;

    // clamp to 0..65535
    rr = clampf(rr, 0.0f, 65535.0f);
    gg = clampf(gg, 0.0f, 65535.0f);
    bb2 = clampf(bb2, 0.0f, 65535.0f);
    float aa = clampf(ca, 0.0f, 65535.0f);

    out[p + 0] = (uint16_t)(rr + 0.5f);
    out[p + 1] = (uint16_t)(gg + 0.5f);
    out[p + 2] = (uint16_t)(bb2 + 0.5f);
    out[p + 3] = (uint16_t)(aa + 0.5f);
}

int main(int argc, char** argv) {
    if (argc < 3) {
        fprintf(stderr, "Usage: %s <width> <height> [sharpen=1.1] [saturation=1.3] [dither=64]\n", argv[0]);
        return 1;
    }
    int w = atoi(argv[1]);
    int h = atoi(argv[2]);
    float sharpen = (argc > 3) ? atof(argv[3]) : 1.1f;
    float sat     = (argc > 4) ? atof(argv[4]) : 1.3f;
    float dither  = (argc > 5) ? atof(argv[5]) : 64.0f; // in 16-bit units (~0.001 of range per unit)

    size_t frame_pixels = (size_t)w * h;
    size_t in_bytes = frame_pixels * 4 * sizeof(uint16_t);   // RGBA64LE
    size_t out_bytes = in_bytes;

    uint16_t* h_in = nullptr;
    uint16_t* h_out = nullptr;
    uint16_t* d_in = nullptr;
    uint16_t* d_out = nullptr;

    CHECK_CUDA(cudaMallocHost((void**)&h_in, in_bytes));
    CHECK_CUDA(cudaMallocHost((void**)&h_out, out_bytes));
    CHECK_CUDA(cudaMalloc((void**)&d_in, in_bytes));
    CHECK_CUDA(cudaMalloc((void**)&d_out, out_bytes));

    dim3 threads(16,16);
    dim3 blocks((w + threads.x - 1) / threads.x, (h + threads.y - 1) / threads.y);

    uint32_t frame_seed = 123456u;
    while (true) {
        // read from stdin raw bytes (RGBA64LE)
        size_t read = fread(h_in, 1, in_bytes, stdin);
        if (read != in_bytes) {
            if (feof(stdin)) break;
            fprintf(stderr,"Short read: expected %zu got %zu\n", in_bytes, read);
            break;
        }

        CHECK_CUDA(cudaMemcpy(d_in, h_in, in_bytes, cudaMemcpyHostToDevice));

        detail_boost_kernel16<<<blocks, threads>>>(d_in, d_out, w, h, sharpen, sat, dither, frame_seed);
        cudaError_t kerr = cudaGetLastError();
        if (kerr != cudaSuccess) {
            fprintf(stderr,"Kernel launch failed: %s\n", cudaGetErrorString(kerr));
            break;
        }

        CHECK_CUDA(cudaMemcpy(h_out, d_out, out_bytes, cudaMemcpyDeviceToHost));

        size_t written = fwrite(h_out, 1, out_bytes, stdout);
        if (written != out_bytes) {
            fprintf(stderr,"Short write: expected %zu wrote %zu\n", out_bytes, written);
            break;
        }

        frame_seed += 1u;
    }

    cudaFree(d_in); cudaFree(d_out);
    cudaFreeHost(h_in); cudaFreeHost(h_out);
    return 0;
}
