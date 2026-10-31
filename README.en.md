# Silverphase

[简体中文](README.md) · [English](README.en.md)

**Silverphase is a film-and-paper process simulator for macOS, iPhone, and iPad.** It takes a photograph through camera input, film, development, print, and scan, exposing controls in photographic terms instead of presenting every research-model parameter. It is not intended to replace Lightroom or Capture One: general grading, asset management, and extensive local retouching belong in tools built for those jobs.

Silverphase is an independent derivative of [SpektraLab](https://github.com/JamesQiu2005/SpektraLab), retaining its Git history and native macOS/C++/Metal foundation. The film and paper model and measured profiles originate in Andrea Volpato's [spektrafilm](https://github.com/andreavolpato/spektrafilm). Silverphase's product direction and interface are independent of both projects; neither upstream project is affiliated with or endorses Silverphase.

> This repository contains work-in-progress source, not a signed and notarized macOS release. Some directories, Xcode targets, and commands still use the internal engineering name `Spektrafilm`; the app's displayed name is `Silverphase`. The iOS editor uses the same engine but has not reached full desktop feature parity; see the [iOS guide](ios/README.md).

## From photograph to print

1. Open an image or folder, then choose a frame in the preview and filmstrip.
2. Choose a film and paper in the bottom material strip. Positive film bypasses the paper-print stage; you can also choose “No Print Profile” to view the developed film without paper.
3. Use the right rail to adjust camera input, film, development, print, and crop in process order. This is a process-parameter rail, not a separate general-purpose grading layer.
4. In the export page, choose either a finished image or a film intermediate for further grading.

The main controls are:

- **Camera input:** metering, film exposure, white balance, and lens correction when available. Film exposure acts before the simulated film response; it is not a post-export rescue slider.
- **Film:** stock, physical frame size, grain, film halation, emulsion scatter, and independent effect strengths. Frame size participates in the scale conversion for grain and spatial effects; it is not merely metadata. The halation menu offers profile-based, high, medium, low, and off; when enabled, its amount runs from 1–4×. These describe the simulated visible effect, not a claim about the exact anti-halation construction of a real stock.
- **Development:** contrast and color separation relative to the stock's profile defaults, plus scene-latitude measurement and explicit scene placement.
- **Print:** paper stock, print exposure, yellow/magenta filtration, preflash, and a separate print/scan glare effect. Print glare is not film halation.
- **Inspection:** preview, histogram, crop, and export soft proof. The local-mask interaction is still being designed and is not exposed in the current build.

The UI and source are authoritative for exact ranges and defaults. This README does not present every underlying model field as though it were a shipped control.


B&W materials include SpektraLab's **Tri-X 400, HP5 Plus 400, T-Max 100, Acros II and Ilford Multigrade IV RC paper**. Spectral response and density curves form the image. Multigrade provides grades 00–5 with filtration/exposure compensation; eight Wratten lens filters are available. See [B&W sources and limitations](engine/tools/profile_sources/blackwhite.md) and [adoption provenance](engine/resources_product/UPSTREAM.json) for chemistry, fitting and grain assumptions.

Film edges and date backs form within the film pipeline: 135, half-frame, multiple 120 and panoramic gates, perforations, markings, fog and leaks. Date availability depends on format: 120 uses the margin; panoramic formats have no date back. Desktop also saves two source photos as a `.spektrapair` half-frame composition; iOS has not yet adopted two-photo pairing. See [film-edge modeling notes](engine/tools/profile_sources/film_edge.md).

## Two export paths

**Finished Film Render:** Silverphase completes the film-and-paper process and writes a ready-to-use JPEG, 8-bit PNG, or 16-bit TIFF. Export recipes provide destination color-space and other options; the export page soft-proofs the selected destination. Choose this when the film process is the finished image.

**Gradeable Film Intermediate:** the export page calls this a `DI package`. Its master is an **untagged 16-bit Cineon-log TIFF with ProPhoto RGB primaries**, accompanied by two fixed **DI-view `.cube` LUTs** (to ProPhoto RGB and Rec.709). A second TIFF page provides a view preview. The master preserves film contrast and bypasses paper rendering and output grading. These are viewing transforms, **not the selected paper's print LUT**. Use the supplied view to inspect the master; treat it as Cineon data rather than assigning a display ICC profile. Exporting a DI through the ordinary JPEG/TIFF route writes its display view with the destination profile.

The two view LUTs are shared within each output directory. See the [engineering guide](modern_UI/Spektrafilm/README.md) for the delivered files and color semantics.

The two paths serve different delivery needs. Do not deliver the TIFF inside a DI package as if it were an ordinary finished TIFF. See the current export page for the available format and recipe options.

## Architecture

- `modern_UI/Spektrafilm/Spektrafilm/`: SwiftUI interface, session, preview, and export.
- `ios/Silverphase/`: native iOS/iPadOS editor sharing the current engine, catalogue, geometry and icon; see the [control audit](ios/CONTROL-AUDIT.md) for differences.
- `engine/`: C++20 render engine, Metal kernels, film/paper resources, and test tools.
- `modern_UI/Spektrafilm/Tools/`: Xcode project generation and bundled-resource/license checks.
- `modern_UI/design/UI-SPEC.md`: UI specification; `ARCHITECTURE.md` and `rfc/`: architecture and historical design records. Older documents may still describe the removed general grading layer; the current source takes precedence.

The engine is compiled into both platform apps. Running the app requires no Python service, subprocess, or virtual environment. The app calls the C++/Metal engine through a C interface; Metal renders the image, while Apple imaging and color-management components handle file decoding and delivery. Python scripts used for development are not runtime dependencies.

## Build locally

You need an Apple-silicon Mac, macOS 15 or later, and Xcode with the Metal toolchain. The current local toolchain is Xcode 27.1. Its Xcode project file is committed, so a normal build does not require regenerating it.

If Command Line Tools is selected, first set `export DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer` in the current shell (adjust for the installed Xcode). From the repository root:

```bash
engine/build.sh bundle
xcodebuild -project modern_UI/Spektrafilm/Spektrafilm.xcodeproj \
  -scheme Spektrafilm -configuration Debug \
  -derivedDataPath build/DerivedData build
```

The app is written to `build/DerivedData/Build/Products/Debug/Silverphase.app`. Re-run `engine/build.sh bundle` after changing engine resources or Metal shaders. Xcode's pre-build check rejects missing resources, but does not generate them. The default build uses development-only ad-hoc signing; it is not a distributable release.

Run tests with:

```bash
xcodebuild -project modern_UI/Spektrafilm/Spektrafilm.xcodeproj \
  -scheme SpektrafilmTests -configuration Debug \
  -derivedDataPath build/DerivedData test
```

Real-photo validation uses an external manifest and temporary copies; private photographs are not committed. See the [validation guide](modern_UI/Spektrafilm/VALIDATION.md) for reproducible commands, coverage and skips. Historical Python-reference parity scripts remain available, but current acceptance does not depend on the retired frozen reference environment. See the [project notes](modern_UI/Spektrafilm/README.md) and [developer notes](AGENTS.md) for more build details.

For iOS/iPadOS 18+ simulator builds, device signing, adaptive preview and diagnostic scopes, see the [iOS guide](ios/README.md). The [documentation index](docs/README.md) maps current guides; the [2026-10-28 validation report](performance/VALIDATION-REPORT-2026-10-28.md) records this integration and its unverified areas.

## Origins, licenses, and independence

Silverphase retains SpektraLab's history and continues development from it. Hanze Qiu created SpektraLab's native macOS app and C++/Metal port; Andrea Volpato created spektrafilm's physical model and measured profiles. We thank both authors for making their work available. Changes in name and interface do not erase that provenance, nor do they imply that the upstream authors endorse these design choices.

The app and C++ engine are **GPL-3.0-or-later**; film/paper profiles and their derived print-preview LUTs are **CC BY-SA 4.0**; Apple's metal-cpp bindings are **Apache 2.0**. Full license texts and a record of changes to the profiles and LUTs are in the [license directory](modern_UI/Spektrafilm/Spektrafilm/Resources/Licenses/). Binary distribution must also meet the applicable source, attribution, and license-text obligations.

Silverphase, SpektraLab, and spektrafilm are independent projects. “Based on” does not mean an official continuation or collaboration.

See [LICENSES.md](LICENSES.md) for component licensing, [CONTRIBUTING.md](CONTRIBUTING.md) for contributions, and the [release review](docs/OPEN-SOURCE-RELEASE.md) for provenance and publication checks. See [local materials](docs/LOCAL-MATERIALS.md) for private experiments and the public-build switch.

## Current interface examples

![Current Silverphase editor with the lotus case](screenshots/current/silverphase-lotus-2026-10-31.jpg)

Actual app window, captured 2026-10-31; experimental materials visible in the capture are available only in local builds containing private materials. See [the record-display case, 100% grain and halation on/off](screenshots/current/README.md) and the [pinned-photo validation workflow](modern_UI/Spektrafilm/VALIDATION.md). RAW originals remain local.
