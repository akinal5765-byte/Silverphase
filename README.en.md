<p align="center">
  <img src="screenshots/app-icon.png" width="128" height="128" alt="Silverphase app icon">
</p>

<h1 align="center">Silverphase</h1>

<p align="center">
  <strong>From film exposure to a photographic print.</strong><br>
  A native film-process simulator for macOS, iPhone, and iPad
</p>

<p align="center">
  <a href="README.md">简体中文</a> · <a href="README.en.md">English</a> ·
  <a href="#installation-and-builds">Build</a> · <a href="screenshots/current/README.md">Gallery</a> ·
  <a href="docs/README.md">Documentation</a> · <a href="CONTRIBUTING.md">Contribute</a> · <a href="#also-by-the-author-layerlight">Layerlight</a>
</p>

![Silverphase macOS editor with the Portra 400 lotus case](screenshots/current/silverphase-lotus-2026-10-31.jpg)

Silverphase takes a photograph through **camera input → film → development → print → scan**. Choose film and paper, then shape the image through exposure, development contrast, filtration, and physical frame size. Grain, halation, and film edges form within the same imaging pipeline. Deliver a finished photograph or export an intermediate that preserves film contrast for further grading.

The app uses SwiftUI and a shared C++20/Metal engine, processing photographs on device without a runtime Python service or virtual environment. Silverphase is an independent derivative of Hanze Qiu's [SpektraLab](https://github.com/JamesQiu2005/SpektraLab). The physical model and original measured film/paper profiles originate in Andrea Volpato's [spektrafilm](https://github.com/andreavolpato/spektrafilm).

## What you can do

- **Choose film and paper.** The public catalog includes 24 film profiles, including push variants, and 9 papers: color negative, reversal, motion-picture negative, and B&W materials.
- **Control exposure and development.** Metering, film exposure, RAW white balance, development contrast, color separation, and scene-latitude placement determine how the scene fits the film response.
- **Shape grain and halation.** Physical frame size sets the scale of grain and spatial effects. Grain amount, size, softness, film halation, and emulsion scatter have separate controls.
- **Make color or B&W prints.** Adjust paper, print exposure, yellow/magenta filtration, preflash, and print glare. Ilford Multigrade IV RC provides grades 00–5 with exposure compensation; eight Wratten lens filters are available.
- **Add film edges and dates.** Use 135, half-frame, multiple 120 and panoramic gates, perforations, markings, fog, and light leaks. Date-back placement and styling follow the chosen format.
- **Inspect and deliver.** Crop, rotate, inspect histograms, compare previews, and use batch export and export recipes. Desktop also provides soft proofing and two-photo half-frame compositions.

### Film and paper

| Material family | Representative profiles |
|---|---|
| Color negative | Portra 160/400/800, Gold 200, Ektar 100, Ultramax 400, Fujifilm C200, Pro 400H, X-Tra 400 |
| Reversal | Ektachrome 100, Kodachrome 64, Provia 100F, Velvia 100 |
| Motion-picture negative | Vision3 50D, 200T, 250D, 500T |
| B&W negative | Tri-X 400, HP5 Plus 400, T-Max 100, Acros II |
| Color paper and motion-picture print | Endura family, Ektacolor Edge, Crystal Archive Type II, Vision 2383, Vision Premier 2393 |
| B&W paper | Ilford Multigrade IV RC |

See the [complete catalog](modern_UI/Spektrafilm/Spektrafilm/Resources/StockCatalog.json). B&W profiles retain SpektraLab's independently constructed models and fits; chemistry, grain, and fitting limitations are documented in the [B&W notes](engine/tools/profile_sources/blackwhite.md).

### Interface and detail

<table>
  <tr>
    <td width="50%"><img src="screenshots/current/silverphase-bird-acros-2026-10-31.jpg" alt="Acros II B&W bird case"></td>
    <td width="50%"><img src="screenshots/current/silverphase-records-gold-2026-10-31.jpg" alt="Gold 200 record-display case"></td>
  </tr>
  <tr><td align="center">Acros II · B&W print</td><td align="center">Gold 200 · Record display</td></tr>
</table>

<details>
<summary>Expand: grain at 100% and halation on/off</summary>

**Grain detail:** Acros II, 135 format, app zoom at 100%, grain amount, size, and softness all at 1×.

![Acros II grain at 100% app zoom](screenshots/current/silverphase-grain-100pct-2026-10-31.jpg)

**Halation comparison:** Vision3 500T, identical exposure and viewport, changing only halation. The enabled image uses high/4×, with emulsion scatter at 0× and grain off.

| Halation on | Halation off |
|---|---|
| ![Halation on](screenshots/current/silverphase-halation-on-100pct-2026-10-31.jpg) | ![Halation off](screenshots/current/silverphase-halation-off-100pct-2026-10-31.jpg) |

Open the original images to inspect detail. Page scaling and JPEG compression affect fine texture; these captures illustrate the appearance rather than provide lossless measurements.

</details>

All captures show actual macOS windows on 2026-10-31. Settings, sources, and permitted use are recorded in the [full gallery](screenshots/current/README.md).

## Platforms and current status

| Platform | Requirements | Current scope |
|---|---|---|
| macOS | Apple silicon, macOS 15+ | Native editor, shared imaging engine, batch export, soft proofing, two-photo half-frame compositions |
| iPhone Duo | iOS 18+ | Larger editing workspace; one of the currently recommended mobile devices |
| Conventional iPhone | iOS 18+ | Runs the mobile editor, but dense process controls feel cramped and need further small-screen usability work |
| iPad | iPadOS 18+ | The same mobile editor with adapted canvas, inspector, and material-browser layouts |

**iPhone Duo and iPad are currently recommended for mobile editing.** On conventional iPhones, the main limitation is fitting the complex interface and interactions onto a smaller screen. OS compatibility does not imply equally comfortable use on every device.

Current builds are distributed through [GitHub Releases](https://github.com/akinal5765-byte/Silverphase/releases): the macOS DMG has no Developer ID signature or notarization, and the iOS IPA requires user-arranged signing and installation. See [binary releases](docs/BINARY-RELEASES.md) for downloads, checksums and installation. Source builds remain available. iOS does not include desktop two-photo pairing or every proofing feature; see the [iOS guide](ios/README.md) and [control audit](ios/CONTROL-AUDIT.md).

iOS currently uses editing sessions: a cold start clears app-owned imported copies, while settings and export recipes persist independently. Keep original photographs and exported images for long-term storage; consult the platform guides for workflow details.

## Also by the author: Layerlight

<table>
  <tr>
    <td width="112" align="center"><a href="https://apps.apple.com/cn/app/layerlight-hdr-photo-editor/id6756343255"><img src="screenshots/related-apps/layerlight-icon.png" width="96" height="96" alt="Layerlight app icon"></a></td>
    <td>
      <strong>Layerlight · HDR Photo Editor</strong><br>
      A separate proprietary app by the same author, available on the App Store for iPhone and iPad.
      <p>Shape HDR highlights and Gain Maps with light, contrast, and softness controls. Supports HEIC Photographic Styles workflows, plus crop, frames, watermarks, and batch export. Photographic Styles editing requires compatible devices and systems; some features require Pro.</p>
      <a href="https://apps.apple.com/cn/app/layerlight-hdr-photo-editor/id6756343255"><strong>View and download on the App Store →</strong></a>
    </td>
  </tr>
</table>

Layerlight and its icon retain their separate rights and are outside Silverphase's open-source licences. See the [related-app artwork notice](screenshots/related-apps/README.md) for the icon's provenance.

## Installation and builds

For a prebuilt version, download the platform assets from [Releases](https://github.com/akinal5765-byte/Silverphase/releases) and follow the [installation guide](docs/BINARY-RELEASES.md). Source-build instructions follow.

### macOS

You need an Apple-silicon Mac, Xcode with its Metal toolchain, and `python3` for development scripts. Current validation uses Xcode 27.1. The Xcode projects are committed; no Python runtime environment setup or project regeneration is needed.

```bash
git clone https://github.com/akinal5765-byte/Silverphase.git
cd Silverphase

# Adjust to your Xcode installation; no global xcode-select change is needed.
export DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer

engine/build.sh bundle
xcodebuild -project modern_UI/Spektrafilm/Spektrafilm.xcodeproj \
  -scheme Spektrafilm -configuration Debug \
  -derivedDataPath build/DerivedData build

open build/DerivedData/Build/Products/Debug/Silverphase.app
```

`Spektrafilm` in paths and targets is a retained internal engineering name; the displayed app name is **Silverphase**. Re-run `engine/build.sh bundle` after changing engine resources or Metal shaders. Default local builds use development signing.

### iPhone and iPad

Open `ios/Silverphase/Silverphase.xcodeproj` in Xcode. Select the `Silverphase` scheme and a device, configure your development team under Signing & Capabilities, then build and run. Device provisioning must include the Increased Memory Limit capability requested by the project. Simulator builds do not need development signing:

```bash
xcodebuild -project ios/Silverphase/Silverphase.xcodeproj \
  -scheme Silverphase -configuration Debug -sdk iphonesimulator \
  -derivedDataPath /tmp/silverphase-ios-derived CODE_SIGNING_ALLOWED=NO build
```

See the [iOS build guide](ios/README.md) for device signing, caches, and diagnostics.

A public checkout contains only the supported materials. Maintainer builds can additionally load private experimental materials; set `SILVERPHASE_LOCAL_MATERIALS=0` when packaging for distribution. See [local materials and public builds](docs/LOCAL-MATERIALS.md).

## First edit

1. **Import a photograph.** Open an image or folder on desktop, or import from Photos/Files on mobile. RAW, JPEG, HEIC/HEIF, PNG, and TIFF are supported; RAW compatibility depends on the system's Apple RAW decoder.
2. **Choose film and paper.** Select a film in the material browser, then a printing paper. Reversal film or “No Print Profile” provides a direct-scan result.
3. **Work in process order.** Set input exposure and white balance, then development, grain, halation, and print. Preview crop and film edges together.
4. **Choose a delivery path.** Export a ready-to-use image or a film intermediate for further color work.

### Export paths

| Path | Output | Intended use |
|---|---|---|
| Finished Film Render | JPEG, 8-bit PNG, or 16-bit TIFF, tagged for the recipe's destination color space | Complete the film/paper process and view, share, or deliver the image |
| Gradeable Film Intermediate / DI package | 16-bit Cineon-log TIFF with accompanying DI-view LUTs | Preserve film contrast and continue grading |

<details>
<summary>DI color semantics</summary>

The master is an **untagged 16-bit Cineon-log TIFF with ProPhoto RGB primaries**, bypassing paper rendering and output grading. Its second page is a view preview. Two `.cube` viewing LUTs, to ProPhoto RGB and Rec.709, are shared within each export directory.

Interpret the master through the supplied view rather than assigning a display ICC profile directly to the log data. These are DI viewing transforms, not the selected paper's print LUT. Exporting a DI through ordinary JPEG/TIFF writes its display view with the destination profile. See the [desktop engineering guide](modern_UI/Spektrafilm/README.md) for the file contract.

</details>

## Documentation and development

| Topic | Entry point |
|---|---|
| All guides and current specifications | [Documentation index](docs/README.md) |
| macOS structure, builds, and export | [Desktop engineering](modern_UI/Spektrafilm/README.md) |
| iOS behavior, builds, and platform differences | [iOS guide](ios/README.md) · [Control audit](ios/CONTROL-AUDIT.md) |
| Shared engine and native boundary | [Architecture](ARCHITECTURE.md) · [API](API-SPEC-callable-render-service.md) · [Contract](CONTRACT-frontend-backend.md) |
| Tests, fixed photographs, and skips | [Validation guide](modern_UI/Spektrafilm/VALIDATION.md) · [Release review](docs/OPEN-SOURCE-RELEASE.md) |
| Bug reports and contributions | [Issues](https://github.com/akinal5765-byte/Silverphase/issues) · [Contributing](CONTRIBUTING.md) |

Run the desktop suite with:

```bash
xcodebuild -project modern_UI/Spektrafilm/Spektrafilm.xcodeproj \
  -scheme SpektrafilmTests -configuration Debug \
  -derivedDataPath build/DerivedData test
```

Current acceptance uses native-engine checks and app workflows. Real photographs are validated through external manifests and stay outside Git. Missing historical fixtures cause explicit skips; report passed, failed, and skipped cases together. Historical Python reference scripts remain as research records, and their runtime does not need to be recreated for current builds or acceptance.

## Origins and licensing

Thank you to **Hanze Qiu** for SpektraLab's native macOS application and C++/Metal port, and **Andrea Volpato** for spektrafilm's physical model and original measured profiles. Silverphase preserves upstream Git history, attribution, and licences while developing independently; the upstream projects are not affiliated with or endorsing Silverphase.

- Application, engine, and development tools: **GPL-3.0-or-later**.
- Film/paper profiles, derived LUTs, and associated fitted packs: upstream **CC BY-SA 4.0** terms.
- Apple metal-cpp: **Apache-2.0**; Colour data retains **BSD-3-Clause** notices.
- Silverphase-controlled cover and icon artwork: see the [artwork notice](license/ARTWORK.md) for scope and third-party packaging exclusions. Case photographs and the Layerlight icon have separate terms and are outside that grant.

See [LICENSES.md](LICENSES.md), the [bundled notices](modern_UI/Spektrafilm/Spektrafilm/Resources/Licenses/), and the [data-source record](license/DATA-SOURCES.md) for full terms, provenance, and distribution requirements.
