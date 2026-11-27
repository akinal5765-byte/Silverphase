# Silverphase documentation

[简体中文](README.zh-CN.md) · **English**

Silverphase is an independent derivative of Hanze Qiu’s SpektraLab and Andrea Volpato’s spektrafilm. Current source and platform guides define behavior. The process is **Prep → Film → Development → Color Enlargement (Print) → Scan**. Crop and Film Edge are separate tools.

## Downloads and use

| Need | Where to go |
|---|---|
| Product and basic builds | [English README](../README.en.md) |
| macOS downloads, signing, App Store and TestFlight | [Downloads and distribution](BINARY-RELEASES.md) |
| Latest versions, builds, and verification | [macOS 1.4.0 (build 7)](../modern_UI/Spektrafilm/releases/1.4.0.md#english) · [iOS/iPadOS 1.4.0 (build 12)](../ios/releases/1.4.0.md#english) |
| App Store upload, review, and beta records | [Distribution record](../ios/APP-STORE.md) |
| Upgrade, support, and privacy | [macOS migration](MACOS-IDENTITY-UPGRADE.md) · [Support](SUPPORT.md#english) · [Privacy](PRIVACY.md#english) |
| Lightroom Classic external editing | [Illustrated guide](LIGHTROOM-CLASSIC.en.md) |
| Real-photo interface captures and examples | [iPhone/iPad captures](../screenshots/ios/2026-11-27/README.md) · [Film and paper showcase](showcase/README.md) |
| Mobile workflows, build, and device limitations | [iOS guide](../ios/README.md) · [Mobile design](../ios/DESIGN.en.md) · [Control audit](../ios/CONTROL-AUDIT.en.md) |

## Engineering and verification

| Need | Where to go |
|---|---|
| Shared native engine and host responsibilities | [Architecture](../ARCHITECTURE.md) |
| ABI, JSON, ownership, Cineon, and film edges | [API reference](../API-SPEC-callable-render-service.md) |
| Host and engine contract | [Contract](../CONTRACT-frontend-backend.md) |
| Desktop engineering, layout, 5219, and verification scope | [macOS guide](../modern_UI/Spektrafilm/README.en.md) · [UI specification source](../modern_UI/design/UI-SPEC.md) · [Validation](../modern_UI/Spektrafilm/VALIDATION.en.md) |
| Material sources, experimental stocks, and private overlay | [Data sources](../license/DATA-SOURCES.md) · [Local materials](LOCAL-MATERIALS.md) · [Bundled notices](../modern_UI/Spektrafilm/Spektrafilm/Resources/Licenses/README.txt) |
| Artwork and model references | [Artwork scope](../license/ARTWORK.md) · [Media inventory](../license/media-inventory.json) · [Data inventory](../license/data-inventory.json) · [B&W](../engine/tools/profile_sources/blackwhite.md) · [Film edges](../engine/tools/profile_sources/film_edge.md) · [App icon](../design/app-icon/README.md) |
| Contribution, writing, and repository maintenance | [Contributing](../CONTRIBUTING.md) · [Writing guide](WRITING-GUIDE.md#english) · [Maintenance](PROJECT-MAINTENANCE.md#english) · [Working rules](../AGENTS.md) |
| Licensing and public release checks | [Licence map](../LICENSES.md) · [Release review](OPEN-SOURCE-RELEASE.md) |

## Historical material

| Need | Where to go |
|---|---|
| Earlier releases and installable builds | [GitHub Releases](https://github.com/akinal5765-byte/Silverphase/releases) · [macOS source notes](../modern_UI/Spektrafilm/releases/) · [iOS source notes](../ios/releases/) |
| Validation, performance and older interface captures | [CineStill 800T](../performance/VALIDATION-CINESTILL-2026-11-02.md) · [Photo case validation](../performance/VALIDATION-CASES-2026-10-31.md) · [Local and public builds](../performance/VALIDATION-LOCAL-MATERIALS-2026-10-31.md) · [Capture archives](../screenshots/README.md) |
| Early designs, RFCs, and measurements | [Historical snapshots](history/) · [RFCs](../rfc/) · [Measurements](../performance/) |

Historical originals, RFCs, licence texts, and upstream notices keep their original language. Dated evidence does not certify current behavior. Do not restore the retired Python runtime, baseline, or old two-rail UI to match an archive; private photo inputs stay outside Git. See the [documentation guide](WRITING-GUIDE.md#english) for translation scope and evidence.
