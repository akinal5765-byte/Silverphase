// Development calibration using the shipping Metal film and print stages.
// Mid-grey filter calibration follows the approach in Spektrafilm experimental
// (28bf883) and Negs (97d63aa, crates/spektrafilm-core/src/print_balance.rs).
// Run: engine/build/print_balance [--holdout] <resources> <film> <paper> [<film> <paper> ...]
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <fstream>
#include <memory>
#include <sstream>
#include <string>

#include "pipeline/pipeline.hpp"

namespace {
using namespace spk;
using Pair = std::array<double, 2>;
constexpr std::array<float, 7> kRamp = {
    0.184f / 8, 0.184f / 4, 0.184f / 2, 0.184f, 0.184f * 2, 0.184f * 4, 0.184f * 8,
};
// Half-stop samples omitted from the calibration screen. Midgrey is still
// measured separately and excluded from the holdout ramp score.
constexpr std::array<float, kRamp.size()> kHoldoutRamp = {
    0.032526912f, 0.065053824f, 0.130107648f, 0.184f, 0.260215295f, 0.520430591f, 1.040861182f,
};
constexpr size_t kMid = kRamp.size() / 2;
using Ramp = std::array<Pair, kRamp.size()>;

double length(const Pair& r) { return std::hypot(r[0], r[1]); }

double ramp_error(const Ramp& ramp, bool holdout) {
    double error = 0;
    for (size_t i = 0; i < ramp.size(); ++i)
        if (!holdout || i != kMid) error += length(ramp[i]);
    return error / (ramp.size() - (holdout ? 1 : 0));
}

struct SolveResult {
    Pair shifts{};
    Ramp before{}, after{};
};

template <typename Measure>
bool solve(Measure measure, Pair low, Pair high, SolveResult& result) {
    if (!measure(result.shifts, result.before)) return false;
    result.after = result.before;
    for (int iteration = 0; iteration < 20 && length(result.after[kMid]) > 1e-5; ++iteration) {
        Pair derivative[2];
        for (size_t c = 0; c < 2; ++c) {
            Pair left = result.shifts, right = result.shifts;
            left[c] = std::max(low[c], left[c] - 0.1);
            right[c] = std::min(high[c], right[c] + 0.1);
            Ramp l, r;
            if (!measure(left, l) || !measure(right, r)) return false;
            for (size_t i = 0; i < 2; ++i)
                derivative[c][i] = (r[kMid][i] - l[kMid][i]) / (right[c] - left[c]);
        }
        const auto& [m_r, m_b] = derivative[0];
        const auto& [y_r, y_b] = derivative[1];
        const auto& [r, b] = result.after[kMid];
        const double det = m_r * y_b - m_b * y_r;
        if (!std::isfinite(det) || std::abs(det) < 1e-12) break;
        const Pair step = {(y_r * b - y_b * r) / det, (m_b * r - m_r * b) / det};

        bool improved = false;
        for (double scale = 1; scale >= 1.0 / 128; scale *= 0.5) {
            const Pair trial = {
                std::clamp(result.shifts[0] + scale * step[0], low[0], high[0]),
                std::clamp(result.shifts[1] + scale * step[1], low[1], high[1]),
            };
            Ramp measured;
            if (!measure(trial, measured)) return false;
            if (length(measured[kMid]) < length(result.after[kMid])) {
                result.shifts = trial;
                result.after = measured;
                improved = true;
                break;
            }
        }
        if (!improved) break;
    }
    return true;
}

bool calibrate(gpu::Gpu& gpu, Colour& colour, Blob& blob, SetupCache& cache,
               const std::string& resources, const Json& filters, const std::string& film,
               const std::string& paper, bool holdout, std::string& error) {
    Params p;
    if (!init_params(resources, film, paper, filters, p, error)) return false;
    if (p.film.info.is_positive() || p.film.info.is_monochrome() || p.print.info.is_monochrome() ||
        p.film.info.stage != "filming" || p.print.info.stage != "printing") {
        error = "calibration requires a colour negative and a colour print material";
        return false;
    }
    p.io.input_color_space = p.io.output_color_space = "sRGB";
    p.io.output_cctf_encoding = false;
    p.io.output_gamut_compress.algorithm = "off";
    p.camera.auto_exposure = false;
    p.enlarger.print_exposure_compensation = false;
    p.debug.deactivate_spatial_effects = p.debug.deactivate_stochastic_effects = true;
    if (!digest(p, filters, error)) return false;

    Pipeline pipeline(&gpu, &colour, &blob, &cache);
    if (!pipeline.build(p, error)) return false;
    pipeline.set_source_long_edge(kRamp.size(), kRamp.size());
    const auto& exposure_ramp = holdout ? kHoldoutRamp : kRamp;
    std::array<float, kRamp.size() * 3> pixels{};
    for (size_t i = 0; i < kRamp.size(); ++i)
        std::fill_n(pixels.begin() + 3 * i, 3, exposure_ramp[i]);

    const auto evaluate = [&]() {
        const Image input{gpu.upload(pixels.data(), sizeof(pixels), error), 1, uint32_t(kRamp.size())};
        Image negative;
        if (!input.valid() || !pipeline.run_film(input, negative, nullptr, error)) return false;
        auto measure = [&](const Pair& shift, Ramp& ramp) {
            Json delta = Json::object();
            delta.set("m_filter_shift", Json(shift[0]));
            delta.set("y_filter_shift", Json(shift[1]));
            pipeline.apply_live_delta(delta);
            Image image;
            if (!pipeline.run_print(negative, image, nullptr, error) || !gpu.flush(error)) return false;
            const auto* rgb = static_cast<const float*>(gpu.contents(image.buf.get()));
            for (size_t i = 0; i < kRamp.size(); ++i) {
                const double green = rgb[3 * i + 1];
                if (!(green > 1e-8) || !std::isfinite(green)) {
                    error = "grey ramp has zero or invalid green response";
                    return false;
                }
                ramp[i] = {(rgb[3 * i] - green) / green, (rgb[3 * i + 2] - green) / green};
                if (!std::isfinite(length(ramp[i]))) { error = "invalid grey ramp"; return false; }
            }
            return true;
        };
        const auto& e = p.enlarger;
        const Pair low = {std::max(-50.0, -e.m_filter_neutral), std::max(-50.0, -e.y_filter_neutral)};
        const Pair high = {std::min(50.0, 200.0 - e.m_filter_neutral), std::min(50.0, 200.0 - e.y_filter_neutral)};
        SolveResult solved;
        if (!solve(measure, low, high, solved)) return false;
        const double mid = length(solved.after[kMid]);
        std::printf("%s\t%s\t%s\t%.5f\t%.5f\t%.5f\t%.6f\t%.6f\t%.6f\t%.6f\t%s\n",
                    film.c_str(), paper.c_str(), e.illuminant.c_str(), e.c_filter_neutral,
                    e.m_filter_neutral + solved.shifts[0], e.y_filter_neutral + solved.shifts[1],
                    length(solved.before[kMid]), mid, ramp_error(solved.before, holdout),
                    ramp_error(solved.after, holdout), mid <= 1e-5 ? "converged" : "limited");
        return true;
    };
    gpu.begin_frame();
    const bool ok = evaluate();
    gpu.end_frame();
    return ok;
}
}  // namespace

int main(int argc, char** argv) {
    const bool holdout = argc > 1 && std::string(argv[1]) == "--holdout";
    const int resources_index = holdout ? 2 : 1;
    const int pairs_index = resources_index + 1;
    if (argc < pairs_index + 2 || (argc - pairs_index) % 2 != 0) {
        std::fprintf(stderr, "Usage: %s [--holdout] <resources> <film> <paper> [<film> <paper> ...]\n", argv[0]);
        return 2;
    }
    const std::string resources = argv[resources_index];
    std::string error;
    Blob blob;
    Colour colour;
    std::ifstream filter_file(resources + "/neutral_print_filters.json");
    std::ostringstream filter_text;
    filter_text << filter_file.rdbuf();
    Json filters;
    if (!Json::parse(filter_text.str(), filters, error) ||
        !blob.open(resources + "/spektrafilm_constants.bin", error) || !colour.init(blob, error)) {
        std::fprintf(stderr, "%s\n", error.c_str());
        return 1;
    }
    std::unique_ptr<gpu::Gpu> device(gpu::Gpu::create_metal(nullptr, resources + "/spektrafilm.metallib", error));
    if (!device || !device->check_math_mode(error)) {
        std::fprintf(stderr, "%s\n", error.c_str());
        return 1;
    }
    SetupCache cache;
    bool success = true;
    std::puts("film\tpaper\tilluminant\tc\tm\ty\tmid_before\tmid_after\tramp_before\tramp_after\tstatus");
    for (int i = pairs_index; i < argc; i += 2) {
        if (!calibrate(*device, colour, blob, cache, resources, filters, argv[i], argv[i + 1], holdout, error)) {
            std::fprintf(stderr, "%s / %s: %s\n", argv[i], argv[i + 1], error.c_str());
            success = false;
        }
    }
    return success ? 0 : 1;
}
