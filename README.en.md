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
  <a href="docs/README.md">Documentation</a> · <a href="#build-from-source">Build from source</a>
</p>

Silverphase simulates **camera input → film exposure → development → printing → scanning** on device. Film and paper shape the result together. Grain, halation, and film edges form within the process. Deliver a finished image or export a Cineon intermediate that preserves film contrast for grading.

## Download

| Platform | Version and download | Requirements |
|---|---|---|
| macOS | [1.3.0 (build 5)](https://github.com/akinal5765-byte/Silverphase/releases/tag/macos-v1.3.0) · Apple silicon DMG | macOS 15 or later |
| iPhone and iPad | [TestFlight](https://testflight.apple.com/join/uwY3ZYJp) · [iOS 1.2.5 notes](https://github.com/akinal5765-byte/Silverphase/releases/tag/v1.2.5) | iOS or iPadOS 18 or later |

On macOS, check for updates in Settings → Software Update. The GitHub DMG is ad-hoc signed and has no Apple notarization. See the [release guide](docs/BINARY-RELEASES.md) for installation and SHA-256 verification. The platforms have independent versions. TestFlight shows the available mobile build.

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

The mobile editor provides a local library, ratings and flags, batch editing and export, and layouts for conventional iPhones, iPhone Duo, and iPad. Version 1.2.5 adds capture EV, RAW preference and resolution choices, and an interactive print walkthrough. See the [iOS guide](ios/README.md) and [control audit](ios/CONTROL-AUDIT.md) for capture workflows, viewfinder modes, and device limitations.

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

Silverphase is an independent derivative of Hanze Qiu’s [SpektraLab](https://github.com/JamesQiu2005/SpektraLab). The physical model and original measured film and paper profiles come from Andrea Volpato’s [spektrafilm](https://github.com/andreavolpato/spektrafilm). Thanks to Noah Haasis’s Negs and MUAStudio’s Fotufilm for the experimental collection. [Licences and credits](LICENSES.md) · [Material data sources](license/DATA-SOURCES.md)

## Layerlight

The same developer also makes an independent iPhone and iPad HDR photo editor with HDR highlight controls, Gain Maps, and HEIC Photographic Styles on supported devices. [View Layerlight on the App Store](https://apps.apple.com/app/id6756343255)
