# iOS capabilities and verification

[简体中文](CONTROL-AUDIT.md) · [English](CONTROL-AUDIT.en.md)

> This English companion covers current controls and validation boundaries. The Chinese source retains the complete dated test record.

This English edition covers the current contract and the scope of the checks. The reference is the current desktop source under `modern_UI/Spektrafilm/Spektrafilm`, not upstream screenshots. Default scalars are recorded in `Silverphase/Resources/DesktopControlDefaults.json`; desktop `MobileDesktopContractTests.testExportDesktopControlContract` guards the wire mapping. **Aligned** below means control and parameter parity, not that every material and device combination was tested on hardware.

## Current device experience

Conventional iPhone is portrait-only, with vertical film/paper lists, seven compact process/tools entries, a height-limited floating panel, Back/Export/Menu, and independent status beneath the toolbar. Duo and iPad use their own navigation. See the [interface specification](DESIGN.en.md) and [real-photo iPhone/iPad captures](../screenshots/ios/2026-11-27/README.md). Layout captures do not verify real-device touch, memory budgets, permissions, or full-resolution output.

## Camera and lock-screen capture

The in-app camera opens from the library footer. It offers live composition, front/rear and physical lens switching, flash, exposure, tap/lock focus, a CoreMotion level, golden-ratio/thirds grids and portrait preview. Choose a film before capture; the app develops the still and saves it to the local library. The Control Center camera control requests authentication and then opens the camera in the app. Physical Camera Control on supported devices can enter the LockedCameraCapture extension, which shares `MobileCameraView` (`SILVERPHASE_LOCKED_CAMERA`) and stages the original in the system session, not an in-process developed image. After unlock, the host renders and writes to Photos according to the same finished-only or RAW + finished setting; interrupted saves resume when the app is active again.

The camera's separate metering menu uses the editor's six film metering modes. Capture diffusion choices are Off, Glimmerglass, Black Pro-Mist, Pro-Mist and Cinebloom; default strength is 0.5, range multiplier 1. The focus-adjacent slider records −4…+4 EV of film exposure compensation for preview, editing and output; AVFoundation controls hardware exposure. The app persists film, metering and diffusion and hands initial values to `CameraCaptureIntent.appContext`; the extension's available changes use session state. Values latch at shutter and the JSON sidecar travels with each locked original. The host restores the film and paper/direct-scan route before the first render; old originals without a recipe keep the earlier default.

Phone/tablet camera chrome generally uses device-relative positions with glyphs rotating in place, independently of the host window. Duo's inner display has dedicated unfolded-landscape and tabletop layouts; see the [platform guide](README.md#locked-camera-film-and-orientation). Both camera paths latch physical pose at shutter; iOS 27+ uses AVFoundation's explicit pose-to-sensor mapping, and released orientation policy is scoped to the camera only. No hard-coded import rotation is added.

In-app live film composition modes are System, Smooth Approximate (default), and Native Engine (experimental). Existing native selections migrate once to Approximate; explicit Off remains Off. All saved photos use the native still recipe.

- **Approximate** caches up to two film-specific 49³ linear ProPhoto lookup textures, log-shaped over 0…16, and uses a small metering image and pre-table diffusion. The colour-sampling entry point excludes inter-sample spatial/sharpening/stochastic effects, not non-spatial colour, scan reference or pointwise EDR. Normal scheduling is 960 px/30 Hz, low-power/high-thermal 640 px/20 Hz. Capture releases large engine buffers but retains the two small textures. Device frame rate may be lower.
- **Native** reuses render session, pipeline and buffers; each new frame invalidates image-derived state. Independent metering input remains up to 1600 px, while scheduled preview is 640 px/30 Hz or 480 px/15 Hz under reduced power. The previously smaller 384/256 px input tier is retired. Skip metering when disabled and avoid a persistent negative copy. Preview receives camera-processed 8-bit SDR; halation headroom reconstruction is set to 0 to avoid inflating already mapped highlights, while material halation and the still-photo recipe remain unchanged.
- Both modes process only the latest frame, release resources on exit, and keep diffusion enabled under reduced power. Digital zoom stays live; physical/portrait switches freeze the displayed processed image until hardware and a matching processed frame from the new configuration are ready. Old frames cannot release a freeze. Preview is a composition aid, not RAW equivalence or final-print proof.

Record Capture Location is on by default but requires When In Use permission. The app uses a valid fix no older than 60 seconds at shutter, without waiting for GPS, and stops/clears it on camera exit, background or disable. Export can strip GPS; the Photos asset location comes from the finished image. The lock-screen extension does not request location. Composition status uses a separate row beneath camera controls.

**Known limitation, not fixed:** pressing physical Camera Control before authentication may briefly freeze the viewfinder or leave the shutter unavailable. The Duo log shows system Camera prewarming taking access; the 17 Pro cause is not confirmed. Tested devices worked after authentication. The framework requires a live camera at extension launch and cannot require authentication beforehand without dropping the entry entirely. In-app capture, development and Photos saving are unaffected. See [known startup limitation](README.md#known-limitation-camera-control-before-authentication).

## Process controls

| Control | Desktop default, range or contract | iOS |
|---|---|---|
| Film and paper | Portra 400 / Supra Endura; shared catalogue, reversal direct scan, B&W target paper | Aligned |
| Exposure latitude | Scene and material measurements, EV distribution, limits, separation and shares | `spk_scene_latitude`; explains failures |
| Legacy highlight/shadow placement | Keeps saved legacy edits; can clear | Aligned |
| Film metering | Centre-weighted default; manual, balanced, centre, protective highlight/shadow variants | Aligned |
| Film exposure | 0 EV; −4…4, step ⅓ | Aligned |
| Prep tone | Local highlights/shadows, exposure/contrast, toe lift, highlight gain, midtone detail/colour and camera-preview brightness matching | Per-photo RAW baseline; clipboard includes matching switch. Previous four controls only appear with saved legacy edits |
| RAW white balance | As Shot; presets, 2000…12000 K, tint −150…150, per-axis reset, neutral point | Implemented; neutral-point touch remains unverified |
| Lens correction | Default off; only decoder-supported sources | Aligned |
| Spectral filters | Off; W8/11/12/15/21/25/47/58 | Aligned |
| Capture diffusion | Off; Glimmerglass/Black Pro-Mist/Pro-Mist/Cinebloom | Aligned |
| Both diffusion stages | Strength 0.5 (0.125…2, step 0.125), range 1 (0.5…2, step 0.1) | Aligned |
| Film format | 135; Super8/16/Super16/Super35/65/110/APS/135/120/custom | Shared physical dimensions; output size is in Export. Existing non-default simulation size can be reset through Film process actions |
| Reference edge / unit / length | Short edge 24 mm; long/short edge, mm/cm/inch, custom length | Aligned; long edge derives from actual input aspect ratio, not fixed 35 mm |
| Grain strength | On; UI ×1, 0…2, step 0.1 | Aligned; Tri-X/HP5/TMax/Acros model factors 1.70/1.49/0.74/0.64 |
| Layered grain | On except the named B&W models | Aligned |
| Grain size | 1; 0.5…2, step 0.1 | Aligned |
| Grain softening | UI ×1; 0…2, step 0.1; wire ×0.65 | Aligned |
| Halation | Stock default; high/medium/low anti-halation or off | Aligned; strength 1, 0…4 |
| Emulsion scattering | 1; 0…1, step 0.1 | Aligned; incorrect previous upper limit of 4 fixed |
| Development contrast | 1; 0.5…1.5, step 0.05 | Aligned |
| Colour separation | On at 1; 0…1.4, step 0.05; unavailable in B&W | Aligned |
| Direct scan / DI | Off; reversal direct scan, DI bypasses printing | Aligned; DI bypasses paper, glare and scan sharpening |
| Print brightness | 0 EV; −3…3, step 0.25; wire is 2 to the power of −EV | Aligned |
| Print contrast | 1; 0.7…1.3, step 0.05 | Aligned |
| Yellow/magenta filtration | 0; −50…50, step 1 | Aligned; full underlying neutral calibration preserved |
| Multigrade paper grade | 2; 00/0/1/2/3/4/5 with exposure compensation | Aligned; limited to Multigrade, compensated once |
| Print effects / preflash | On / 0; ruler 0…0.05, direct input 0…1, step 0.005 | Aligned |
| Enlarger diffusion | Off; same choices as capture diffusion | Off when print stage is bypassed |
| Scan sharpening | On, UI ×1, 0…2; wire ×0.7 | Aligned; no extra unsupported black/white-point or blur controls |
| Print glare | On at 1; 0…4, step 0.1 | Off for direct scan/DI |
| Highlight expansion | On for new photos, off after Scan reset, disabled for direct scan/DI/B&W paper | Aligned |
| Film edge | Off; 135/strip/auto/white/none | Aligned |
| Film dimensions | 135, half frame, 645, 6×6/7/8/9, XPan, 6×12/17 | Aligned |
| Edge presentation / gate / holes / holder | strip/filed; auto/square/rounded/eared/shouldered/kicked; white/black; none/black/open | Aligned |
| Frame index / fog / light leak | 0 auto / 1 / 0; 0…99 / 0…4 / 0…4 | Aligned |
| Camera / transport seed | 1/1; change camera and repeat transport | Aligned |
| Date back | Off; empty text from EXIF, LCD, 3.5 EV, scale 1 | Aligned; no invented date without EXIF |
| Date style / format / capture data | LCD/dots/data, Japanese default/US, data off | Aligned |
| Date position / corner / margins | frame/br, 3 mm/2.4 mm; exposure −2…8, scale 0.4…3, margins 0…30 | Aligned; 120 requires an edge, panoramas have no date back |
| Reset section / value | Current material/capture defaults, not universal zero | Double-tap ruler, menu reset and undo history |
| Rotation and crop | Free crop, straighten, orientation, turns and flips | Shares `Geometry.swift`; eight touch handles, move/redraw, aspect/orientation, ±45°, both quarter turns/flips, same preview/export mapping |
| Half-frame pairing | Desktop two-photo composition | Not ported; single-photo half-frame gate supported |
| Masking or additional grading | Desktop feature-gated controls | No new mobile grading panel or change to the material model |

## Settings, export and local storage

Settings includes reduced-power priority, crop effect rescaling (off by default), DI blue compensation (off), cache release, and engine/workspace information. Preview automatically fits screen pixels and adds detail progressively, independent of output resolution. No fixed preview-size picker. Preferences and export recipes are independently persistent, and Settings separates photo count from memory information. Mobile does not expose placeholder desktop controls for interface scale, fast material LUT, detailed GPU timings, disk cache policy, manual memory override or host diagnostics; automatic memory guards remain active.

JPEG, PNG, 16-bit TIFF and Cineon DI are supported. Standard output supports Display P3 (default), sRGB and Adobe RGB, with ProPhoto also available in TIFF; JPEG quality defaults to 95%. Ordinary finishes share the desktop GPU output transform without additional tone compression. JPEG/PNG/TIFF write `xmp:Rating`.

Scopes include current/all/kept/filtered; choose 6/12/24/36/48 MP, long edge or full resolution subject to memory limits and source or simulation dimensions. Output sizing only downsamples. Naming combines original, film, paper, date and sequence; placeholder syntax is internal. Choose whether to keep metadata/remove location, target a folder and append/replace/skip collisions. Named recipes and TIFF previews are available. DI writes untagged 16-bit Cineon TIFF plus two desktop viewing LUTs, not ordinary Photos output. Custom ICC profiles, soft proofing, desktop comparison grids and half-frame composite export are not ported. Folder access is per-session; batch rendering is sequential.

The library atomically stores photo IDs, relative originals, recipes, crop, ratings and flags; a corrupt manifest is not replaced by an empty session. Deletion first persists removal and only then deletes app-owned files. JPEG previews are disposable; GPU state and undo history are transient. Search and format/rating/flag filters combine with explicit multi-select, swipe-range selection and fixed-ID export. Tap opens the viewer first: zoom, hold to compare, change film or read Photo Info before editing. A single edit has no filmstrip; batch shows only its chosen set. Clipboard copies chosen parameter groups, with optional crop ratio adapting to target orientation while preserving target position, straighten, turn and flip. Format availability, Photos permissions and memory are separate checks.

## Evidence and limits

| Check | Recorded outcome |
|---|---|
| Library and clipboard | 17 library-model and 29 parameter clipboard checks passed, including persistence, recovery, batch/deletion and ratio adaptation |
| Phone workspace | Focused XCTest verified seven tools, target size, float/height and canvas transform through transitions; 2 portrait/material tests passed without skips |
| Status placement | Focused ordinary iPhone/Duo simulator checks placed status 8–32 pt from Back; folded-window rotation is not unfolded-device coverage |
| Export names | 6 production Swift model checks: component order, compatibility and preview defaults |
| Desktop suite | 542 cases, 0 failed, 47 skipped for missing external RAW/camera/smoke fixtures; real-photo coverage incomplete |
| Neutral selection close/reopen | 6 isolated lifecycle checks passed, including cleanup of markers/preview; does not validate real RAW neutral colour |
| Build and install | Project generation, simulator/device builds and signing checked. Prior iPhone 17 Pro install verifies installation only; lock blocked automatic launch |
| Camera | Code/package and synthetic checks cover orientation declarations, 25 public films, 90 recipes and EXIF replay; phone/tablet layouts were exercised without opening a camera |

Camera checks also include 18 file-vs-video and 18 streaming comparisons, processed-frame ownership/cancellation, migration, orientation and synthetic timing. They do not establish physical sensor orientation, true lock-screen execution, hinge transitions, permission flow, sustained thermal performance or full-resolution photo capture. The simulator's fixed-ID batch export was stopped by the memory limit and not cleared by weakening it. Historical Duo export, strip, colour and crash follow-up results apply only to the recorded inputs and dates.

For diagnostic flags/outputs see [the platform guide](README.md#validation). The English page does not repeat every dated session entry. The [Chinese audit's screenshot and reproduction section](CONTROL-AUDIT.md#截图与复现) retains exact acceptance details and dated tests, and the [archived audit](history/CONTROL-AUDIT-through-2026-11-02.md) preserves superseded designs and historical diagnostics. For current 1.4.0 visuals see the [real-photo documentation](../screenshots/ios/2026-11-27/README.md); the [2026-11-02 screenshot set](../screenshots/ios/2026-11-02/README.md) used synthetic inputs.
