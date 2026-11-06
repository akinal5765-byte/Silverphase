# Silverphase iOS editor

The editor supports a persistent local library, an in-app camera that develops captures with the selected film, native process navigation, and batch editing and export.

Native iOS editor based on **the current desktop product**, with its full-width
canvas and floating process panel. Ordinary iPhones open film/paper lists inside
that panel; Duo and iPad retain the bottom material browser. The [dated ordinary-iPhone captures](../screenshots/ios/2026-11-02/README.md) show the 2026-11-02 phone layout, before the 1.1.2 material-entry changes; historical upstream screenshots and the FTP PoC UI are not its specification.
The desktop implementation in `EditorWindow.swift` and `RightPanel.swift` is the
reference for hierarchy. FTP is not required by this application.

This is the first working editor integration, **not completed desktop feature
parity**. It uses the current repository's C++/Metal engine, product profiles,
licences, catalogue and JSON scalar type. The earlier iOS PoC's build approach
and simulator texture compatibility fix have been brought forward; its older
engine and receiver have not been copied into this product.

## Device usability

Conventional iPhones run in portrait only, with vertically scrolling film/paper
lists, a compact seven-item process bar and a floating,
height-limited inspector over the canvas. The top bar contains Back, Export and
Menu; undo/redo are in the menu. Status sits immediately below the toolbar,
independent of image zoom and comparison. See the [current phone screenshots](../screenshots/ios/2026-11-02/README.md).

Duo retains side navigation when folded or landscape and uses floating tools
when unfolded in portrait. iPad retains top navigation and a right inspector.
Simulator layout coverage does not establish equal real-device touch, memory or
export performance. The deployment floor remains iOS18.

### Known limitation: Camera Control before authentication

On iPhone 17 Pro and iPhone Duo, pressing the physical Camera Control before
device authentication can open the lock-screen capture extension with a live
viewfinder while the shutter is unavailable, or the viewfinder can briefly
freeze. On Duo, device logs show the system Camera app's lock-screen prewarm
taking camera access from the extension. The cause of the 17 Pro shutter issue
has yet to be confirmed from device logs. Pressing Camera Control after
authentication worked on both devices during testing. The on-screen Silverphase
control requests authentication and opens the camera in the main app.

## Installation and downloads

Install the beta on iPhone or iPad through [TestFlight](https://testflight.apple.com/join/uwY3ZYJp).
App Store preparation and remaining distribution requirements are tracked in
[APP-STORE.md](APP-STORE.md).

Historical unsigned device IPA builds are available through [GitHub Releases](https://github.com/akinal5765-byte/Silverphase/releases). Users handle signing, provisioning and installation; the Increased Memory Limit entitlement needs appropriate support. The public IPA excludes personal profiles and local experiments. See [binary releases](../docs/BINARY-RELEASES.md).

## Build

Use Xcode 27.1 with its Metal Toolchain installed. Set `DEVELOPER_DIR` for the
command when the machine's selected developer directory points at Command Line
Tools; changing the global Xcode selection is unnecessary.

```sh
python3 ios/Silverphase/Tools/gen-project.py
DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer \
  xcodebuild -project ios/Silverphase/Silverphase.xcodeproj \
  -scheme Silverphase -configuration Debug -sdk iphonesimulator \
  -derivedDataPath /tmp/silverphase-ios-derived CODE_SIGNING_ALLOWED=NO build
```

For device compilation, use `-sdk iphoneos`. To run on a phone, select a development
team and signing identity in Xcode. The new bundle ID `com.silverphase.editor`
does not replace the earlier FTP demo. No device provisioning or installation
is performed by the build script.

When signing a device build produced with `CODE_SIGNING_ALLOWED=NO`, sign embedded
Mach-O libraries (including `Silverphase.debug.dylib` and `__preview.dylib`) before
signing the app bundle with its provisioning profile and entitlements. Verify the
whole bundle with `codesign --verify --deep --strict` before installing. Signing
only the outer app can install successfully yet terminate at launch with a DYLD
“missing code signature” error. Confirm both launch and a surviving device process;
an installation success alone does not verify startup.

The build phase compiles all current engine translation units, separately
compiles engine kernels with safe/precise float32 math, and bundles current
constants, base/product profiles, catalogue, packaging artwork and licences.
Its cache includes source/header hashes, SDK/compiler identity and build-script
content. iOS uses `AppResources/`: a root `Resources/` directory causes Foundation
to misidentify this as an old-style macOS bundle and lose its bundle identifier.

The desktop catalogue and JSON scalar types are referenced as source files,
not copied. Regenerate the desktop project after shared source extraction:

```sh
python3 modern_UI/Spektrafilm/Tools/gen-project.py
python3 ios/Silverphase/Tools/gen-project.py --check
```

## Current behavior

The portrait iPhone editor, including unfolded Duo, uses a floating height-limited inspector over a stable canvas and a compact seven-item process bar with a native toolbar segmented control for glass selection and tracking. Folded Duo and Duo landscape place a vertical seven-item segmented control inside the system side toolbar instead of relying on tab-bar overflow; the system hinge state distinguishes folded from unfolded portrait. Export/menu actions and hold-to-compare, glass panels and shared tick rulers remain available. iPad shares the native segmented process picker as a horizontal icon-only control in the same native top toolbar row as back/export/menu actions, with its right inspector and bottom browser. Its canvas extends behind transparent chrome while controls respect the safe area. The layout and components are specified in [DESIGN.md](DESIGN.md).

Crop now compiles the desktop `Geometry.swift` directly: free/aspect-locked framing, eight touch handles, moving/redrawing, ±45° straighten, orientation, quarter turns and flips. Preview and export use the same inverse pixel mapping. The frame stays level while straightening; framed-film input can be edited on the original before the film gate is applied. Full desktop parity still excludes half-frame pairing.

System Photos/file import, per-photo edits, undo/redo, EXIF, RAW white balance, scene latitude, film/development/print/scanner controls, film edges and date backs are connected. Imported originals, per-photo recipes, crop geometry, ratings and flags persist in the app-owned local library across cold starts. The library is the launch screen; tapping a photo opens the editor without a filmstrip, while multi-photo editing shows only the chosen batch. Settings and export recipes persist independently. The system Photos picker accepts RAW, JPEG, HEIC/HEIF, PNG and TIFF after validating their contents. It preserves the offered file and colour profile, shows the saved original format in the library, and prefers RAW. With Photos read access it checks the selected asset’s original and alternate resources for RAW. With limited or denied access it can still import the picker representation, and rejects a non-RAW file when the picker identifies the selection as RAW. RAW-only white balance and lens correction controls remain hidden for rendered photos.

Preview quality is automatic: screen-sized fit, coalesced live adjustment, and progressive viewport detail up to native pixels. Double-tap or the menu switches fit/1:1. Settings retains low-power priority, crop effect rescaling, DI blue compensation and cache release; no fixed preview resolution picker. Output resolution is independent of preview. Export provides batch scopes, recipes, naming, JPEG/PNG/16-bit TIFF/Cineon DI, output spaces, metadata/location policies, TIFF previews, file-folder collision policies and add-only Photos saving. Per-process memory guards still apply.

The desktop scalar defaults are captured in `DesktopControlDefaults.json` and checked by the desktop contract test. `Tools/merge-neutral-filters.swift` preserves the full base calibration database while merging product additions. The canvas/output conversion reuses the desktop output shader; the engine remains scene-linear ProPhoto float32.

See [CONTROL-AUDIT.md](CONTROL-AUDIT.md) for every process control, default/range, feature gate, known missing desktop feature and colour measurement scope. Full desktop feature parity is not claimed.

## Validation

Explicit Debug flags run diagnostics inside this app without a phone automation service:

- `--flat-import-regression`: synthetic Photos-provider JPEG (sRGB/P3/Adobe RGB), HEIC and PNG import, names, linear grey, EXIF rotation, first editor preview and JPEG export dimensions/ICC; rejects invalid files and RAW-to-JPEG substitution, and writes `Documents/flat-import-report.json`. The report separately records `exportsValidated`; a simulator with insufficient reported process memory runs input checks but explicitly leaves export unverified. Add `--flat-import-large` for native 4032×3024 JPEG/HEIC render and JPEG export. Test images, imported copies and export directories are removed automatically. After copying the report to the host, launch `--clear-flat-import-regression` to delete the device report.
- `--smoke-test`: synthetic GPU, defaults, calibration, negative reuse, layout constraints, film gates, undo/reset, export decode/ICC/depth, TIFF previews and DI/LUT packaging; writes `Documents/smoke-report.json`.
- `--cinestill-regression`: focused synthetic CineStill 800T checks for shared catalogue, ISO 800, packaged cover, default highlight headroom and warm/fresh halation-preset agreement; writes `Documents/cinestill-report.json`. This does not claim full smoke, full-resolution export or phone acceptance.
- `--device-audit --audit-color`: authorised temporary `Documents/DeviceAuditInput.ARW`; working-pixel samples and resolved parameters for desktop comparison.
- `--device-audit --audit-mp=24`: cold/edit/stress timing and sampled memory/thermal state.
- `--device-audit --audit-jpeg`: priority JPG checks across P3/sRGB/Adobe RGB, actual 24/12/6MP, crop/long-edge, metadata and file decode; writes `Documents/device-jpeg-audit.json`.
- `--device-audit --audit-mp=24 --audit-export`: actual JPEG/TIFF/DI file sizes, dimensions, colour/depth and memory. Checks achieved pixel count, not only the requested option.
- `--device-audit --clear-device-audit`: deletes only that private diagnostic RAW. Diagnostic launches suppress idle locking; normal relaunch restores normal behaviour.

No simulator visual or phone automation service is required. Numerical, file and layout checks do not establish touch ergonomics or visual perfection. Desktop engine reference/parity policy remains unchanged; no material model or C++ pipeline change is part of this UI/settings/export work.

## Device memory capability

`Silverphase.entitlements` requests Apple's production Increased Memory Limit capability (not the debug-only entitlement). The generated project enables the matching capability. Use Xcode automatic signing with provisioning updates so the App ID/profile actually authorizes it; the manual signing helper refuses a stale profile that drops it. Device launches measured approximately3.52GB available before and6.42GB after, on the same12.13GB physical-memory Duo. These are current per-app budgets, not a promise that all physical RAM belongs to this process.

JPG exports explicitly request256-row bands from the engine's existing striped executor (its0 default still runs whole-plane) and use a256px comparison placeholder; they do not decode/render a second full-resolution before image. Their engine source, negative and pool are released before copying the owned output texture into a host image. Preview rendering/defaults remain unchanged. The smoke harness compares striped/whole-frame pixels both with and without grain.

Verified on Duo: native6336×9504 (60.2MP) RAW → JPG,33.0MB, about6.73s with thermal state normal; memory use depends on recipe/source and current system conditions. The device-only pool policy retires completed zero-reference reusable buffers≥64MB when at least4×the requested size, so small bands do not pin whole-plane allocations. Eight-MP real-RAW striped/whole comparisons passed bit-for-bit with grain on/off, including ownership and reuse-ratio checks. These results supersede the original conservative24MP-only configuration.

Manual-crash follow-up: the final visible-editor check used the actual failing68.2MB RAW with the user's3840px preview, sRGB, JPEG80 and batch scope. Three native6336×9504 files completed in about15.52s and the real activity sheet was presented. Whole-run25ms sampled peak including share presentation and preview recovery was4.63GB. Temporary RAW decoder objects now drain before film rendering; dead log-exposure/pre-shift grain planes are released at last use; each Metal colour conversion has its own autorelease pool. Normal exports keep bounded app-private last-export.json breadcrumbs (no pixels) including phase, options, destination and peak. No diagnostic Photos write or external share was executed.

Import and export now share a modal progress surface with real file counts/stages. It locks touch gestures, native navigation and model mutations only for long operations; ordinary adjustment previews remain interactive. Import stays locked across Photos-provider reads, file copying and the first usable preview; failures/empty results unlock and foregrounding resumes unfinished preview preparation. Export advances through render/colour/write and add-only Photos completion. Tests cover these transitions and reject repeated imports while a task owns the operation.

## Repository integration

The current global map is [ARCHITECTURE.md](../ARCHITECTURE.md); the
[documentation index](../docs/README.md) distinguishes active guides from
historical service/reference documents. Desktop half-frame pair documents remain
a desktop feature. Current import/export/preview behavior takes precedence over
older fixed-preview settings and earlier device-budget observations in the audit.

The [2026-10-28 integration report](../performance/VALIDATION-REPORT-2026-10-28.md)
records a fresh simulator build and desktop/native gates. Existing device results
above retain their original scope; this integration does not repeat phone,
Photos-write, external-sharing or signing/provisioning acceptance.

## Selective settings clipboard

Use “复制参数” on the current photo or its context menu to choose process groups
at copy time. Crop ratio is initially unchecked. When selected, it copies the numeric proportion only; orientation follows the target, preserving its crop centre, straighten, quarter turns and flips. Confirmed groups and the
source snapshot form the clipboard; cancelling keeps the previous clipboard.
“选择” starts empty multi-selection, while the context menu's “选择多张” starts
with that photo checked. Photo taps then change checkmarks while the orange
border continues to identify the preview. Select all applies to the visible
filter result. Paste applies directly to the selected photos without another
range sheet, keeps the selection, and supports one undo/redo for the whole batch,
even after changing the preview. Single-photo paste uses the same clipboard.

Only editable intent is copied: each target retains its own metadata, lens
calibration and As Shot decode, and refits scene placement. Photo edits are automatically saved in the local library; the clipboard and undo history remain transient.
The Debug `--clipboard-regression` flag writes `Documents/clipboard-report.json`
from synthetic in-memory photo states without importing personal images. The
focused UI test is `PhotoImportTests.testSelectiveCopyAndMultiPhotoPaste`.

## Local library

The library supports search, rating/flag filters, visible-result select all,
copy/paste edit groups, batch ratings/flags, selected-photo export and confirmed
app-only deletion. Selection and scroll/filter state survive returning from the
editor. Batch editing provides an explicit apply-to-batch sheet; ordinary slider
edits still affect the previewed photo until applied. Export from the library
fixes the range to the chosen IDs even when an export preset changes.

`Application Support/Silverphase/library.json` is an atomic, versioned manifest;
originals live beside it with unique relative filenames. Startup does not delete
this directory. Corrupt/unknown records fail visibly and remain intact. Deletion
commits the manifest before removing owned originals, leaving the system Photos
library and import sources untouched. Finished preview thumbnails are disposable
Caches data keyed to recipe/geometry/settings. Unrendered or changed edits fall back to source thumbnails rather than stale finished pictures. The gallery defaults to a dense square grid and remembers its thumbnail size and aspect options. RAW, ratings and flags appear as small badges;
the filename, original format and available EXIF are in the photo’s context menu
under Photo Info. Photo count and original-file size are in Settings. The native
top toolbar shows Import, Select and More. Camera uses the native bottom toolbar.
More contains thumbnail size and aspect options, filename search, RAW/star/flag
filters, Settings and About. In selection mode the toolbar
shows Done and Select All/Clear. Once photos are selected, the native bottom toolbar
adds Edit, Export and batch actions. Duo places that group below the selection
controls in its vertical system rail. Horizontal swipes select a range or
deselect it when starting on a selected photo. Vertical swipes scroll. The editor
uses a back chevron to return to the library. Undo history is limited to the current
process; library albums, cloud sync and cross-device transfer are not implemented.

Debug `--library-regression` writes `Documents/library-report.json` with isolated
synthetic state/disk checks. `--library-ui-regression` uses a dedicated synthetic
library across launches; `--reset-library-fixture` resets only that fixture.
The focused XCTest is
`PhotoImportTests.testLibrarySelectionEditingExportAndColdRestore`.

Export filenames use checkbox choices for the original filename, film, paper,
export date and sequence number, with a live preview from the first export
target. Choices follow the displayed order with underscores and retain at least
one component. Stored recipe compatibility is preserved; a custom legacy naming
rule stays active until the user changes a choice. Template syntax is internal.
