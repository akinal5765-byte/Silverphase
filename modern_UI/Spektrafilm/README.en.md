# Silverphase macOS engineering guide

[简体中文](README.md) · **English**

The desktop app has its own version sequence. The [Xcode project generator](Tools/gen-project.py) defines the source build version; see [GitHub Releases](https://github.com/akinal5765-byte/Silverphase/releases) for installers and release notes.

This directory contains Silverphase’s SwiftUI/AppKit app. The Xcode target and some internal paths are still named Spektrafilm; the product is called Silverphase. It builds on Hanze Qiu’s native SpektraLab port and Andrea Volpato’s spektrafilm model and profiles. See the [repository overview](../../README.en.md) for provenance and licensing.

## Current structure

- `Spektrafilm/Model/Session.swift`: asynchronous decoding, engine sessions, parameter scheduling, render caching, multi-selection, clipboard, undo, and per-photo state.
- `Spektrafilm/Service/EngineClient.swift`: directly calls the C ABI. The Service directory name is historical; there is no Python service, stdio bridge, or runtime subprocess.
- `Spektrafilm/Canvas/`: Metal canvas, ProPhoto display, geometry, histogram, and layered development animation.
- `Spektrafilm/Panels/`: floating process inspector, film/paper selector, and photo navigation strip.
- `Spektrafilm/Export/`: export recipes, soft proofing, background texture readback, and ImageIO file writing.
- `Spektrafilm/Resources/`: engine resources, catalog, film and paper artwork, DI viewing LUTs, and licenses.
- `SpektrafilmTests/`: standalone XCTest target that compiles both app and engine sources.
- `Tools/`: project generation, resource checks, validation, signing, notarization, and DMG packaging.

The app has one layout: a top toolbar, a floating process panel, and bottom film and photo navigation controls. The Metal canvas keeps its window size; Fit and zoom use the unobstructed area. The bottom strip can stay pinned or hide automatically. Tab hides or shows the editing panels.

A newly opened photo starts in **Prep**, where you can adjust input tone, exposure, detail, and color before film exposure. Camera-preview brightness matching for supported RAW files is a Prep option. The main process is **Prep → Film → Development → Color Enlargement (Print) → Scan / Output**; Crop and Film Edge are separate tools. Metering and film exposure are in **Film**.

There is no second legacy layout or separate general-purpose color-grading rail. The app can still read old grading information from existing sidecars. See the [current UI specification](../design/UI-SPEC.md).

## Build

Requires Apple silicon, macOS 15 or later, and Xcode with the Metal toolchain (Xcode 27.1 in the documented setup). If Command Line Tools is selected, set `DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer` for the commands below. Run from the repository root:

```sh
engine/build.sh bundle
xcodebuild -project modern_UI/Spektrafilm/Spektrafilm.xcodeproj \
  -scheme Spektrafilm -configuration Debug \
  -derivedDataPath build/DerivedData build
```

The app is built at `build/DerivedData/Build/Products/Debug/Silverphase.app`. Profile data and provenance in `engine/resources/` and `engine/resources_product/` are versioned. Product profiles overlay the same profile directory during packaging; paper-grade tables and original notices ship with the bundle. `engine/build.sh` compiles the Metal library and stages it under the app’s Resources/engine directory. Bundle checks reject missing data but do not regenerate profiles.

After adding or removing a Swift, Metal, or engine C++ source file, run:

```sh
python3 modern_UI/Spektrafilm/Tools/gen-project.py
python3 modern_UI/Spektrafilm/Tools/gen-project.py --check
modern_UI/Spektrafilm/Tools/check-bundle-resources.sh
```

The app build does not require a Python environment. Project and catalog generation uses only the Python standard library. `Tools/make-smoke.py` belongs to the old Python fork’s fixture-generation workflow and is not a current validation entry point. Use `Tools/validate.py` to select and isolate current test inputs.

## Images and output

macOS decodes RAW files. The engine receives scene-linear input, whereas original comparison uses a display decode. Different RAW decoders may apply different camera profiles, tone, or lens processing. Do not rewrite measured film or paper profiles to compensate for different inputs.

For JPEG, encoded TIFF, and other RGB files, the transfer function is decoded at the input boundary. An externally rendered file may already contain tone adjustments; it does not establish that original scene radiance was recovered. Validation keeps RAW decoding separate from encoded RGB input and does not use a processed TIFF as a RAW reference.

The working space and standard canvas textures are ProPhoto RGB. Previews and full-resolution renders use the same process parameters; grain and spatial effects scale to the physical film format. Zoom does not change the film profile. Full-resolution export follows the canvas geometry, converts to the recipe’s target color space, and replaces the destination after writing a temporary file.

Desktop **Output Proof** uses the same finished-image pipeline as export to show the selected target gamut. Version 1.4.0 compresses less of the low- to mid-saturation colors already inside that gamut; compression remains smooth near the boundary. Colors outside sRGB, such as a saturated blue sky, can still look less saturated than on the standard canvas. A color-managed Display P3 workflow may preserve more colors. If you need sRGB compatibility, check the sRGB soft proof rather than expecting an exact match with the ordinary canvas.

Under **Film → Format ⋯ → Simulation Size…**, set the desired long edge after cropping. **Use Original** restores source sampling. The engine resamples linearly before generating grain and halation based on the selected physical film format. An export recipe can reduce the finished dimensions further. Simulation size is saved per photo; half-frame pairs have their own geometry rules.

| Path | Current output |
|---|---|
| JPEG | 8-bit with the selected target ICC profile; quality follows the export recipe |
| PNG | Lossless 8-bit with the selected target ICC profile |
| TIFF | 16-bit with the selected target ICC profile; the current finished-image path writes uncompressed TIFF |
| DI package | `<name>_DI.tif`: untagged 16-bit Cineon master and a viewing-preview page, with two fixed DI viewing `.cube` files alongside |

DI uses Cineon log code values with ProPhoto RGB primaries. It preserves film contrast and bypasses paper printing and post-output grading. The two 65³ viewing LUTs are Cineon → ProPhoto RGB and Cineon → Rec.709. These are viewing transforms, not printing tables for the currently selected paper. The app canvas uses the bundled ProPhoto view LUT. When DI is exported as ordinary RGB, the app applies this view first and then converts to the recipe’s target color space and embeds its ICC profile.

Do not treat the Cineon master as an ordinary ICC-tagged image. Use the accompanying LUT to view it and avoid applying the full DI view after an existing Cineon conversion. The view includes highlight mapping, but it does not rewrite master image data. See the [DI resource documentation](Spektrafilm/Resources/DI/README.md) for provenance.

## Validation and distribution

The [validation guide](VALIDATION.en.md) covers reproducible test commands, real-photo manifests, external fixture handling, and acceptance limits. Automated tests do not replace visual or frame-rate checks in the live app. Descriptions of the legacy layout, Python service, or older density-based DI in architecture archives and RFCs are historical. This guide describes the current implementation.

`Tools/package.sh` retains the archive, Developer ID signing, DMG, notarization, and verification workflow. Use `tools/package-public-release.py` for a public package without Developer ID signing. It explicitly labels ad-hoc signing and the absence of notarization, excludes private resources, and does not claim to satisfy Gatekeeper’s default trust checks. See [binary releases](../../docs/BINARY-RELEASES.md) for downloads and installation.

## Shared platforms and film presentation

The iOS project references `StockCatalogCore.swift`, `ParamValue.swift`, and `Geometry.swift` directly rather than copying them. `MobileDesktopContractTests` checks desktop defaults captured by the mobile app. Run both project generators when modifying shared files. iOS implements its own native interface, operation state, memory limits, and export policy; see the [iOS guide](../../ios/README.md).

`FilmEdge.swift`, `ShootingData.swift`, `Session+FilmPresentation.swift`, and engine overscan handle the film border and date back; `FilmCanvasInput.swift` prepares the film-gate input. Lens filters affect film exposure but not the border or date exposure. These parameter changes require the film to be developed again; the old negative cannot be reused.

**Edge Label** replaces the film name printed in the border of the current photo or half-frame pair. It supports up to 10 characters (A–Z, digits, spaces, and `+ - . /`); the stock’s layout may fit fewer. Clear the field to restore the default film name. Frame numbers, perforations, and framing do not change.

`HalfFramePair.swift` defines the `.spektrapair` document that references source photos. `PairComposer.swift` composes the pair in linear space. The pair’s sidecar stores shared printing and border settings; the source photos retain their own capture state. Do not commit user pairs or source photos.

See the profile provenance for black-and-white stocks and Multigrade paper grades. `PaperGrade.swift` maps paper grades to filtration and exposure compensation; the compensation is applied exactly once. All platforms use the same production `Silverphase.icon`; earlier artwork is in the [icon design directory](../../design/app-icon/README.md).

See the [architecture overview](../../ARCHITECTURE.md) and the dated [2026-10-28 validation report](../../performance/VALIDATION-REPORT-2026-10-28.md).

## Release history

The current desktop release is **1.4.0 (build 7)**. See the [release notes](releases/1.4.0.md) and the [migration guide](../../docs/MACOS-IDENTITY-UPGRADE.md) for existing app data. The [1.3.1 source notes](releases/1.3.1.md) cover the change to the metering and film-exposure controls, Fotufilm artwork, and DIR edge adjustments.

The public Apple silicon DMG is [**1.4.0 (build 7)**](https://github.com/akinal5765-byte/Silverphase/releases/tag/macos-v1.4.0). The [1.3.1 (build 6)](https://github.com/akinal5765-byte/Silverphase/releases/tag/macos-v1.3.1) package is still available. The **1.3.0 (build 5)** installer is retained in the [historical release](https://github.com/akinal5765-byte/Silverphase/releases/tag/macos-v1.3.0); its [version record](releases/1.3.0.md) covers pre-film controls, experimental film, shared-engine calibration, and validation scope.

## Lightroom Classic external editing

macOS 1.2.0 (build 4) introduced single-photo JPEG/TIFF external editing. Lightroom Classic creates a copy with adjustments and opens Silverphase’s external-editor view. **Save** (⌘S), in the upper-right corner, writes the full-resolution result back to the copy and closes the window. No `.lrplugin` is needed.

See the [Lightroom Classic walkthrough](../../docs/LIGHTROOM-CLASSIC.md) for setup, screenshots, repeat edits, and tone behavior, or the [1.2.0 notes](releases/1.2.0.md) for source and validation scope.

For development diagnostics, `--lightroom-editor <path>` explicitly enters external-editor mode. The sender of the macOS open event identifies the source application. If it is unavailable, the app does not guess.
