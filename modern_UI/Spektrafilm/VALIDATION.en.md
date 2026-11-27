# Silverphase validation

[简体中文](VALIDATION.md) · **English**

Current acceptance tests cover the native C++/Metal engine and complete workflows with real photos. The frozen Python fork is no longer retained and is not a prerequisite for acceptance. The `engine/tests/parity_*.py` scripts are historical tools. Do not mark an unrun oracle-parity check as passed or pass off a new script as an independent physical reference. Color-science claims remain bounded by the measured profiles and input decoding.

## Reproducible checks

### 5219 negative film and spectral patches

The staged checks draw on [Negs’ GPU validation report](https://github.com/noahhaasis/negs/blob/479a5674bb9d43af5c08fbd7307b367bec7bf10b/docs/gpu-vs-cpu-quality.md). Download the [BabelColor Avg30 measured spectra](https://babelcolor.com/index_htm_files/CC_Avg30_spectrum_CGATS.txt). The driver checks the original file’s SHA-256. Keep the measured patch file in the build or external-fixture directory. Build the test driver, then pass the engine resource directory inside the macOS app being validated:

```sh
engine/build.sh tests
python3 engine/tests/check_film_reference.py \
  '/path/to/Silverphase.app/Contents/Resources/Resources/engine' \
  '/path/to/CC_Avg30_spectrum_CGATS.txt' \
  --report /tmp/5219-stages.tsv
```

- The 5219 check uses 14 exposure points from [page 4 of Kodak’s 2015 ECN-2 technical data](https://www.kodak.com/content/products-brochures/Film/VISION3-500T-Color-Negative-Film-7219-TECHNICAL-DATA.pdf#page=4) and estimates transmission density using [ISO 5/3 Status M weights](https://cdn.standards.iteh.ai/samples/20101/642e3ed0adfe43be85e67b2c413cca56/ISO-5-3-1984.pdf). Exposure is aligned once at zero stops using only the green channel. The thresholds assess curve shape.
- For 24 color patches under the film profile’s reference illuminant, the test compares direct spectral integration with the production RGB input path. Each path is normalized to the same ideal white; errors are reported in EV per sensitivity channel. Direct integration uses the current film response curves. It measures the spectral approximation; real-world color still needs independent film measurements.
- Stage regression records input exposure, negative CMY, Supra Endura paper CMY, and output RGB. Fixed inputs cover neutrals, saturated colors, values above white, and near-black. Grain and glare are disabled for reproducibility. Stage tolerances identify where software output drifts.
- Grain is measured separately on uniform fields. At three high-density points, transmittance is averaged through a 48 µm circular aperture before computing blue-channel density fluctuations. The threshold allows for sampling variation and checks the current grain model’s statistics. The manufacturer’s blue-channel granularity is higher; this known difference remains in the baseline.

### Fotufilm DIR edge-enhancement review

On 2026-11-25, native Metal checks were repeated for all 29 imported Fotufilm profiles. The first pass halved spatial adjacency weight for nine color negatives. The second pass added lower exposure and a second pixel pitch, identifying 17 of the 29 profiles that needed a spatial adjacency limit.

The original Fotufilm Pro 160NS has its own DIR inhibition matrix, release curve, and diffusion scale. After conversion by Negs, the Silverphase profile uses Spektrafilm’s generic color-negative DIR preset and diffusion model. Development inhibition diffusing across adjacent areas produces overshoot on the bright side of an edge and undershoot on the dark side, even with scan sharpening off. [Original Fotufilm profile](https://github.com/DhaliwalX/fotufilm-engine/blob/96623ba0831a52dbddcda35727a206d4123a8b5f/Sources/FotufilmCore/Stocks/pro160ns.json) · [Port provenance](../../license/DATA-SOURCES.md#experimental-fotufilm-profiles)

The current correction blends diffused inhibition with same-pixel inhibition at the development stage. The 17 profiles use individual spatial weights ranging from 0.08 to 0.70. The two weights add to 1, preserving the DIR color response and density-curve precorrection under uniform exposure. The existing DIR slider still controls the overall effect. Before-and-after comparisons showed at most one 16-bit code-value difference on uniform RGB patches at both pitches. Pro 160NS, Phoenix 200, and Infrared Color were pixel-identical between whole-frame and strip outputs. [Spatial adjacency implementation](../../engine/src/pipeline/pipeline.cpp)

#### Test conditions

- A 1024 × 256 neutral linear-RGB step with the edge at column 512. Three equal-ratio exposure steps: `0.04 → 0.12`, `0.08 → 0.24`, and `0.16 → 0.48`. Pixel pitches were 8.838 µm (the 120-format case) and 3.90625 µm (close to 135 format at the same resolution). The engine’s physical pitch is derived from the format’s long edge and pixel width.
- Render mode was `full`: negatives used Portra Endura and reversal stocks were scanned directly. Auto metering, grain, halation, paper glare, and scan sharpening were off. Each condition was rendered with DIR disabled and at `1.00×`, for 174 on/off pairs. The middle step was rendered 58 more times with the previous engine and the same resources.
- The finished 16-bit RGB code values were weighted by `0.2126 / 0.7152 / 0.0722`. Rows 32–223 were averaged. Columns 256 and 768 represented the uniform areas on either side. The largest overshoot or undershoot in columns 494–529 was measured as a percentage of the code-value difference between those areas.

#### Full-catalog results

DIR still produced measurable overshoot or undershoot in 24 color profiles. With DIR off, the excursion was zero for all 29 profiles under every tested condition. The engine bypasses DIR for five black-and-white profiles. At the current defaults, all 174 pairs were below the 40% internal screening threshold. The maximum was 34.8% for Reala 500D at lower exposure and near-135 pitch. The remaining 12 profiles were pixel-identical to the previous engine at both pitches for the middle step.

The table shows before-and-after excursions for the middle step (0.08 → 0.24), plus the current maximum across all six conditions. Values are percentages of the difference between uniform areas.

| Profile | 120 pitch before | 120 pitch now | Near-135 pitch before | Near-135 pitch now | Current maximum across six conditions |
|---|---:|---:|---:|---:|---:|
| Agfa Agfachrome 100 | 16.7 | 12.1 | 18.4 | 13.3 | 31.3 |
| Agfa Agfachrome 200 | 14.3 | 14.3 | 15.8 | 15.8 | 31.5 |
| Agfa Agfachrome 50 | 16.6 | 12.0 | 18.3 | 13.2 | 30.4 |
| CineStill 400D | 34.6 | 15.8 | 38.3 | 17.6 | 30.0 |
| CineStill 800T | 36.6 | 16.9 | 40.4 | 18.8 | 32.2 |
| Infrared Color (creative) | 24.3 | 6.9 | 27.1 | 7.6 | 29.9 |
| Fujifilm Neopan 100 Acros II | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| Fujifilm Astia 100F | 15.6 | 15.6 | 17.2 | 17.2 | 32.6 |
| Fujifilm Eterna 500 | 57.3 | 15.9 | 62.4 | 17.6 | 33.0 |
| Fujifilm Eterna Vivid 500 | 62.3 | 14.6 | 67.2 | 16.2 | 32.3 |
| Fujifilm F-64D | 60.8 | 15.0 | 66.1 | 16.6 | 33.2 |
| Fujifilm Pro 160NS | 57.5 | 17.4 | 62.8 | 19.3 | 33.4 |
| Fujifilm Superia Reala 100 | 69.2 | 11.9 | 74.0 | 13.2 | 31.2 |
| Fujifilm Reala 500D | 46.9 | 15.2 | 51.4 | 16.8 | 34.8 |
| Fujifilm Superia 200 | 77.6 | 13.0 | 81.3 | 14.4 | 28.8 |
| Fujifilm Velvia 50 | 10.3 | 10.3 | 11.4 | 11.4 | 23.0 |
| Harman Phoenix 200 | 31.4 | 3.5 | 33.4 | 3.8 | 21.4 |
| Ilford Delta 3200 Professional | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| Ilford FP4 Plus | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| Ilford HP5 Plus | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| Kodak Aerochrome III 1443 (infrared) | 15.8 | 7.8 | 17.5 | 8.4 | 28.7 |
| Kodak Aerocolor IV 2460 | 33.1 | 18.2 | 36.7 | 20.3 | 30.6 |
| Kodak Kodachrome 200 | 14.3 | 14.3 | 15.7 | 15.7 | 28.7 |
| Kodak Kodachrome 25 | 14.1 | 14.1 | 15.6 | 15.6 | 31.5 |
| Kodak Kodacolor 100 | 45.9 | 15.5 | 50.4 | 17.3 | 33.3 |
| Kodak T-MAX 100 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| Lomography Color Negative 100 | 42.9 | 15.3 | 47.2 | 17.0 | 33.0 |
| LomoChrome Metropolis | 9.0 | 9.0 | 9.9 | 9.9 | 16.3 |
| LomoChrome Turquoise | 10.8 | 10.8 | 12.0 | 12.0 | 21.0 |

#### Lower-exposure retest

For the 0.04 → 0.12 step at 120-format pitch, the table shows excursions as percentages of the difference between uniform areas. The baseline is the first pass, which limited spatial adjacency for nine profiles.

| Profile | First pass | Current |
|---|---:|---:|
| Harman Phoenix 200 | 319.3 | 19.2 |
| Fujifilm Superia 200 | 120.2 | 25.7 |
| Fujifilm Superia Reala 100 | 97.8 | 28.0 |
| Infrared Color (creative) | 88.9 | 27.2 |
| Fujifilm Pro 160NS | 54.7 | 30.0 |

In color-gradient edge spot checks at both pitches, the maximum channel excursion fell in 31 of 34 before-and-after comparisons and increased in three. The largest increase was 451 16-bit code values. All tested color excursions remained below 40% of the largest channel difference between uniform areas. Local color-edge behavior varies with the stock and input; uniform color-patch results apply only to uniform areas.

#### Regression and limits

Build the native dynamic library, set the engine resource directory, and run the [Fotufilm edge regression](../../engine/tests/fotufilm_dir_edges.py):

```sh
export SPEKTRAFILM_ENGINE_RESOURCES="$PWD/modern_UI/Spektrafilm/Spektrafilm/Resources/engine"
python3 engine/tests/fotufilm_dir_edges.py
```

The 40% threshold is an engineering screen for these six test conditions, not a physical tolerance. Spatial weights came from synthetic edge comparisons; the first pass also drew on the user’s visual feedback about a Pro 160NS portrait. Independent testing with the original ARW from the screenshot, original Fotufilm output under matched conditions, and real negative density profiles are still missing. Manufacturer data can support the DIR edge-enhancement mechanism and guide a future negative MTF comparison. It does not directly validate the percentage excursion in the finished-image step response measured here.

A diagnostic report can be saved separately. Start with two stocks available in both implementations. The report retains the 40% screen and records overshoot and undershoot for each RGB channel, plus the effect of toggling DIR on the center pixel of five uniform neutral exposures (−2.5, −1, 0, +1.5, and +3 EV relative to 0.18):

```sh
python3 engine/tests/fotufilm_dir_edges.py \
  --profile fujifilm_pro_160ns_fotufilm --profile fujifilm_velvia_50_fotufilm \
  --report /tmp/silverphase-dir-report.json
```

The report measures finished RGB code-value differences, not negative density. If a channel’s difference between uniform areas is less than one code value, its excursion percentage is `null`. Upstream [Fotufilm #352](https://github.com/DhaliwalX/fotufilm-engine/pull/352) uses the same exposure series in its schema v4 tests but checks its own synthetic profiles and linear output. Do not apply the upstream tolerance to this report or assume that two stocks with the same name use the same profile. For cross-engine comparison, fix the linear input space, physical format, stock profile, disabled spatial effects, and render stage before comparing DIR on/off differences within each engine. The report neither imports upstream profiles nor changes rendering.

[Fujifilm Pro 160NS data sheet, §22](https://asset.fujifilm.com/www/jp/files/2024-04/6b75b1c1cb4253623fb2cd7a56ff7443/datasheet_pro160ns_01.pdf) · [Fujifilm research report, §3.2.2](https://asset.fujifilm.com/www/jp/files/2019-10/a2b78141b856eedf5ba0bb0c403c69fc/rd_report_ff_rd051_all.pdf)

### Real photos

From the repository root, build the engine bundle and run the Python standard-library validation entry point:

```sh
engine/build.sh bundle
python3 modern_UI/Spektrafilm/Tools/validate.py \
  --photos-root '/path/to/photos' \
  --scope photos \
  --output /tmp/silverphase-photos-validation
```

The `photos` scope checks real photos, DI export, and the current canvas contract. This gate requires zero failures and zero skips. Missing fixtures or hash mismatches fail preflight rather than silently substituting synthetic images. Choose a fresh `--output` directory for every run so existing `.xcresult` bundles aren’t overwritten.

For full integration:

```sh
python3 modern_UI/Spektrafilm/Tools/validate.py \
  --photos-root '/path/to/photos' \
  --scope full \
  --output /tmp/silverphase-full-validation
```

The full suite still includes older cases tied to specific fixtures and disabled performance tests, which can be skipped. The entry point marks this as `partial: inspect skipped tests` in `summary.json`. A successful exit is not evidence that all fixture-dependent cases ran. Inspect pass, failure, and skip counts together.

Long batches are opt-in, for example full-resolution JPEG export of 50 distinct RAW files:

```sh
python3 modern_UI/Spektrafilm/Tools/validate.py \
  --photos-root '/path/to/photos' \
  --scope photos --batch-count 50 --batch-format jpeg \
  --output /tmp/silverphase-batch-validation
```

The batch recursively enumerates RAW files, sorts by relative path, takes the requested count, and makes uniquely numbered copies in a temporary directory. Each photo is selected, rendered, and exported at full resolution; the checks confirm the files were written and the full-resolution render count equals the photo count. `batch.tsv` records per-photo timing and a memory sample after export. The final sample is not a peak, and timings are not a platform performance guarantee. TIFF uses more temporary disk; size the batch for the expected full-resolution output.

## Maintainer’s fixed cases (2026-10-31)

The [case manifest](SpektrafilmTests/Fixtures/release-case-manifest.json) pins ten Sony ILCE-7CM2 RAWs with 7008 × 4672 ImageIO dimensions, multiple orientations, and different ISO settings. The local copies are in the Git-ignored `private-fixtures/release-cases/` directory. Git stores only relative filenames, SHA-256 hashes, dimensions, orientations, and scene descriptions, not RAW files, previews, private sidecars, or exports. The local copies can still be used when the external drive is disconnected.

```sh
DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer \
python3 modern_UI/Spektrafilm/Tools/validate.py \
  --photos-root private-fixtures/release-cases \
  --scope cases --batch-format jpeg \
  --output /tmp/new-silverphase-case-run
```

The `cases` scope uses only the ten distinct RAW files in the manifest, rather than picking other photos recursively. It checks the canvas contract, DI with a real RAW, and full-resolution batch export one photo at a time. It verifies count, dimensions, bit depth, ICC, decodability, and full-render count. Missing inputs, hash mismatches, failures, or skips fail the gate. Use `--batch-format tiff` for the same fixed set in TIFF. Tests run on temporary copies; the source mirror explicitly excludes `private-fixtures/` and `output/`.

This differs from the four-role `photos` gate below. All ten inputs are real RAWs, not externally developed encoded JPEG/TIFF, and they do not fill historical camera-specific gaps for Nikon, A7 III, and others. The dated run passed 16 tests with zero failures and zero skips, and all ten photos exported as full-resolution JPEG. This is not independent validation of the physical model. See the [case report](../../performance/VALIDATION-CASES-2026-10-31.md) and [screenshots](../../screenshots/current/README.md) for the interface and 100% grain/halation comparisons.

## External fixtures and isolation

The [validation manifest](SpektrafilmTests/Fixtures/validation-manifest.json) stores relative paths, camera details, ImageIO dimensions, format information, and SHA-256 hashes only. The four selected inputs are:

| Role | Input | What it tests |
|---|---|---|
| raw-standard | Sony ILCE-7RM5, 6240 × 4160 ARW | Real RAW decode, edit/reset, and full-resolution export |
| raw-high-resolution | Same camera, 9504 × 6336 ARW | 60 MP input and deterministic edit/reset |
| encoded-jpeg | 4096 × 3072, 8-bit sRGB JPEG | Encoded RGB input; not a RAW reference |
| encoded-tiff | 6336 × 9504, 16-bit ProPhoto TIFF | Externally rendered RGB; does not establish recovery of original scene data |

Other machines can use their own manifest via `--manifest /path/to/manifest.json`. It must contain four distinct roles with real relative paths, SHA-256 hashes, and ImageIO dimensions. Confirm the input format and color semantics. Do not replace a missing RAW with a synthetic TIFF. Photos and the manifest can live outside the repository. New inputs require a new coverage statement; do not reuse the results from this set.

The recorded dimensions come from ImageIO file properties. EXIF orientation may swap the decoded width and height. Both RAW dimensions come from one camera and do not establish coverage across different sensors or manufacturers.

The validation entry point first checks source-photo hashes, then copies the source and fixtures to a temporary location to avoid macOS privacy restrictions on the test host reading Documents. Each test makes its own photo copies without existing sidecars. Edits and exports are written only beside the copies. On completion, the driver rechecks the original photo hashes and removes the temporary source and fixtures. Logs, `.xcresult`, JSON, and batch tables stay in the output directory. They can include private filenames and should not be uploaded as release assets.

These photos were not renamed to stand in for legacy Nikon Z7 II or A7 III fixtures. Cases that depend on those particular inputs remain explicitly skipped until migrated to the current app contract. The current Sony files cannot substitute for cases such as checking Nikon’s default lens correction.

## Gate coverage

- **Real pixels:** changing print exposure changes real output; after disabling grain and glare, reset is pixel-identical. This verifies controls and state propagation, not the physical accuracy of the film model.
- **Finished exports:** full-resolution TIFF/JPEG decodes in ImageIO, matches the decoded orientation and dimensions, and has the correct bit depth and target ICC profile.
- **DI:** a real-RAW 16-bit Cineon master has no display ICC profile, and its viewing LUTs are present alongside it. Ordinary RGB export of DI writes the display view with an ICC profile.
- **Current canvas:** showing and hiding the floating inspector changes the available area and position of Fit while the Metal canvas retains its dimensions. The removed hover-capsule area is absent.
- **Development:** GPU tests check the layered reveal, an unchanged endpoint image, cancellation, and Reduce Motion.
- **Native engine:** run the following smoke tests, math guard, and applicable extended gates when changing generated `.cube` files, kernels, parameters, or engine boundaries.

```sh
engine/build.sh all
engine/build/gpu_smoke engine/resources/spektrafilm.metallib
engine/tests/check_math_guard.sh
# External Python needs numpy for development tests only; it is not a runtime dependency.
PYTHONPATH=engine/tests <python-with-numpy> engine/tests/upstream_controls.py
```

See the [dated validation report](../../performance/VALIDATION-REPORT-2026-10-01.md) for the recorded run.

The `validate.py` entry point runs project indexing and bundle resource checks automatically. A full XCTest run does not replace native checks. These tests also do not establish live-window frame rates, real gestures, visual quality, coverage of additional cameras, or the results of signing and notarization.
