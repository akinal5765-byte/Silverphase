# Silverphase host/engine contract

Current contract, reviewed 2026-11-09. This filename predates the native engine.
The product has two native hosts and one shared C++/Metal engine. The earlier
Python service/two-session contract is preserved in
[docs/history](docs/history/CONTRACT-frontend-backend.md); its file ownership,
worktree rules and unimplemented requests are historical.

## 1. The boundary

The public C ABI is `engine/include/spektrafilm/spk_engine.h`. Native parameter
names, types, ranges and cache layers live in `engine/src/core/params.cpp`.
macOS `EngineClient` and iOS `MobileEngine` provide host wrappers. JSON carries
small requests/replies; typed native structures carry input buffers and owned
output textures. There is no stdio protocol or runtime Python process.

### 1.1 Operations

Lifecycle/capabilities/schema → open input → set parameters/solve → render or
reprint → host presentation/export → release. Scene-latitude analysis is
explicit and returns a delta to apply. Film-edge geometry is queried through
`spk_overscan_geometry`. The [API reference](API-SPEC-callable-render-service.md)
records current surface/semantics, including Cineon DI versus the legacy API.

### 1.2 Invariants

- Input pixels match their declared color space and transfer function; after
  decode they are linear RGB. Rendered JPEG/TIFF inputs can retain baked tone
  rendering and are not thereby recovered scene radiance. Both hosts normally supply linear ProPhoto
  float32. Never compensate for decode errors in material profiles.
- `shoot` edits invalidate the negative; `print` edits may reuse it. Film edge,
  lens filter, date back and paired scene placement are shoot-side. Paper grades
  map to print filtration/exposure, applied once. A cache layer is correctness.
- Borrowed inputs remain valid during the call. Results have retained textures,
  valid row strides and explicit ownership. Pending GPU work can outlive CPU
  references; buffer reuse requires completion boundaries.
- Hosts own files, documents, crop geometry, metadata/ICC policy and export
  recipes. The engine returns pixels/tables and writes no image files.
- Selection/session/parameter generations guard asynchronous results.
- Bundled resources, profile overlays and notices must come from the source
  revision being built. A stale bundle is not a valid acceptance result.

### 1.3 Lightroom external-edit host contract

macOS 1.2.0 accepts a single Lightroom Classic JPEG/TIFF copy, retains its initial
input and writes the developed result to the registered target only on Save.
Saving uses full-resolution normal rendering and an atomic ImageIO write;
success closes the editor, failure leaves it open. It adds no native method,
parameter, cache layer, transport or schema version. TIFF writeback is 16-bit;
JPEG is re-encoded at 8-bit. Both carry the chosen ProPhoto RGB output ICC.
The ordinary file reader decodes the incoming ICC; it cannot undo baked Lightroom
adjustments. No silent exposure or material compensation is part of the contract.
The first retained input is reused for a repeated path, so newly baked LR edits
must arrive under a new path. See [workflow and limits](docs/LIGHTROOM-CLASSIC.md).

## 2. Version negotiation

Transport and schema versions are currently 1. Keep `transport_version` and
`schema_version` in capability replies and update both hosts for breaking changes.
A transport mismatch must be visible; decoding/startup failure must not be
silently treated as a warm-up miss. Named additive fields still require matching
Swift mapping/tests and correct invalidation behavior.

## 3. Platform sharing

Shared by relative reference: current engine, base/product data, catalogue,
`StockCatalogCore.swift`, `ParamValue.swift`, `Geometry.swift`, production icon
and relevant output shaders. Mobile defaults are captured in
`ios/Silverphase/Resources/DesktopControlDefaults.json` and checked against
actual desktop defaults by `MobileDesktopContractTests`.

Mobile keeps its own native UI, memory policy, import/progress/export lifecycle
and adaptive preview. Desktop `.spektrapair` workflows, custom ICC and soft proof
are not automatically mobile features. The iOS control audit lists the boundary.
A compile does not establish device memory provisioning, touch or Photos access.

## 4. Ownership and source changes

CineStill 800T shares its alias profile, back-reflection implementation,
catalogue and packaging illustration across both hosts. The additive
`halation_headroom_ev` control is shoot-side, defaults to 4 EV for legacy
recipes, and belongs to film settings for reset/copy/paste. It changes scene
light before film exposure, never the base material's measured arrays.

The repository is one product; there is no exclusive frontend/backend directory
assignment. Announce edits to shared global documents. No parallel agents or
separate worktree is mandated by this contract. Preserve the user's existing
changes; do not reset or discard them as workspace cleanup.

Regenerate the relevant Xcode project after adding/removing sources (including
engine C++ sources in the desktop project). Check both generators after changing
shared files. Preserve upstream history, GPL/CC BY-SA notices and visible author
credits. Never push to the original `upstream` remote.

## 5. Verification and delivery

Use focused tests during implementation and one full desktop gate at integration.
Run relevant native checks when kernels/resources/inputs/render boundary change.
Report missing fixtures and skips; independent Python oracle parity is historical
unless an explicit external reference is actually run. No test suite substitutes
for real-window/device interaction or physical-model validation.

Current commands and acceptance scope are in
[VALIDATION.md](modern_UI/Spektrafilm/VALIDATION.md) and [ios/README.md](ios/README.md).
Keep private photographs, exports, logs, signing material and Xcode caches outside
Git. Commit/push only when requested; creating a local commit does not authorize
publishing, remote push or release.

## 6. Adopted surfaces in this workspace

The current integration includes product B&W profiles/Multigrade grades, Wratten
lens filters, film edges/date backs, desktop half-frame pairs and regional scene
placement, shared mobile models/geometry/icon, adaptive mobile previews, and
mobile import/export progress plus bounded JPEG rendering. Attribution is in
`engine/resources_product/UPSTREAM.json` and the bundled license notices.

Check source and dated validation reports for proven behavior. Historical
performance numbers or prior-device reports must not be presented as a fresh
run of the current commit.

### Continuous camera-frame replacement

iOS live film view uses `spk_replace_device_frame` for consecutive frames of the
same dimensions and recipe, retaining native setup rather than reopening a
session each time. The frontend finishes its linear ProPhoto upload before the
call. The engine copies that borrowed input and invalidates all image-derived
state, including exposure measurement. Recipe/dimension changes open a new
session. Display/frozen frames own their pixels; neither source replacement nor
shutdown may mutate them. This does not affect still-photo open/render semantics.

Camera display uses `spk_render_viewfinder` at 640px (480px under reduced power),
while keeping the up-to-1600px metering input. The display tier has no schema
field and cannot lower editor/export quality. Auto exposure off preserves each
input's brightness; it does not assert a system video frame is a RAW scene
estimate. No guessed exposure gain or material alteration is applied.

Approximate-camera colour tables use `spk_render_color_samples`, not ordinary
photo rendering of an RGB lattice. Adjacent table entries are unrelated colours
and must not share blur, DIR diffusion or sharpening. The helper preserves
pointwise print EDR/scanner colour references and does not mutate the recipe.
Table layout/permutation invariance is a required native check. Preview modes
remain composition approximations on ISP video, not inverses of a RAW decode.

For iOS 1.2.1 the approximate path is the default composition mode, with a
one-time migration from the saved experimental native selection; explicit off
and subsequent manual choices persist. Host-side input generations prevent an
old processed frame from releasing a lens/portrait freeze. Digital zoom continues
processing during the ramp. Lock-screen capture retains system preview. None of
these choices changes the captured recipe or supplies an inverse RAW decode.
