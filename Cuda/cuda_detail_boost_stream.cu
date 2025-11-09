// cuda_detail_boost_stream.cu
// Compile: nvcc -O3 -arch=sm_75 -o cuda_detail_boost_stream.exe cuda_detail_boost_stream.cu
// Usage: cuda_detail_boost_stream.exe <width> <height> [sharpen=1.1] [saturation=1.35] [dither=80] [start_seed=12345]
// Reads RGBA64LE (uint16_t per channel) frames from stdin, writes RGBA64LE to stdout.

#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cuda_runtime.h>
#include <cmath>

#define CHECK_CUDA(call) do { cudaError_t err = (call); if (err != cudaSuccess) { \
    fprintf(stderr, "CUDA error %s:%d '%s'\n", __FILE__, __LINE__, cudaGetErrorString(err)); exit(1);} } while(0)

__device__ inline float clampf(float v, float a, float b) {
    return v < a ? a : (v > b ? b : v);
}

// Kernel: input & output each pixel RGBA as uint16_t (0..65535)
__global__ void enhance_kernel16(const uint16_t* in, uint16_t* out, int w, int h,
                                 float sharpen_amt, float sat_amt, float dither_amp, uint32_t seed_base)
{
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x >= w || y >= h) return;

    int p = (y * w + x) * 4;
    // read 16-bit values
    float cr = (float)in[p + 0];
    float cg = (float)in[p + 1];
    float cb = (float)in[p + 2];
    float ca = (float)in[p + 3];

    // 3x3 average blur
    float br=0.0f, bg=0.0f, bb=0.0f;
    int count=0;
    for (int oy=-1; oy<=1; ++oy) {
        int yy = y + oy;
        if (yy < 0 || yy >= h) continue;
        for (int ox=-1; ox<=1; ++ox) {
            int xx = x + ox;
            if (xx < 0 || xx >= w) continue;
            int q = (yy * w + xx) * 4;
            br += (float)in[q + 0];
            bg += (float)in[q + 1];
            bb += (float)in[q + 2];
            count++;
        }
    }
    br /= max(count,1); bg /= max(count,1); bb /= max(count,1);

    // high-frequency
    float hr = cr - br;
    float hg = cg - bg;
    float hb = cb - bb;

    // sharpen
    float sr = cr + sharpen_amt * hr;
    float sg = cg + sharpen_amt * hg;
    float sb = cb + sharpen_amt * hb;

    // luma (works in same unit)
    float lum = 0.2989f * sr + 0.5870f * sg + 0.1141f * sb;
    float rr = lum + (sr - lum) * sat_amt;
    float gg = lum + (sg - lum) * sat_amt;
    float bb2 = lum + (sb - lum) * sat_amt;

    // per-pixel pseudo-random jitter to reduce compressibility
    uint32_t seed = (uint32_t)(x*73856093u ^ y*19349663u ^ seed_base);
    seed ^= (seed << 13); seed ^= (seed >> 17); seed ^= (seed << 5);
    float rnd = ((seed & 0xFFFF) / 65535.0f) - 0.5f;  // [-0.5,0.5)
    float jitter = rnd * dither_amp;
    rr += jitter;
    gg += jitter * 0.85f;
    bb2 += jitter * 0.7f;

    // small contrast around midpoint (32768)
    float contrast = 1.02f;
    rr = (rr - 32768.0f) * contrast + 32768.0f;
    gg = (gg - 32768.0f) * contrast + 32768.0f;
    bb2 = (bb2 - 32768.0f) * contrast + 32768.0f;

    // clamp
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
        fprintf(stderr, "Usage: %s <width> <height> [sharpen=1.1] [saturation=1.35] [dither=80] [seed=12345]\n", argv[0]);
        return 1;
    }

    int w = atoi(argv[1]);
    int h = atoi(argv[2]);
    float sharpen = (argc > 3) ? atof(argv[3]) : 1.1f;
    float sat = (argc > 4) ? atof(argv[4]) : 1.35f;
    float dither = (argc > 5) ? atof(argv[5]) : 80.0f; // in 16-bit units
    uint32_t seed = (argc > 6) ? (uint32_t)atoi(argv[6]) : 12345u;

    size_t frame_pixels = (size_t)w * h;
    size_t frame_bytes = frame_pixels * 4 * sizeof(uint16_t); // RGBA64LE

    // allocate pinned host buffers
    uint16_t* h_in = nullptr;
    uint16_t* h_out = nullptr;
    CHECK_CUDA(cudaMallocHost((void**)&h_in, frame_bytes));
    CHECK_CUDA(cudaMallocHost((void**)&h_out, frame_bytes));

    // device buffers
    uint16_t* d_in = nullptr;
    uint16_t* d_out = nullptr;
    CHECK_CUDA(cudaMalloc((void**)&d_in, frame_bytes));
    CHECK_CUDA(cudaMalloc((void**)&d_out, frame_bytes));

    dim3 threads(16,16);
    dim3 blocks((w + threads.x - 1)/threads.x, (h + threads.y - 1)/threads.y);

    // stdin/stdout must be in binary mode on Windows; setvbuf can help but C stdio already binary in most envs.
    // Loop: read frames from stdin, process, write to stdout
    while (true) {
        size_t read = fread(h_in, 1, frame_bytes, stdin);
        if (read == 0) {
            // EOF
            break;
        }
        if (read != frame_bytes) {
            fprintf(stderr, "Short read: expected %zu got %zu\n", frame_bytes, read);
            break;
        }

        // copy to device
        CHECK_CUDA(cudaMemcpy(d_in, h_in, frame_bytes, cudaMemcpyHostToDevice));

        // launch kernel
        enhance_kernel16<<<blocks, threads>>>(d_in, d_out, w, h, sharpen, sat, dither, seed);
        cudaError_t kerr = cudaGetLastError();
        if (kerr != cudaSuccess) {
            fprintf(stderr, "Kernel launch failed: %s\n", cudaGetErrorString(kerr));
            break;
        }

        // copy back
        CHECK_CUDA(cudaMemcpy(h_out, d_out, frame_bytes, cudaMemcpyDeviceToHost));

        // write out
        size_t written = fwrite(h_out, 1, frame_bytes, stdout);
        if (written != frame_bytes) {
            fprintf(stderr, "Short write: expected %zu wrote %zu\n", frame_bytes, written);
            break;
        }

        // increment seed each frame so jitter varies per-frame
        seed += 1u;
    }

    fflush(stdout);
    // cleanup
    cudaFree(d_in); cudaFree(d_out);
    cudaFreeHost(h_in); cudaFreeHost(h_out);
    return 0;
}
