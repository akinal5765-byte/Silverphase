# CineStill 800T adoption — 2026-11-02

Source: Hanze Qiu's SpektraLab commit
`02d82b56cf65f0f8e802a708612edc4e9a4790af` (1.3.5 / build 20).
The exact source blobs and adaptation notes are in
`engine/resources_product/UPSTREAM.json`.

## Product behavior

- Both hosts offer `cinestill_800t` as a still-camera colour negative at ISO 800.
  Catalogue metadata inherits the base's stage, type and declared print target.
- The adopted alias is unchanged. The loader reuses Andrea Volpato's unchanged
  Vision3 500T measured arrays and neutral-print calibration; it does not claim
  independently measured CineStill sensitometry.
- The profile preset selects upstream's four-component back-reflection fit,
  including its wider red halo. Existing strong/weak/none overrides retain
  Silverphase's established Gaussian presets.
- Highlight headroom is 0–8 EV, default 4, applied in scene light before film
  exposure and film-edge composition. It is gated to the back-reflection model,
  active halation and nonzero halation amount. It is an estimate of clipped
  source energy, not recovered sensor data or a change to material arrays.
- Both hosts expose the control and include it in film reset/copy/paste;
  desktop sidecars lacking the field decode to 4 EV. It invalidates the negative.
- The text-only `packaging-prompt-v1.md` template was instantiated with
  CineStill 800T / ISO 800 and generated with built-in imagegen. Complete prompt:
  `modern_UI/design/film-artwork/generated-cinestill-packaging-manifest.json`.
  Artwork: `cinestill_800t-packaging-v1.png`, SHA-256
  `29574d79b210d524fb806500b2e44a7028766c33bb88cb74c8ec6127e610a66c`.
- The original product `NOTICE.md` remains verbatim. The newer upstream notice
  is separately preserved as `CINESTILL_NOTICE.md` and bundled with the source
  provenance and GPL / CC BY-SA attribution in both apps.

## Validation

Xcode 27.1, Apple silicon, macOS Debug and iOS simulator Debug. Public material
mode (`SILVERPHASE_LOCAL_MATERIALS=0`); no private profiles or photos added.
These checks do not establish real-phone touch, Photos permission, memory
entitlement, full-resolution export, or visual acceptance of a real photo.
No performance benchmark was taken.

| Check | Result |
|---|---|
| `engine/build.sh all` | PASS; existing C-linkage warnings in `engine.cpp` |
| macOS application build | PASS |
| iOS simulator application build | PASS |
| Desktop full XCTest suite | 544 tests, 47 skipped, 0 failures |
| `cinestill_checks.py` | 14 checks PASS, 0 failed |
| GPU smoke and safe-math rejection guard | PASS |
| Product B&W, camera filters, paper grades | All three drivers PASS |
| Overscan, overscan striped, strip executor, band purity | All four drivers PASS |
| Both project generator checks; bundle resource gate | PASS |
| Media inventory and unchanged baked-array inventory | PASS |
| Adopted profile/notice hashes; both built app profile, provenance and cover bytes | PASS |
| iOS `--cinestill-regression` on iPhone Duo / iOS 27.1 simulator | PASS |

The 800T native checks include rejection of traversal/missing/nested aliases and
invalid metadata, exact base-emulsion/neutral-print agreement with halation off,
exact whole/127-row striped agreement, the brighter halo rim, red/green halo
reach at two exposures, highlight gating, and preservation of other films'
headroom/override behavior. Whole/strip equality is an internal consistency
check; upstream's fitted halo assumptions are not an independent physical oracle.

The focused iOS report confirms encoded TIFF import, tagged ProPhoto output,
the shared catalogue, ISO 800, decoded packaged cover, default headroom, and
warm/fresh preset agreement. The full `--smoke-test` run passed these 800T checks
and subsequent menu/family checks, then failed with
`当前内存不足以读取原图细节`. Full mobile smoke therefore remains incomplete;
the focused report does not replace that result.

Desktop skips are fixture/opt-in coverage limits, including absent camera RAWs,
the external 1 MP smoke frame and the authorized temporary device-colour RAW.
No historical fixtures were restored or replaced. Initial tests caught the old
33-stock expectations and missing headroom wire whitelist; both were updated,
and the final full suite above passed. Native math/blur paths retain float32,
safe/precise compilation and existing node flushes.

The initial adoption checks above preceded the user's request to commit and
publish. On 2026-11-03, the follow-up sets independent application versions:
macOS 1.0.1 (2), iOS 1.1.1 (3). The iOS material-card short name is now `800T`,
matching macOS; full catalogue/list names remain `CineStill 800T`. Both updated
Debug builds succeeded. The Duo update uses an in-place installation, with no
application launch, phone UI operation or further device acceptance checks.
Public Release packaging and its source/notice/private-material gates are run
separately for each platform before uploading the PR's prerelease artifacts.
