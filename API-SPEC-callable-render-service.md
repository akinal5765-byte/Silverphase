# Silverphase native render API

Current integration reference, reviewed 2026-10-28. The filename is historical:
there is no callable Python service in the product. The authoritative declarations
are [spk_engine.h](engine/include/spektrafilm/spk_engine.h); parameter metadata and
validation live in [params.cpp](engine/src/core/params.cpp). The [earlier service
spec](docs/history/API-SPEC-callable-render-service.md) preserves old probes,
Python paths and timing results; they are not current runtime instructions.

## 1. The boundary

macOS `EngineClient` and iOS `MobileEngine` call one linked C++/Metal engine.
JSON carries parameter deltas and analysis replies. Image buffers and textures
cross through native structs, never temporary JSON-RPC pixel files.

| Operation | Native entry points |
|---|---|
| Lifecycle/data root | `spk_engine_create`, `spk_engine_destroy` |
| Discover methods/parameters | `spk_capabilities`, `spk_params_schema` |
| Open scene-linear float32 RGB/RGBA | `spk_open`, `spk_open_device` |
| Read/update parameters | `spk_get_params`, `spk_set_params` |
| Exposure/filter-pack solve | `spk_solve` (`exposure`, `filter_pack`, `both`) |
| Film + print / reuse eligible negative | `spk_render`, `spk_reprint` |
| Analysis / presentation geometry | `spk_scene_latitude`, `spk_overscan_geometry` |
| Intermediate / preview / table | `spk_render_digital_intermediate`, `spk_preview_scan`, `spk_preview_stock_lut`, `spk_print_lut_table` |
| Output conversion | `spk_output_transform` |
| Progress/cancellation | `spk_progress`, `spk_cancel` |
| Release resources | `spk_result_free`, `spk_string_free`, `spk_session_release` |

Additional diagnostic/legacy functions remain declared in the header; this table
is a host integration map, not an exhaustive generated API list.

## 2. Parameter layers and cache invalidation

`spk_set_params` takes an object of flat schema names and returns an owned JSON
reply containing `invalidated` and resolved `params`. Unknown names, wrong types,
invalid enum choices and out-of-range values are rejected by native validation.
Use `spk_params_schema` for exact defaults/types/ranges rather than duplicating
a stale field count. Stock digestion and product defaults can change resolved
values relative to raw schema defaults.

- `shoot`: invalidate film/negative. Examples: film stock, lens filter, exposure,
  grain, scene latitude, film edge, date back and paired-frame regional mapping.
- `print`: retain eligible negative; re-run print/output. Examples: paper,
  enlarger/filter pack, print exposure, scan controls and Cineon DI selection.

The `live` schema flag describes adjustability, not permission to reuse a negative.
Result flags `reprint` / `negative_was_cached` expose actual reuse. A stock's
`targetPrint` documents a declared pairing; rendering another paper is possible
but does not establish measured compatibility.

## 3. Ownership and errors

Caller-owned input memory is valid for the open call; the engine copies what it
retains. `spk_device_image.buffer` must be a sufficiently large buffer on the
engine's Metal device, tightly packed float32, top row first. Alpha is ignored.

A successful `spk_result.texture` is returned retained (+1). `rgba16` aliases its
memory and is valid while that texture remains retained. Read rows using
`row_stride_px`, not width: device texture alignment can add padding. Swift must
transfer ownership once; C callers release with `spk_result_free`. Follow the
header for borrowed versus caller-freed JSON; never free a borrowed schema/table.

Check every `spk_status` and the engine error text. Error categories include
invalid arguments/user input, resources, unsupported settings, GPU, I/O,
cancellation and internal errors. Failed calls are not valid image results.

## 4. Input and output semantics

Input must match its declared color space and transfer-function flag. Hosts
provide scene-linear ProPhoto RGB float32 after ImageIO/Core Image decoding.
Encoded RGB is decoded at the input boundary; exposure then acts in linear light.
RAW-only controls are not offered for already rendered JPEG/TIFF files.

Normal output is configured explicitly by the host. Preserve working-space
semantics through canvas/proof/export conversion and write the destination ICC
for ordinary image files. The engine returns pixels and tables; it writes no
JPEG, TIFF or `.cube` files.

## 5. Material data and solving

Bundle base `engine/resources/` plus the product overlay. The engine reads a
single resolved data root; it does not search `resources_product/` automatically.
Keep adopted source/profiles and provenance notices together.

`spk_solve` and scene analysis are separate from manual control changes. Film
exposure can be normalized by print compensation; do not assume the exposure
control is an output brightness gain (AGENTS trap 30). A variable-contrast paper
grade is translated by the host to filtration and print exposure, once. It is
not a replacement tone curve or a dedicated `paper_grade` engine field.

## 6. Resolution

Native render tier names remain `live`, `preview`, `full`. Supported names in an
ABI are not a requirement to expose a three-step quality picker. Desktop uses
its preview/full scheduling; mobile adapts fit and viewport detail automatically.
`preview_long_edge` affects interactive resolution; export recipe resolution is
independent. Grain/spatial scale must use the physical source/frame dimensions.

## 7. Memory and concurrency

Serialize session operations through the platform wrapper. Cancellation can be
signalled from another thread as documented in the header. Keep generation and
selection guards in hosts so late results cannot replace a different photo.

Engine buffers can remain referenced by pending GPU commands after a CPU handle
drops. Reuse follows flush/completion; never infer safety from refcount alone.
Striped rendering requires explicit configuration. Dimension-changing overscan
rebuilds the downstream strip plan; halos and final partial bands remain part of
the pixel contract. Strip/whole equality is not physical oracle validation.

## 8. Export and intermediate

Finished exports use host ImageIO writers after destination conversion. Current
Cineon DI uses `spk_render_digital_intermediate`: untagged 16-bit log TIFF,
ProPhoto RGB primaries, film base at code 95; host supplies the fixed DI view
LUTs and preview. The view transforms are Cineon→ProPhoto RGB / Rec.709, not
paper print LUTs. Ordinary RGB export of a DI applies the view and destination
profile. Legacy `spk_export_di` density/print-LUT behavior remains in the ABI
for compatibility; it is not the current UI package.

## 9. Verification

See [VALIDATION.md](modern_UI/Spektrafilm/VALIDATION.md) for gates and fixture
policy. Use native GPU/math checks and relevant feature tests, plus host file
and pixel checks. Full XCTest reports must include skips. Historical Python
parity scripts require an explicit external oracle; the retired frozen oracle
is not a build or acceptance dependency.

## 10. Version negotiation

`SPK_TRANSPORT_VERSION` and `SPK_SCHEMA_VERSION` are currently 1. Keep capability
reply fields decodable by hosts; the schema is extended with named native fields.
A breaking contract change needs a coordinated version/host change, not a
silent reinterpretation of existing names. Follow the [contract](CONTRACT-frontend-backend.md).

## 11. Output transforms and diagnostics

`spk_output_transform` provides native destination transform data; hosts own
conversion scheduling and file tagging. `spk_memory_report`, `spk_build_info`,
progress and node timings serve diagnostics. Encoding elapsed time alone does
not establish GPU completion time. Keep load and thermal context with benchmarks.

## 12. Scene latitude

`spk_scene_latitude` measures the medium and scene, suggests pull-backs and solves
a fit; it does not render or silently apply a recommendation. Requests may set
`highlight_pull_back`, `shadow_pull_back`, `rolloff`, `max_lift`, `norm`, `margin`
and robust extreme percentiles as documented in the header. Only a valid fit
carries an applicable `params_delta`; commit it with `spk_set_params`.

Paired-frame support adds `scene_latitude_split` (0…1),
`scene_latitude_b_active`, B highlight/shadow knees (−24…24 EV) and rooms
(0…24 stops). These are shoot fields. The host resolves each photograph's scene
placement before/for its paired region; a shared paper grade stays print-side.

## 13. Film edge, date back and lens filters

These additions are shoot-layer fields with `live: false`. Refer to schema and
`Params` for exact defaults; the host also resolves text, EXIF and framing.

| Field group | Names / semantics |
|---|---|
| Edge selection | `overscan_active`, `overscan_format`, `overscan_mode` (`strip` / `filed`) |
| Shape | `overscan_gate` (`auto`, `square`, `rounded`, `eared`, `shouldered`, `kicked`), `overscan_holes` (`white` / `black`), `overscan_carrier` (`none`, `black`, `open`) |
| Seeds | `overscan_camera_seed`, `overscan_frame_seed`: 0…2147483647 |
| Exposure/marking | `overscan_fog`, `overscan_leaks`: 0…4; `overscan_edge_text`; `overscan_f_number`: 0…64 |
| Frame/pair | `overscan_frame_number`: 0…99 (0 automatic); `overscan_pair` |
| Date exposure | `date_imprint_active`, `date_imprint_text`, `date_imprint_text_b`, `date_imprint_data_text`; `date_imprint_ev`: −2…8 |
| Date layout | `date_imprint_placement`, `date_imprint_style` (`lcd`, `dots`, `data`), `date_imprint_size`: 0.4…3, `date_imprint_corner`, `date_imprint_inset_x` / `y`: 0…30 mm |
| Lens filter | `camera_filter`: empty, `w8`, `w11`, `w12`, `w15`, `w21`, `w25`, `w47`, `w58` |

Formats are `135`, `135_half`, `120_645`, `120_6x6`, `120_6x7`, `120_6x8`,
`120_6x9`, `135_xpan`, `120_6x12`, `120_6x17`. All 135/ordinary 120 formats
support the modeled date faces; 120 placement is in the film margin and needs
overscan. Panoramic formats have no date back. Hosts gate unavailable options
instead of promising that every accepted field draws on every format.

`spk_overscan_geometry(session, &out_json)` returns caller-freed geometry JSON
for presentation mapping. Overscan changes rendered dimensions; use returned
geometry/result sizes, never a fixed border percentage. Lens filtering changes
image exposure sensitivity with compensation, but edge printers/date backs use
the unfiltered sensitivity. Source/provenance and assumptions are in
`engine/resources_product/UPSTREAM.json` and the film-edge source notes.
