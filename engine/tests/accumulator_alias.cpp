// Opt-in grain accumulator reuse must preserve each float, not just an image's look.
#include "pipeline/blur.hpp"
#include <cstdio>
#include <cstring>
#include <memory>
#include <vector>

int main(int argc, char** argv) {
    std::string error;
    std::unique_ptr<spk::gpu::Gpu> gpu(spk::gpu::Gpu::create_metal(nullptr,
        argc > 1 ? argv[1] : "engine/resources/spektrafilm.metallib", error));
    if (!gpu) { std::fprintf(stderr, "%s\n", error.c_str()); return 1; }
    spk::Blur blur(gpu.get());
    for (double sigma : {0.0, 0.45, 0.65, 1.8, 3.5}) {
        spk::Image image; image.h = 137; image.w = 193; image.c = 3;
        std::vector<float> source(image.elements()), initial(image.elements());
        for (size_t i = 0; i < source.size(); ++i) {
            source[i] = float((i * 37) % 1009) / 83.0f;
            initial[i] = float((i * 17) % 257) / 99.0f;
        }
        image.buf = gpu->upload(source.data(), image.bytes(), error);
        spk::Image oldAcc = image, reuseAcc = image;
        oldAcc.buf = gpu->upload(initial.data(), image.bytes(), error);
        reuseAcc.buf = gpu->upload(initial.data(), image.bytes(), error);
        double sigmas[3] = {sigma, sigma * 0.8, 0}, weight[3] = {1, 0.7, 0.3};
        spk::Image reference, reused;
        if (!blur.gaussian(image, sigmas, reference, error, 3, &oldAcc, weight) ||
            !blur.gaussian(image, sigmas, reused, error, 3, &reuseAcc, weight, true) || !gpu->flush(error)) {
            std::fprintf(stderr, "%s\n", error.c_str()); return 1;
        }
        if (std::memcmp(gpu->contents(reference.buf.get()), gpu->contents(reused.buf.get()), image.bytes()) != 0) {
            std::fprintf(stderr, "Accumulator changed at sigma %g\n", sigma); return 1;
        }
        const auto audit = gpu->pool_stats().audit;
        if (audit.over_releases || audit.live_underflows) return 1;
    }
    std::puts("FIR, inactive channels, mixed FIR/IIR and IIR accumulator reuse are bit-identical");
}
