<p align="center">
  <img src="screenshots/app-icon.png" width="112" height="112" alt="Silverphase app icon">
</p>

<h1 align="center">Silverphase</h1>

<p align="center">
  <strong>From film exposure to the finished print.</strong><br>
  Native film and print simulation for macOS, iPhone, and iPad
</p>

<p align="center">
  <a href="README.md">简体中文</a> · English ·
  <a href="#download">Download</a> · <a href="screenshots/current/README.md">Examples</a> ·
  <a href="docs/README.md">Documentation</a> · <a href="#build-from-source">Build from source</a> ·
  <a href="#also-by-the-author-layerlight">Layerlight</a>
</p>

Silverphase simulates **camera input → film exposure → development → printing → scanning** on device. Film and paper shape the result together. Grain, halation, and film edges form within the process. Deliver a finished image or export a Cineon intermediate that preserves film contrast for grading.

## Also by the author: Layerlight

<table>
  <tr>
    <td width="112" align="center"><a href="https://apps.apple.com/app/id6756343255"><img src="screenshots/related-apps/layerlight-icon.png" width="96" height="96" alt="Layerlight app icon"></a></td>
    <td>
      <strong>Layerlight · HDR Photo Editor</strong><br>
      A separate proprietary app by the same author, available on the App Store for iPhone and iPad.
      <p>Shape HDR highlights and Gain Maps with light, contrast, and softness controls. Supports HEIC Photographic Styles workflows, plus crop, frames, watermarks, and batch export. Photographic Styles editing requires compatible devices and systems; some features require Pro.</p>
      <a href="https://apps.apple.com/app/id6756343255"><strong>View and download on the App Store →</strong></a>
    </td>
  </tr>
</table>

Layerlight and its icon retain their separate rights and are outside Silverphase's open-source licences. See the [related-app artwork notice](screenshots/related-apps/README.md) for the icon's provenance.

## Download

| Platform | Version and download | Requirements |
|---|---|---|
| macOS | [1.3.0 (build 5)](https://github.com/akinal5765-byte/Silverphase/releases/tag/macos-v1.3.0) · Apple silicon DMG | macOS 15 or later |
| iPhone and iPad | [App Store](https://apps.apple.com/us/app/silverphase-film-simulator/id6829987567) · [TestFlight beta](https://testflight.apple.com/join/uwY3ZYJp) | iOS or iPadOS 18 or later |

On macOS, check for updates in Settings → Software Update. The GitHub DMG is ad-hoc signed and has no Apple notarization. See the [release guide](docs/BINARY-RELEASES.md) for installation and SHA-256 verification. Silverphase is available on the App Store outside mainland China. The App Store and TestFlight show the versions available through each channel.

## What's new in macOS 1.3.0

- **Pre-film controls.** Adjust local brights and darks, exposure, contrast, lift, gain, midtone detail, color boost, and saturation. Existing photos retain their saved tone settings.
- **Match Camera Preview Brightness.** Supported RAW files can use the camera preview to set their starting exposure. Batch copying can carry the switch while each photo keeps its own fine-tuning.
- **Experimental stocks and print balance.** Adds 29 Fotufilm profiles adapted by Negs. Shared engine updates cover spectral adaptation, DIR, neutral print filtration, and grain softness.
- **Output.** JPEG, PNG, and TIFF exports carry the photo’s XMP star rating. For heavy crops that need a large output, Film → Frame ⋯ → Simulation Size generates grain and halation at the target size.

See the [1.3.0 release notes](modern_UI/Spektrafilm/releases/1.3.0.md) for the full changes and Kodak 5219 validation scope.

## Edit and deliver

1. **Open a photo.** Open a file or folder on macOS. Import from Photos or Files, or use the in-app camera, on iPhone and iPad. RAW compatibility depends on the Apple system decoder.
2. **Choose materials.** The public catalog contains 25 standard film profiles, 9 papers, and 29 experimental films. Print a negative or select a direct scan. Ilford Multigrade IV RC supports grades 00–5. [Full catalog](modern_UI/Spektrafilm/Spektrafilm/Resources/StockCatalog.json) · [Experimental profile provenance and scope](license/DATA-SOURCES.md#experimental-fotufilm-profiles)
3. **Adjust the process.** Control metering, white balance, development, grain, halation, physical frame size, and print filtration. Add film edges and date stamps. macOS also offers soft proofing and two-photo half-frame compositions. [macOS guide](modern_UI/Spektrafilm/README.md)
4. **Export.** Deliver a JPEG, 8-bit PNG, or 16-bit TIFF with your chosen color profile. The Cineon DI package provides a 16-bit log TIFF plus ProPhoto RGB and Rec.709 viewing LUTs for grading. [Export and DI guide](modern_UI/Spektrafilm/README.md#图像与输出边界)

Lightroom Classic can send a single JPEG or TIFF copy to the macOS editor. Save writes the full-resolution result back to the registered copy. Lightroom’s tone rendering is baked into the input. [Illustrated setup and workflow](docs/LIGHTROOM-CLASSIC.md)

### iPhone and iPad

The mobile editor provides a local library, ratings and flags, batch editing and export, and layouts for conventional iPhones, iPhone Duo, and iPad. iOS 1.3.0 (build 10) adds pre-film adjustments, RAW camera preview brightness matching, and star ratings in JPEG, PNG and TIFF exports. [GitHub release notes](https://github.com/akinal5765-byte/Silverphase/releases/tag/v1.3.0) · [Source and validation notes](ios/releases/1.3.0.md). See the [iOS guide](ios/README.md) and [control audit](ios/CONTROL-AUDIT.md) for capture workflows, viewfinder modes, and device limitations.

### Examples

The desktop image below is from the October 2026 examples. The [case gallery](screenshots/current/README.md) includes multiple stocks, 100% grain crops, and halation comparisons. The platform guides describe current control locations.

![Earlier Portra 400 lotus example](screenshots/current/silverphase-lotus-2026-10-31.jpg)

## Build from source

Both hosts use SwiftUI and a shared C++20/Metal engine. Python is used by development scripts. Image processing runs on the device.

```sh
git clone https://github.com/akinal5765-byte/Silverphase.git
cd Silverphase
export DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer

SILVERPHASE_LOCAL_MATERIALS=0 engine/build.sh bundle
SILVERPHASE_LOCAL_MATERIALS=0 xcodebuild \
  -project modern_UI/Spektrafilm/Spektrafilm.xcodeproj \
  -scheme Spektrafilm -configuration Debug -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Silverphase.app
```

See the [iOS guide](ios/README.md) for the project, device signing, and simulator builds. For architecture and verification, see the [documentation index](docs/README.md), [shared engine architecture](ARCHITECTURE.md), and [validation guide](modern_UI/Spektrafilm/VALIDATION.md). Report issues on [GitHub](https://github.com/akinal5765-byte/Silverphase/issues) or see the [contribution guide](CONTRIBUTING.md).

## Sources and licences

Silverphase is an independent derivative of Hanze Qiu’s [SpektraLab](https://github.com/JamesQiu2005/SpektraLab). The physical model and original measured film and paper profiles come from Andrea Volpato’s [spektrafilm](https://github.com/andreavolpato/spektrafilm). [Licences and credits](LICENSES.md) · [Material data sources](license/DATA-SOURCES.md)

### Thanks to Negs

Thank you to Noah Haasis’s [Negs](https://github.com/noahhaasis/negs) and to [yosoyelchris](https://github.com/yosoyelchris), who contributed Prep and camera brightness matching to Negs. Silverphase 1.3.0 draws on Negs in the following areas.

- **Pre-film controls and camera brightness matching** · We drew on Negs’s tone, detail, and color adjustments and its use of the camera preview to fit each RAW file’s starting exposure. [Negs Prep](https://github.com/noahhaasis/negs/blob/479a5674bb9d43af5c08fbd7307b367bec7bf10b/docs/prep.md) · [Negs credits](https://github.com/noahhaasis/negs#credits)
- **Simulation Size and star ratings in exports** · We drew on Negs’s pre-film linear resampling and the practice of writing photo ratings to `xmp:Rating` in finished exports. [Negs Image Size](https://github.com/noahhaasis/negs/blob/479a5674bb9d43af5c08fbd7307b367bec7bf10b/docs/image-size.md) · [Negs library and export features](https://github.com/noahhaasis/negs#a-darkroom-in-a-window)
- **29 experimental film profiles** · We adopted Negs’s conversions of MUAStudio’s [Fotufilm](https://fotufilm.com) profiles and selected development and print parameters. [Profile sources and licensing](license/DATA-SOURCES.md#experimental-fotufilm-profiles) · [Pinned source and file provenance](engine/resources_product/UPSTREAM.json)
- **Shared engine calibration** · We drew on Negs’s implementation of the experimental Spektrafilm model for DIR saturation, Hanatos spectral-window normalization, and the neutral print filter solver. [DIR](https://github.com/noahhaasis/negs/blob/97d63aaebca9654b041211dea9eebd55dd12b878/crates/spektrafilm-model/src/couplers.rs) · [Spectral adaptation](https://github.com/noahhaasis/negs/blob/97d63aaebca9654b041211dea9eebd55dd12b878/crates/spektrafilm-core/src/spectral_service.rs) · [Print balance](https://github.com/noahhaasis/negs/blob/97d63aaebca9654b041211dea9eebd55dd12b878/crates/spektrafilm-core/src/print_balance.rs)
- **Stage-by-stage validation** · Negs’s verification approach informed Silverphase’s own Kodak 5219 checks for negative density, grain, and measured spectral patches. [Negs validation report](https://github.com/noahhaasis/negs/blob/479a5674bb9d43af5c08fbd7307b367bec7bf10b/docs/gpu-vs-cpu-quality.md) · [Silverphase’s 5219 checks](modern_UI/Spektrafilm/VALIDATION.md#5219-底片与光谱色样)
