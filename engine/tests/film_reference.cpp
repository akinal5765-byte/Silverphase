#include "core/spectral.hpp"
#include "pipeline/pipeline.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <exception>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <memory>
#include <sstream>
#include <stdexcept>

namespace spk {

struct FilmReferenceProbe {
    // Read the production kernels at their boundaries without changing the render path.
    static bool paper_density(Pipeline& pipe, const Image& negative, Image& paper, std::string& error) {
        Pipeline::Chain exposed, diffused;
        return pipe.print_prefix(error)
            && pipe.print_expose({negative, {}}, exposed, error)
            && pipe.print_diffusion(exposed, diffused, error)
            && pipe.node_print_curves(diffused.cur, paper, error);
    }
};

} // namespace spk

namespace {

using namespace spk;
using Triple = std::array<double, 3>;
using Spectrum = std::array<double, kNumWavelengths>;

// Traced from Kodak H-1-5219t (2015), p. 4, ECN-2 sensitometric curves.
constexpr std::array<std::array<double, 4>, 14> kKodak{{
    {-6.9304, .1969, .5908, .8506}, {-5.9053, .2221, .6243, .8673},
    {-4.9248, .2807, .6830, .9260}, {-3.8997, .3645, .7793, 1.0140},
    {-2.9192, .4902, .9260, 1.1648}, {-1.8942, .6327, 1.0978, 1.3408},
    {-.9136, .7709, 1.2654, 1.5000}, {.0669, .9092, 1.4288, 1.6550},
    {1.0919, 1.0601, 1.6006, 1.8184}, {2.0724, 1.1983, 1.7640, 1.9777},
    {3.0975, 1.3450, 1.9358, 2.1494}, {4.0780, 1.4832, 2.0950, 2.3045},
    {5.1031, 1.6131, 2.2458, 2.4553}, {6.0836, 1.7221, 2.3841, 2.5852}
}};

struct LogResponse {
    int first_nm;
    Vec values;
};

// ISO 5/3:1984 Table 4 visual-instrument channel weights. Outside the tabulated
// response the weight is zero. Interpolate the logarithmic response on 5 nm.
const std::array<LogResponse, 3> kStatusM{{
    {620, {2.109,4.479,5,4.899,4.578,4.252,3.875,3.491,3.099,2.687,2.269,1.859,1.449,1.054,.654,.254}},
    {470, {1.152,2.207,3.156,3.804,4.272,4.626,4.872,5,4.995,4.818,4.458,3.915,3.172,2.239,1.070}},
    {410, {2.103,4.111,4.632,4.871,5,4.955,4.743,4.343,3.743,2.990,1.852}}
}};

void require(bool ok, const std::string& error) {
    if (!ok) throw std::runtime_error(error);
}

using InstrumentBands = std::vector<std::pair<size_t, double>>;

InstrumentBands instrument_bands(const Profile& film, const Vec& wavelengths, size_t channel) {
    InstrumentBands weights;
    double total = 0;
    const auto& response = kStatusM[channel];
    for (size_t i = 0; i < wavelengths.size(); ++i) {
        const double at = (wavelengths[i] - response.first_nm) / 10;
        if (at < 0 || at > response.values.size() - 1) continue;
        const double* dye = &film.data.channel_density[3 * i];
        if (!std::isfinite(film.data.base_density[i] + dye[0] + dye[1] + dye[2])) continue;
        const auto left = size_t(at);
        const auto right = std::min(left + 1, response.values.size() - 1);
        const double weight = std::pow(10, std::lerp(response.values[left], response.values[right], at - left) - 5);
        weights.emplace_back(i, weight);
        total += weight;
    }
    require(total > 0, "Missing Status M response");
    for (auto& band : weights) band.second /= total;
    return weights;
}

template<class T>
double transmission(const Profile& film, const InstrumentBands& bands, const T* cmy) {
    double transmitted = 0;
    for (const auto& [i, weight] : bands) {
        const double* dye = &film.data.channel_density[3 * i];
        const double density = film.data.base_density[i] +
            dye[0] * cmy[0] + dye[1] * cmy[1] + dye[2] * cmy[2];
        transmitted += weight * std::pow(10, -density);
    }
    return transmitted;
}

Triple status_m(const Profile& film, const Vec& wavelengths, const Triple& cmy) {
    Triple result{};
    for (size_t c = 0; c < 3; ++c) {
        const double transmitted = transmission(film, instrument_bands(film, wavelengths, c), cmy.data());
        require(transmitted > 0, "Invalid Status M transmission");
        result[c] = -std::log10(transmitted);
    }
    return result;
}

struct ChartPatch {
    std::string name;
    Spectrum reflectance;
};

std::vector<ChartPatch> load_chart(const char* path) {
    std::ifstream input(path);
    require(bool(input), "Cannot open the BabelColor CGATS fixture");
    std::string line;
    while (std::getline(input, line) && !line.starts_with("BEGIN_DATA\r") && line != "BEGIN_DATA") {}
    std::vector<ChartPatch> patches;
    while (std::getline(input, line) && !line.starts_with("END_DATA")) {
        std::istringstream row(line);
        int id;
        ChartPatch patch{};
        std::array<double, 36> measured{};
        require(bool(row >> id >> patch.name) && id == int(patches.size()) + 1, "Invalid patch index");
        for (double& value : measured) {
            require(bool(row >> value) && value >= 0 && value <= 1, "Invalid spectral reflectance");
        }
        // Data covers 380–730 nm at 10 nm. Use constant endpoint extension
        // for the remaining wavelengths instead of adding an artificial cutoff.
        for (size_t i = 0; i < kNumWavelengths; ++i) {
            const auto left = std::min(i / 2, measured.size() - 1);
            const auto right = std::min(left + 1, measured.size() - 1);
            patch.reflectance[i] = std::lerp(measured[left], measured[right], .5 * (i % 2));
        }
        patches.push_back(patch);
    }
    require(patches.size() == 24, "Expected the 24 BabelColor Avg30 reflectance spectra");
    return patches;
}

struct FrameScope {
    gpu::Gpu& gpu;
    explicit FrameScope(spk::gpu::Gpu& device) : gpu(device) { gpu.begin_frame(); }
    ~FrameScope() { gpu.end_frame(); }
};

struct Checkpoint {
    Triple exposure;
    Triple negative;
    Triple paper;
    Triple rgb;
};

Triple center(gpu::Gpu& gpu, const Image& image) {
    require(image.valid() && image.c == 3, "Missing render checkpoint");
    const auto* data = static_cast<const float*>(gpu.contents(image.buf.get()));
    require(data != nullptr, "Cannot read render checkpoint");
    const size_t i = 3 * (size_t(image.h / 2) * image.w + image.w / 2);
    Triple result{data[i], data[i + 1], data[i + 2]};
    for (double value : result) require(std::isfinite(value), "Non-finite render checkpoint");
    return result;
}

Checkpoint render(Pipeline& pipe, gpu::Gpu& gpu, const Triple& rgb, bool print, uint32_t edge = 16) {
    std::string error;
    FrameScope frame(gpu);
    std::vector<float> pixels(size_t(edge) * edge * 3);
    for (size_t i = 0; i < pixels.size(); ++i) pixels[i] = float(rgb[i % 3]);
    const Image input{gpu.upload(pixels.data(), pixels.size() * sizeof(float), error), edge, edge};
    Image negative, paper, output;
    pipe.set_source_long_edge(edge, edge);
    require(input.valid(), error);
    require(pipe.run_film(input, negative, nullptr, error), error);
    if (!print) {
        require(gpu.flush(error), error);
        return {{}, center(gpu, negative), {}, {}};
    }
    Pipeline::Chain exposed;
    require(pipe.film_scale_and_expose({input, {}}, exposed, error), error);
    require(FilmReferenceProbe::paper_density(pipe, negative, paper, error), error);
    require(pipe.run_print(negative, output, nullptr, error), error);
    require(gpu.flush(error), error);
    return {center(gpu, exposed.cur), center(gpu, negative), center(gpu, paper), center(gpu, output)};
}

void print_triple(const Triple& values) {
    for (double value : values) std::cout << '\t' << value;
}

void print_checkpoint(const std::string& name, const Triple& color_error, const Checkpoint& sample) {
    std::cout << name;
    print_triple(color_error);
    print_triple(sample.exposure);
    print_triple(sample.negative);
    print_triple(sample.paper);
    print_triple(sample.rgb);
    std::cout << '\n';
}

void check_tone(Pipeline& pipe, gpu::Gpu& gpu, const Params& p, const Vec& wavelengths) {
    constexpr double first = -9, step = .25;
    std::array<Triple, 73> ramp;
    for (size_t i = 0; i < ramp.size(); ++i) {
        const double linear = .184 * std::exp2(first + step * i);
        auto sample = render(pipe, gpu, {linear, linear, linear}, false);
        ramp[i] = status_m(p.film, wavelengths, sample.negative);
        if (i == 0) continue;
        for (size_t c = 0; c < 3; ++c)
            require(ramp[i][c] >= ramp[i - 1][c] - .001, "The neutral ramp reversed");
    }

    // One shared offset from green at 0 EV. Leave the other two curves free.
    const double green = std::lerp(kKodak[6][2], kKodak[7][2], -kKodak[6][0] / (kKodak[7][0] - kKodak[6][0]));
    const auto upper = std::find_if(ramp.begin(), ramp.end(), [&](auto sample) { return sample[1] >= green; });
    require(upper != ramp.begin() && upper != ramp.end(), "Could not align the Kodak curve");
    const auto lower = upper - 1;
    const double shift = first + step * (std::distance(ramp.begin(), lower)
        + (green - (*lower)[1]) / ((*upper)[1] - (*lower)[1]));
    std::cout << "# Kodak exposure alignment\t" << shift << " EV\n";

    Triple mae{};
    for (const auto& row : kKodak) {
        const double on_ramp = (row[0] + shift - first) / step;
        require(on_ramp >= 0 && on_ramp < ramp.size() - 1, "Alignment exceeds measured ramp");
        const size_t left = size_t(on_ramp);
        Triple model{};
        for (size_t c = 0; c < 3; ++c) {
            model[c] = std::lerp(ramp[left][c], ramp[left + 1][c], on_ramp - left);
            mae[c] += std::abs(model[c] - row[c + 1]) / kKodak.size();
        }
        std::cout << "# density\t" << row[0];
        print_triple({row[1], row[2], row[3]});
        print_triple(model);
        std::cout << '\n';
    }
    std::cout << "# Kodak R/G/B mean absolute error in D";
    print_triple(mae);
    std::cout << '\n';
    require(mae[0] < .06 && mae[1] < .04 && mae[2] < .04, "5219 sensitometry has moved outside the reference bounds");
}

void check_colors(Pipeline& pipe, gpu::Gpu& gpu, const Params& p, const Colour& colour,
                  const Blob& blob, const std::vector<ChartPatch>& patches) {
    std::string error;
    Vec illuminant, sensitivity;
    require(standard_illuminant(colour, blob, p.film.info.reference_illuminant, illuminant, error), error);
    require(film_sensitivity(colour, blob, p.film, p.camera, sensitivity, error), error);
    Mat3 rgb_to_xyz;
    require(tc_b_matrix(colour, blob, p.io.input_color_space, p.film.info.reference_illuminant, rgb_to_xyz, error), error);
    const Mat3 xyz_to_rgb = rgb_to_xyz.inverse();

    auto integrate = [&](const Spectrum& reflectance) {
        Triple xyz{}, direct{};
        for (size_t l = 0; l < reflectance.size(); ++l) {
            const double light = reflectance[l] * illuminant[l];
            for (size_t c = 0; c < 3; ++c) {
                xyz[c] += light * colour.cmfs_1931_2deg()[3 * l + c];
                direct[c] += light * sensitivity[3 * l + c];
            }
        }
        return std::pair{xyz, direct};
    };

    Spectrum perfect_diffuser;
    perfect_diffuser.fill(1);
    const auto [white, white_exposure] = integrate(perfect_diffuser);
    Triple white_rgb{};
    const Triple white_xyz{white[0] / white[1], 1, white[2] / white[1]};
    xyz_to_rgb.apply(white_xyz.data(), white_rgb.data());
    const auto white_sample = render(pipe, gpu, white_rgb, true);
    std::cout << "# chart\terror EV RGB\tfilm exposure RGB\tnegative CMY\tpaper CMY\toutput RGB\n";
    print_checkpoint("white", {}, white_sample);
    for (const auto& patch : patches) {
        auto [xyz, direct] = integrate(patch.reflectance);
        for (double& value : xyz) value /= white[1];
        Triple rgb{};
        xyz_to_rgb.apply(xyz.data(), rgb.data());
        const auto sample = render(pipe, gpu, rgb, true);
        Triple color_error{};
        for (size_t c = 0; c < 3; ++c) {
            require(sample.exposure[c] > 0 && white_sample.exposure[c] > 0 && direct[c] > 0,
                    "Non-positive exposure for chart patch " + patch.name);
            color_error[c] = std::log2((sample.exposure[c] / white_sample.exposure[c]) /
                                      (direct[c] / white_exposure[c]));
        }
        print_checkpoint(patch.name, color_error, sample);
    }
    print_checkpoint("hdr-neutral", {}, render(pipe, gpu, {4, 4, 4}, true, 512));
    print_checkpoint("hdr-saturated", {}, render(pipe, gpu, {4, .02, 1.2}, true, 512));
    print_checkpoint("near-black", {}, render(pipe, gpu, {1e-6, 2e-6, 1e-6}, true, 512));
}

void check_blue_grain(gpu::Gpu& gpu, Colour& colour, Blob& blob, SetupCache& cache, Params p) {
    // Kodak's published 48 µm aperture. Average transmission before taking
    // density, and use disjoint apertures on a flat exposed frame.
    constexpr uint32_t edge = 768;
    constexpr int radius = 6;
    constexpr std::array<std::array<double, 3>, 3> anchors{{
        {4.6173, 2.4679, 19.3915}, {5.6241, 2.5978, 16.8137}, {7.2415, 2.7570, 14.2846}
    }};
    p.film_render.grain.active = true;
    p.film_render.grain.amount = 1;
    p.film_render.grain.sublayers_active = true;
    p.settings.grain_sampler = "exact";
    p.camera.film_format_mm = .004 * edge;
    std::string error;
    Pipeline pipe(&gpu, &colour, &blob, &cache);
    require(pipe.build(p, error), error);

    // Blue Status M covers 410–510 nm. Pre-normalise the aperture weights.
    const auto bands = instrument_bands(p.film, colour.wavelengths(), 2);

    for (const auto& [ev, kodak_density, kodak_rms] : anchors) {
        FrameScope frame(gpu);
        std::vector<float> pixels(size_t(edge) * edge * 3, float(.184 * std::exp2(ev)));
        const Image input{gpu.upload(pixels.data(), pixels.size() * sizeof(float), error), edge, edge};
        Image negative;
        pipe.set_source_long_edge(edge, edge);
        require(input.valid(), error);
        require(pipe.run_film(input, negative, nullptr, error), error);
        require(gpu.flush(error), error);
        const auto* data = static_cast<const float*>(gpu.contents(negative.buf.get()));
        require(data != nullptr, "Cannot read the grain checkpoint");

        // A flat frame keeps subject texture out of the estimate. Skip the
        // frame margins so the PSF's edge extension cannot bias the sample.
        size_t count = 0;
        double mean = 0, sum_of_squares = 0;
        for (int y = 4 * radius; y < int(edge) - 4 * radius; y += 2 * radius + 1) {
            for (int x = 4 * radius; x < int(edge) - 4 * radius; x += 2 * radius + 1) {
                double aperture = 0;
                size_t pixels_in_aperture = 0;
                for (int dy = -radius; dy <= radius; ++dy) {
                    for (int dx = -radius; dx <= radius; ++dx) {
                        if (dx * dx + dy * dy > radius * radius) continue;
                        const float* cmy = &data[3 * (size_t(y + dy) * edge + x + dx)];
                        aperture += transmission(p.film, bands, cmy);
                        ++pixels_in_aperture;
                    }
                }
                const double density = -std::log10(aperture / pixels_in_aperture);
                const double delta = density - mean;
                mean += delta / ++count;
                sum_of_squares += delta * (density - mean);
            }
        }
        const double rms = 1000 * std::sqrt(sum_of_squares / (count - 1));
        std::cout << "# blue grain\t" << ev << '\t' << kodak_density << '\t' << mean
                  << '\t' << kodak_rms << '\t' << rms << '\n';
        require(std::abs(mean - kodak_density) < .04 && rms / kodak_rms > .53 && rms / kodak_rms < .80,
                "5219 blue grain drifted from the documented model baseline");
    }
}

} // namespace

int main(int argc, char** argv) try {
    require(argc == 3, "Usage: film_reference <bundled engine resources> <BabelColor Avg30 CGATS>");
    const std::string resources = argv[1];
    std::string error;
    const auto patches = load_chart(argv[2]);
    Blob blob;
    Colour colour;
    require(blob.open(resources + "/spektrafilm_constants.bin", error), error);
    require(colour.init(blob, error), error);
    std::unique_ptr<gpu::Gpu> gpu(gpu::Gpu::create_metal(nullptr, resources + "/spektrafilm.metallib", error));
    require(bool(gpu), error);
    Params p;
    require(init_params(resources, "kodak_vision3_500t", "kodak_supra_endura", Json{}, p, error), error);
    p.io.input_color_space = "sRGB";
    p.camera.auto_exposure = false;
    p.camera.film_format_mm = .064;
    p.film_render.halation.active = false;
    p.film_render.halation.headroom_ev = 0;
    p.film_render.halation.boost_ev = 0;
    p.film_render.grain.active = false;
    p.film_render.glare.active = false;
    p.print_render.glare.active = false;
    p.io.output_gamut_compress.algorithm = "off";
    SetupCache cache;
    Pipeline pipe(gpu.get(), &colour, &blob, &cache);
    require(pipe.build(p, error), error);
    std::cout << std::fixed << std::setprecision(7);
    check_tone(pipe, *gpu, p, colour.wavelengths());
    check_colors(pipe, *gpu, p, colour, blob, patches);
    check_blue_grain(*gpu, colour, blob, cache, p);
    return 0;
} catch (const std::exception& error) {
    std::cerr << "film reference: " << error.what() << '\n';
    return 1;
}
