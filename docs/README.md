# Silverphase documentation

Current index, reviewed 2026-11-27. Silverphase is an independent derivative of
Hanze Qiu's SpektraLab and Andrea Volpato's spektrafilm. Current source and the
platform guides govern shipped behavior; RFCs and dated reports retain their
original scope. Documentation review is not a new performance or visual audit.

The editor’s main stages are **Prep → Film → Development → Color Enlargement
(Print) → Scan**. Crop and Film Edge are separate tools. See the platform guides
for label and control differences.

| Need | Current entry |
|---|---|
| Product, origins, licensing, basic builds | [中文](../README.md) / [English](../README.en.md) |
| Whole-product implementation | [ARCHITECTURE.md](../ARCHITECTURE.md) |
| Working rules and debugging traps | [AGENTS.md](../AGENTS.md) |
| ABI, JSON, ownership, tiers, Cineon, film edge | [API reference](../API-SPEC-callable-render-service.md) |
| Host/engine invariants and shared-platform changes | [Contract](../CONTRACT-frontend-backend.md) |
| App Store, TestFlight and macOS downloads | [Binary releases](BINARY-RELEASES.md) |
| macOS 1.4.0 release notes, output behavior and migration | [Build 7 notes](../modern_UI/Spektrafilm/releases/1.4.0.md) / [macOS upgrade guide](MACOS-IDENTITY-UPGRADE.md) |
| iOS and iPadOS 1.4.0 changes and validation | [Build 12 notes](../ios/releases/1.4.0.md) / [Distribution record](../ios/APP-STORE.md#140-12--2026-11-27) |
| Previous 1.3.1 Mac installer and iOS source release | [macOS DMG](https://github.com/akinal5765-byte/Silverphase/releases/tag/macos-v1.3.1) / [iOS source release](https://github.com/akinal5765-byte/Silverphase/releases/tag/v1.3.1) |
| 1.3.1 source notes and verification | [macOS build 6](../modern_UI/Spektrafilm/releases/1.3.1.md) / [iOS and iPadOS build 11](../ios/releases/1.3.1.md) |
| macOS 1.3.0 installer, changes and validation | [GitHub Release](https://github.com/akinal5765-byte/Silverphase/releases/tag/macos-v1.3.0) / [1.3.0 notes](../modern_UI/Spektrafilm/releases/1.3.0.md) |
| iOS 1.3.0 historical release | [GitHub Release](https://github.com/akinal5765-byte/Silverphase/releases/tag/v1.3.0) / [Source notes](../ios/releases/1.3.0.md) |
| App Store distribution, privacy and user support | [Store record](../ios/APP-STORE.md) / [Privacy policy](PRIVACY.md) / [Support](SUPPORT.md) |
| CineStill 800T adoption and validation scope | [Dated adoption checks](../performance/VALIDATION-CINESTILL-2026-11-02.md) |
| Desktop structure/build/export | [macOS engineering](../modern_UI/Spektrafilm/README.md) |
| Lightroom Classic external editing, setup and tone boundaries | [Illustrated workflow](LIGHTROOM-CLASSIC.md) / [macOS 1.2.0](../modern_UI/Spektrafilm/releases/1.2.0.md) |
| Desktop layout | [UI-SPEC](../modern_UI/design/UI-SPEC.md) |
| Desktop acceptance, 5219 reference and private photo fixtures | [VALIDATION](../modern_UI/Spektrafilm/VALIDATION.md) |
| Mobile build, photo viewer, in-app camera, RAW import, export and diagnostics | [iOS engineering](../ios/README.md) |
| iOS lock-screen camera activation limitation (unresolved) | [iOS engineering](../ios/README.md) / [CONTROL-AUDIT](../ios/CONTROL-AUDIT.md) |
| iPhone and iPad screens with real photographs | [1.4.0 simulator captures](../screenshots/ios/2026-11-27/README.md) |
| Mobile layout and controls | [DESIGN](../ios/DESIGN.md) / [CONTROL-AUDIT](../ios/CONTROL-AUDIT.md) |
| Public experimental Fotufilm profiles and the private local overlay | [Data sources](../license/DATA-SOURCES.md#experimental-fotufilm-profiles) / [DIR edge audit](../modern_UI/Spektrafilm/VALIDATION.md#fotufilm-dir-边缘增强复查) / [Local material overlay](LOCAL-MATERIALS.md) |
| B&W profile origin and limitations | [B&W notes](../engine/tools/profile_sources/blackwhite.md) / [provenance](../engine/resources_product/UPSTREAM.json) |
| Film edge/date-back model | [Film-edge notes](../engine/tools/profile_sources/film_edge.md) |
| Production icon and design iterations | [Icon guide](../design/app-icon/README.md) |
| Open-source preparation and contribution terms | [Licensing map](../LICENSES.md) / [Contributing](../CONTRIBUTING.md) / [Release review](OPEN-SOURCE-RELEASE.md) |
| Asset provenance and runtime data | [Artwork scope](../license/ARTWORK.md) / [Visual inventory](../license/media-inventory.json) / [Data sources](../license/DATA-SOURCES.md) / [Stored array inventory](../license/data-inventory.json) |
| Image/data/software licenses | [Bundled notices](../modern_UI/Spektrafilm/Spektrafilm/Resources/Licenses/README.txt) |
| Product images and how they were rendered | [Current product showcase](showcase/README.md) |
| Dated desktop UI captures and fixed photo validation | [2026-10-31 captures](../screenshots/current/README.md) / [Case validation](../performance/VALIDATION-CASES-2026-10-31.md) |
| Earlier release verification | [2026-10-31 release review](OPEN-SOURCE-RELEASE.md) / [local and public builds](../performance/VALIDATION-LOCAL-MATERIALS-2026-10-31.md) |
| Earlier implementation and measurements | [Historical snapshots](history/) / [RFCs](../rfc/) / [dated reports](../performance/) |

The root architecture/API/contract were refreshed for the two-host native product.
Their preceding versions are preserved verbatim after a historical-scope banner
in `docs/history/`. Older section references can be resolved there. AGENTS retains
numbered debugging traps with an explicit historical/current distinction.

Do not recreate a retired Python environment, deleted baseline or old two-rail UI
just because a historical document describes one. Current acceptance uses native
checks plus host workflows; private real-photo fixtures stay outside the repo.
