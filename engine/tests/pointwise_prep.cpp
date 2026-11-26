// Exercise the same C ABI that bakes the camera preview's colour table.
// Run from the repository root: engine/build/pointwise_prep [engine/resources]
#include <algorithm>
#include <cstdio>
#include <memory>
#include <string>
#include <vector>

#include "spektrafilm/spk_engine.h"

namespace {

std::vector<uint16_t> render(spk_engine* engine, const spk_image& source,
                             const char* prep, bool samples = true) {
    const std::string recipe = std::string(R"({"auto_exposure":false,
        "input_color_space":"ProPhoto RGB","input_cctf_decoding":false,
        "halation_active":false,"grain_active":false,"glare_active":false,
        "dir_couplers_active":false,"scanner_lens_blur":0,
        "scanner_sharpening_amount":0,"camera_diffusion_active":false)") + prep + '}';
    const std::unique_ptr<spk_session, decltype(&spk_session_release)> session(
        spk_open(engine, &source, recipe.c_str(), nullptr), spk_session_release);
    if (!session) {
        std::fprintf(stderr, "Open failed: %s\n", spk_last_error(engine));
        return {};
    }
    spk_result result{};
    const spk_status status = samples ? spk_render_color_samples(session.get(), &result)
                                      : spk_render(session.get(), "full", &result);
    std::vector<uint16_t> pixels;
    if (status == SPK_OK && result.rgba16 && result.width == source.width &&
        result.height == source.height) {
        for (uint32_t y = 0; y < result.height; ++y) {
            const uint16_t* row = result.rgba16 + size_t(y) * result.row_stride_px * 4;
            pixels.insert(pixels.end(), row, row + size_t(result.width) * 4);
        }
    } else {
        std::fprintf(stderr, "Render failed or dimensions changed: %s\n", spk_last_error(engine));
    }
    spk_result_free(&result);
    return pixels;
}

}  // namespace

int main(int argc, char** argv) {
    const std::unique_ptr<spk_engine, decltype(&spk_engine_destroy)> engine(
        spk_engine_create(argc > 1 ? argv[1] : "engine/resources", nullptr), spk_engine_destroy);
    if (!engine) {
        std::fprintf(stderr, "Could not create engine: %s\n", spk_last_error(nullptr));
        return 1;
    }

    // One chart contains dark and bright neutral samples and lower-saturation
    // colours so each pointwise adjustment can produce a measurable difference.
    constexpr uint32_t width = 9, height = 7;
    std::vector<float> pixels;
    for (uint32_t p = 0; p < width * height; ++p) {
        const float level = 0.033f + float(p % 9) * 0.075f;
        pixels.push_back(level);
        pixels.push_back(level * (0.76f + 0.055f * float(p / width)));
        pixels.push_back(level * (1.18f - 0.039f * float(p / width)));
    }
    const spk_image chart{pixels.data(), width, height, 3};
    const auto baseline = render(engine.get(), chart, "");
    if (baseline.empty()) return 1;

    const char* controls[] = {
        R"(,"camera_prep_exposure_ev":0.8)",
        R"(,"camera_prep_contrast":70)",
        R"(,"camera_prep_lift":70)",
        R"(,"camera_prep_gain":70)",
        R"(,"camera_prep_vibrance":70)",
        R"(,"camera_prep_saturation":-70)"
    };
    for (const char* control : controls) {
        const auto actual = render(engine.get(), chart, control);
        const auto ordinary = render(engine.get(), chart, control, false);
        if (actual.empty() || actual == baseline || actual != ordinary) {
            std::fprintf(stderr, "Pointwise adjustment dropped or differs from ordinary render: %s\n", control);
            return 1;
        }
    }

    const char* spatial = R"(,"camera_local_tone_brights":80,"camera_local_tone_darks":40,"camera_prep_detail":65)";
    const std::string mixed = std::string(controls[0]) + spatial;
    const auto expected = render(engine.get(), chart, controls[0]);
    if (render(engine.get(), chart, spatial) != baseline ||
        render(engine.get(), chart, mixed.c_str()) != expected) {
        std::fprintf(stderr, "Spatial prep affected independent colour samples\n");
        return 1;
    }
    const auto ordinary_mixed = render(engine.get(), chart, mixed.c_str(), false);
    if (ordinary_mixed.empty() || ordinary_mixed == expected) {
        std::fprintf(stderr, "Spatial prep did not affect the ordinary render\n");
        return 1;
    }

    std::vector<float> reversed(pixels.size());
    for (uint32_t p = 0; p < width * height; ++p)
        std::copy_n(pixels.data() + (width * height - 1 - p) * 3, 3, reversed.data() + p * 3);
    const spk_image permuted{reversed.data(), height, width, 3};
    const auto reordered = render(engine.get(), permuted, mixed.c_str());
    if (reordered.size() != expected.size()) return 1;
    for (uint32_t p = 0; p < width * height; ++p) {
        if (!std::equal(reordered.data() + p * 4, reordered.data() + p * 4 + 4,
                        expected.data() + (width * height - 1 - p) * 4)) {
            std::fprintf(stderr, "Colour samples depend on chart order or dimensions\n");
            return 1;
        }
    }
    std::puts("Pointwise Camera Prep survives colour sampling; spatial prep is isolated.");
    return 0;
}
