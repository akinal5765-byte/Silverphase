# Silverphase architecture

Current implementation map, reviewed 2026-10-28. Silverphase derives from Hanze
Qiu's SpektraLab and Andrea Volpato's spektrafilm model. Product name changes do
not change source or profile attribution. The [documentation index](docs/README.md)
identifies current guides; the [earlier architecture](docs/history/ARCHITECTURE.md)
retains old measurements and descriptions. Section numbers remain stable where
practical because code and RFCs refer to them.

## 0. The product, end to end

Silverphase has native macOS and iOS/iPadOS hosts over one C++20/Metal engine.
The macOS target is still named `Spektrafilm`, but builds `Silverphase.app`.
The iOS target is `Silverphase`. Both link the engine into the application and
load bundled data. There is no runtime Python, stdio service, subprocess renderer
or CPU fallback. Python scripts are development tools.

```text
Photos / files
  → platform ImageIO / Core Image decode → scene-linear ProPhoto RGB float32
  → C ABI + JSON parameters → C++ setup and Metal film/development/print/scan
  → owned texture → platform canvas / geometry / destination color transform
  → host ImageIO file writer → finished image or Cineon DI + viewing LUTs
```

| Boundary | Source |
|---|---|
| Native ABI, ownership, cancellation | `engine/include/spektrafilm/spk_engine.h` |
| Parameter names, ranges, cache layers | `engine/src/core/params.cpp` |
| Profile/calibration setup | `engine/src/core/` |
| GPU allocation and completion | `engine/src/gpu/metal_gpu.cpp` |
| Pipeline and whole/strip execution | `engine/src/pipeline/` |
| Native kernels | `engine/src/shaders/` |
| macOS host | `modern_UI/Spektrafilm/Spektrafilm/` |
| iOS host | `ios/Silverphase/Sources/` |

### Who owns what

Decode, documents, crop/presentation, UI scheduling, export policy and file writes
belong to the host. Film/paper setup and image formation belong to the engine.
A material profile records capability; scene placement before film and output
headroom after print must not be hidden by edits to measured profiles.

The frontend/backend two-session ownership split is retired. The [contract](CONTRACT-frontend-backend.md)
now describes this native boundary. Announce shared global-document edits.

### Where to read more

See [macOS engineering](modern_UI/Spektrafilm/README.md), [iOS engineering](ios/README.md),
[iOS control audit](ios/CONTROL-AUDIT.md), [validation](modern_UI/Spektrafilm/VALIDATION.md),
[API](API-SPEC-callable-render-service.md), and [agent notes](AGENTS.md).
RFCs record design decisions at their dates; missing upstream RFC numbers cited
in adopted source do not imply those files exist locally.

## 1. The physical model

Scene light passes through camera exposure/filtration, film exposure and
spectral response, development/density/grain, enlarger/paper development, and
scanner/output conversion. Positive-film/direct-scan and Cineon intermediate
paths bypass paper. Scene-latitude analysis suggests placement; changes are
committed through explicit parameter deltas.

Lens filters (`camera_filter`: empty, w8/w11/w12/w15/w21/w25/w47/w58) modify film
sensitivity with exposure compensation and invalidate the negative. They do not
filter edge-printer or date-back exposure. Diffusion, halation and print glare
are separate effects with separate physical positions.

### Product B&W data

`engine/resources/` contains the 28 original base profiles. Self-authored
experimental material profiles and their generators are excluded from tracked
product inputs. Maintainer builds optionally stage an ignored local overlay;
`SILVERPHASE_LOCAL_MATERIALS=0` removes it for public builds. The shared catalog
merges `LocalMaterials/StockCatalog.json` only when packaged; the experiment
category is visible only when that overlay contains materials.
`engine/resources_product/` carries adopted Tri-X 400, HP5 Plus 400, T-Max 100,
Acros II and Multigrade IV RC data, paper-grade packs, and source provenance.
The build overlays product profiles into the bundled profile directory. Legacy
Tri-X/HP5 experimental IDs resolve to the adopted stocks for existing edits.
Other experimental material IDs require the local overlay; without it they produce a missing
profile error rather than silently selecting another stock. See [B&W source notes](engine/tools/profile_sources/blackwhite.md).

`channel_model: bw` uses neutral silver and disables layered color-grain behavior;
generic monochrome decoding structures remain for compatibility. Silver paper has no
calibrated color-paper EDR map, so EDR is gated off. Paper grades 00–5 map to
filtration plus exposure compensation in the host, preserving negative reuse.
These profiles and approximations do not establish accuracy for all chemistry,
lighting, grain or real-film samples.

### Film presentation

`overscan.cpp` / `overscan.metal` implement physically scaled film gates, edges,
perforations, fog/leaks, markings and date-back exposure. Formats include 135,
half-frame, 645 through 6×9, XPan, 6×12 and 6×17. Date-back availability depends
on format: panoramic formats have none; 120 dates use margins and require edges.

Metering/highlight statistics use the photograph before canvas expansion.
`film_overscan` follows exposure/boost, then normal film processing acts on it.
`print_film_present` and `print_edge_light` handle later presentation. Output
shape can change; `spk_overscan_geometry` returns geometry for host mapping.
The strip executor rebuilds its band plan after a size-changing whole stage.

Desktop pairs are `.spektrapair` JSON documents referencing two photos. The host
composes scene-linear inputs and resolves frame geometry/dates; pair settings
and per-source shot information remain distinct. Regional scene-latitude B fields
support the second frame. iOS currently supports a single half-frame gate but
has no two-photo pairing workflow. [Film-edge notes](engine/tools/profile_sources/film_edge.md)
describe modeling assumptions rather than measured scanner reproduction.

## 2. Runtime structure

macOS `Session` owns selection, asynchronous decode, parameter generations,
undo/sidecars, cache and render scheduling. `EngineClient` serializes native
calls and gives the canvas owned results. `Session+FilmPresentation.swift`,
`FilmCanvasInput` and `PairComposer` resolve presentation/composition outside the
material model.

iOS `MobileDocument` coordinates imported photos, per-photo state, operations,
settings and recipes. `MobileEngine` wraps the same ABI. Shared desktop sources
are compiled by relative reference: `StockCatalogCore.swift`, `ParamValue.swift`
and `Geometry.swift`. `DesktopControlDefaults.json` captures desktop defaults;
`MobileDesktopContractTests` detects drift. Other mobile control code is
platform-specific and must be audited explicitly.

Source or session changes invalidate in-flight work; stale results must not
replace the current photograph. Import/export operations own a modal progress
state on mobile; ordinary adjustment previews stay interactive. Imported mobile
copies are cleared at a cold start while preferences/recipes persist.

## 3. Stage classification

The engine separates pointwise, neighborhood and whole-image stages. Banded
runs fuse eligible operations and carry neighborhood halos; global statistics
remain whole-image. Spatial parameters derive from physical film dimensions
and source resolution, not arbitrary preview pixel sizes.

`shoot` parameters invalidate film/negative caches; `print` parameters can reuse
the developed negative. Film edge, date back, lens filter and scene placement
are shoot changes. Paper grade is a host mapping to print parameters. A cached
negative from the wrong generation is a correctness failure.

## 4. Memory model

GPU images use reference-counted buffers. Last CPU reference release does not
mean encoded GPU commands have finished reading. Node flush/completion boundaries
make buffers reusable; preserve these boundaries and result ownership. Cache
retention and working scratch allocations are separate budgets.

The striped path bounds eligible stage scratch, but whole stages and output
planes still exist. Overscan can expand those planes; desktop file-backed
allocations and pool trimming handle that path. Dead log-exposure and grain
planes are released at last use. The opt-in grain accumulator alias path must
preserve exact pixels, checked by `accumulator_alias.cpp`.

Device-only iOS pool retirement avoids keeping a completed zero-reference buffer
of at least 64 MB when it is at least four times the requested size. Mobile JPEG
export explicitly requests 256-row strips, uses a small comparison placeholder,
and releases engine source/negative/pool before host image conversion. A zero
strip-row default alone does not activate this bounded path. Memory guards
still depend on process availability. Increased Memory Limit must be authorized
by the actual signing profile; an entitlement file alone proves nothing.

## 5. Build and release

Apple silicon; macOS 15+, iOS/iPadOS 18+. The current local toolchain is Xcode
27.1 with Metal Toolchain. Set `DEVELOPER_DIR` per command if Command Line Tools
is selected. Commands and outputs are in the platform READMEs.

`engine/build.sh all` builds native libraries, kernels, drivers and desktop
resource overlay. Desktop Xcode builds compile engine C++ sources and consume
the prepared metallib. iOS `Tools/build-engine.sh` compiles the same sources
for device/simulator, caching by source/header/compiler/SDK/script fingerprint.
Both use safe/precise Metal float32 flags and a runtime math probe.

Desktop bundle data is under `Resources/engine`; iOS uses `AppResources/engine`
to avoid Foundation's old-style bundle inference for a root `Resources/` folder.
iOS merges base neutral-print calibration with product additions. The desktop
host applies its paper-grade mapping. Never replace the full calibration database
with the product supplement.

Both projects compile the same `Silverphase.icon`. Approved artwork and design
history are indexed in [design/app-icon/README.md](design/app-icon/README.md).
Project generators use deterministic relative file identities. Regenerate after
source additions/removals; keep caches, signing profiles and build products out
of Git.

License texts, product notices, provenance and profile-change records ship with
the app. `bundle-licenses.sh` maintains them; `check-bundle-resources.sh` checks
the desktop inputs. `package.sh` archives/signs the app, signs the DMG, notarizes,
staples and assesses the image with Gatekeeper's open/primary-signature context.
The existence of this script does not establish a notarized public release.
Never push to `upstream`.

## 6. Where the time goes

Decode, input color conversion/upload, film development, print, host output
transform and file writing are separate costs. `Session.LoadClock` and
`core=native-metal` remain diagnostic instruments. GPU dispatch encoding time
is not execution time; completion must be measured separately. Check competing
load/thermal state before quoting timing or memory claims.

Earlier timings are preserved in the historical architecture and dated reports.
They are not current acceptance limits. See iOS guides for the scope of recorded
device audits; no new device performance claim follows from this documentation.

## 7. The frontend

### 7.1 Structure

macOS uses SwiftUI/AppKit, a Metal canvas, floating process inspector, bottom
film/paper browser and photo strip. [UI-SPEC](modern_UI/design/UI-SPEC.md) and
current source govern layout. iOS uses native navigation, glass panels, tick
rulers and a compact material browser; iPad keeps horizontal process navigation
and a right inspector. [iOS DESIGN](ios/DESIGN.md) records its layout.

### 7.2 Process controls and compatibility

Camera → film → development → print → scan/crop is the exposed process order.
There is no separate general grading rail. Legacy adjustment/sidecar structures
may remain for compatibility. A source file's existence is not a promise of an
exposed feature. Local-mask interaction is not currently a shipped editing flow.

### 7.3 Resolution

macOS renders an interactive preview and schedules full source detail using its
session/generation guards. iOS adapts fit resolution to screen pixels, coalesces
interactive updates and progressively requests viewport detail up to native
pixels. Fit/1:1 is available by gesture/menu. Mobile has no fixed preview-size
picker; low-power behavior remains a preference. Export resolution is independent
of preview resolution and remains bounded by source size and memory policy.

### 7.4 Host responsibilities and limits

Hosts decode files, preserve metadata policy, manage documents, crop geometry,
undo, settings, progress and output delivery. They do not repair input-decode
or output limitations by changing measured film data. Mobile lacks desktop pair
composition, custom ICC installation and soft proof/export comparison grids;
see the control audit for detailed coverage.

### 7.5 Color chain

RAW enters through Core Image's scene-linear decode; encoded RGB enters through
its profile/transfer-function decode. Working input is scene-linear ProPhoto
float32. White-balance/lens RAW controls apply only to RAW. An external rendered
TIFF cannot recover the original camera radiance or invert a developer's look.

The canvas and host color conversion honor working/output space; UI literals
painted into a working-space texture must be converted as well. Shared desktop
output shaders also serve mobile. Ordinary exports write destination ICC tags;
Cineon masters intentionally omit a display ICC profile.

## 8. The native engine

### 8.1 Layout

`core/` owns profiles, parameters, spectral/color setup, filters and caches;
`gpu/` owns Metal resources; `pipeline/` owns stage execution/session/C ABI;
`shaders/` owns kernels. Base and product data are separate tracked inputs.

### 8.2 The C ABI

JSON carries small parameter requests/replies. Textures/pixel buffers use typed
native structures; results, strings and sessions have explicit release functions.
The ABI header and runtime capabilities/schema are authoritative. See the API
for scene-latitude, overscan-geometry and output-transform entry points.

### 8.3 The GPU layer

No alternate CPU renderer. Allocation, dispatch, copy, flush/completion and
pool reuse must preserve pending work and retained output textures. Device and
simulator texture compatibility paths do not change the material model.

### 8.4 The kernels

Compile with `-fmetal-math-mode=safe` and
`-fmetal-math-fp32-functions=precise`. Native math-probe startup rejects an
incompatible metallib. Do not inherit canvas fast-math settings into engine
kernels. Profile NaNs and matrix orientation need the handling in AGENTS traps.

### 8.5 Caches

Setup caches avoid regenerating spectral/print/gamut tables on unrelated edits.
Film/negative caches allow cheap print changes. Host caches may evict results
under pressure; tests must observe completed rendering, not demand retention
of an evictable texture. Cache keys include all parameters affecting the stage.

### 8.6 Verification

Current acceptance uses native GPU smoke, math guard, focused engine checks,
XCTest and manifest-based real-photo workflows. Full suite skips are reported.
Whole/strip equality, reset invariance, default contracts and file ICC/depth
checks answer different questions; none establishes independent physical accuracy.

Frozen Python oracle parity is retired as a required gate. Historical scripts
and their tolerances remain available for explicit research use, without a
claim that they ran against this revision. See [VALIDATION](modern_UI/Spektrafilm/VALIDATION.md)
and dated reports in `performance/`.

### 8.7 Performance evidence

Report input, device, load/thermal state, recipe and whether memory was sampled
or peak. A simulator build does not validate device export budgets or gestures.
The [historical architecture](docs/history/ARCHITECTURE.md) preserves prior
measurements; [iOS audit](ios/CONTROL-AUDIT.md) preserves bounded mobile evidence.

### 8.8 Export boundary

The engine returns pixels, transforms and LUT tables; hosts write files.
Finished JPEG/PNG/16-bit TIFF carries the chosen destination ICC.
`spk_render_digital_intermediate` returns Cineon-log data with ProPhoto primaries,
film base at code 95; the host delivers an untagged 16-bit TIFF plus fixed
Cineon→ProPhoto/Rec.709 view LUTs and an optional preview page. These are not the
selected paper's LUT. Legacy `spk_export_di` density/print-table support remains
in the ABI but does not define the current UI's DI package.

### 8.9 Timing

Node timers ordinarily measure CPU encoding. GPU-completion timing must be
explicit. Maintain per-node names and the open-path instrumentation; do not
remove safe synchronization to improve an encode-only number.
