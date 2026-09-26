# Silverphase performance baseline — 2026-09-26

This is the starting measurement for the performance engineering work, not a
release performance claim. The app was built from `ec94e28` with Xcode 27 beta
on a 16 GB Apple Silicon Mac. `SPEKTRAFILM_CANVAS_LOG=1` supplied the stage
times; `/usr/bin/time -l` supplied maximum resident set size. The engine
reported `core=native-metal` in each run.

## Actual image path

```text
File (RAW / TIFF / JPEG / other supported flat format)
  → Core Image / ImageIO decode
  ├─ display CIImage → scaled original preview → rgba16Unorm MTLTexture
  │                    (Original / before-after comparison; not the first print)
  └─ scene-linear ProPhoto CIImage → shared float32 RGBA MTLBuffer
       → spk_open_device → engine source
       → film/camera/negative stages (cached per resolution tier)
       → print and scan stages → rgba16Unorm MTLTexture
            → app Layer 2 Metal kernel → histogram + canvas fragment
            → CAMetalLayer drawable
```

The live tier renders at the chosen preview long edge (2560 px by default).
On a cold open, the original preview is made and cached before the engine
frame, but it is not put on the canvas. The first image the user sees is the
developed print, after the full engine input has been decoded.
After an edit settles, a full-resolution render follows. Zoom and pan change
the canvas sampling transform, not the film pipeline. Export asks the engine
for a full-tier print, then applies the app's geometry, Layer 2 and output
colour transform before ImageIO writes the destination format. A separate
embedded/developed thumbnail path feeds the filmstrip and batch grid.

The engine caches a negative for reprints and setup data for repeated stock
and parameter combinations. The frontend holds bounded decoded, source,
print, thumbnail and disk cache entries. Re-decoding is required when camera
white balance or lens correction changes; a print-only edit can reuse the
negative; a Layer 2 or viewport edit stays in the app's Metal canvas.

## Synthetic flat-file baseline

Each file was an LZW TIFF with a two-axis grey ramp, generated in `/private/tmp`
and opened once through the app's snapshot harness at 1600×900. Each row is
one run, so these figures identify paths and approximate scale; they are not
statistical latency estimates. `open path` is measured from frame load to the
developed live print and excludes app startup. Warm-up was 375–393 ms.

| Input | Decode | Original preview texture | Engine frame | Engine open | Solve | Live reprint | Open path total | Full render | Peak RSS |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 6000×4000 (24 MP) | 101 ms | 72 ms | 101 ms | 40 ms | 428 ms | 187 ms | 931 ms | 1477 ms | 1.87 GB |
| 7000×4800 (33.6 MP) | 131 ms | 42 ms | 99 ms | 51 ms | 419 ms | 189 ms | 933 ms | 2552 ms | 2.29 GB |
| 9504×6336 (60.2 MP) | 209 ms | **14547 ms** | 171 ms | 63 ms | 517 ms | 262 ms | 15771 ms | 5325 ms | 3.44 GB |
| 9504×6336 (fresh copy, repeat) | 222 ms | **14552 ms** | 195 ms | 101 ms | 572 ms | 234 ms | 15879 ms | 5330 ms | 3.58 GB |

The 60.2 MP original-preview stage repeated within 5 ms on a fresh file
identity, an outlier by two orders of magnitude. Spotlight used substantial CPU
on the repeat, so the exact wall time is machine-load sensitive; the stable
stage boundary still warrants a Core Image/Metal trace before changing
downsample code. The full render grows with image area as expected. These
TIFFs do not measure RAW development, JPEG decode, image
switching, continuous slider presentation latency, or batch export throughput.

The Time Profiler trace of a third LZW run put 12,221 of 15,257 running CPU
samples between seconds 2 and 17 directly in `LZWDecode`; the stack was
ImageIO's TIFF decoder servicing Core Image's pixel-block request. A direct
ImageIO 2560 px thumbnail of the same source took 363 ms. The uncompressed
version took 212 ms through that API, versus 2896 ms through the old app
preview path. The 14.5-second wait was caused by full-image decompression in
the original-preview route, not by a Metal film kernel.

## Rejected experiment: large 8-bit flat-file preview

We tried asking ImageIO for a display-size thumbnail when an 8-bit flat image's
long edge exceeds three times the requested preview edge. This only sped up
the Original/compare texture. It caused the later full engine input to decode
the same TIFF again, so the first *developed print* was slower. The change was
reverted in `d286600`; the table preserves the evidence for future work.

| 60.2 MP input | Original preview texture before | After | First original preview estimate (decode + texture) | Complete open before → after | Full render before → after |
|---|---:|---:|---:|---:|---:|
| LZW TIFF | 14552 ms | **422 ms** (34.5×) | 14.77 s → **0.64 s** | 15.88 s → 16.49 s | 5.33 s → 5.60 s |
| Uncompressed TIFF | 2896 ms | **249 ms** (11.6×) | 2.97 s → **0.49 s** | 4.05 s → 4.24 s | 5.16 s → 5.26 s |

The expensive full decode moved to the later engine-frame stage: 14.84 s on
the LZW file and 2.89 s on the uncompressed file. The final print's central
800×450 snapshot region was pixel-identical before and after, so correctness
was not the reason for rejection. The runs are single samples under variable
machine load; the stage shift is much larger than the run-to-run variation
seen in the two LZW baseline runs. Optimize the route to the developed print,
not a stage timer whose output is hidden during cold open.

## Accepted change: bitmap-backed decode for large opaque 8-bit RGB TIFFs

An independent ImageIO full-frame decode plus bitmap draw of the 60.2 MP LZW
TIFF took about 0.26 s. Merely wrapping ImageIO's `CGImage` in a `CIImage`
still spent 14.5 s in the preview render: Core Image re-entered the TIFF strip
provider. Drawing it once into an independent bitmap broke that link. The
optimized route is limited to TIFF, at least 20 MP, 8-bit, opaque RGB. RAW,
high-depth, alpha, CMYK and smaller files retain the prior route.

| Cold input | Open before | Open after | Original preview texture before → after | Full render before → after |
|---|---:|---:|---:|---:|
| 24 MP LZW TIFF | 931 ms | 872 ms | 72 → 50 ms | 1477 → 1255 ms |
| 33.6 MP LZW TIFF | 933 ms | 986 ms | 42 → 58 ms | 2552 → 2188 ms |
| 60.2 MP LZW TIFF | **15628 ms** | **1312 ms** (11.9× faster) | 14500 → 83 ms | 4864 → 4980 ms |

The 60.2 MP final-print snapshot's central 800×450 area was pixel-identical
before and after. A focused test also compares tagged Display P3 TIFFs at all
eight EXIF orientations, both as display textures and linear float engine input.
Peak RSS in the optimized 60.2 MP run was 3.51 GB, within the 3.44–3.58 GB
range of the earlier baseline. Each row is a single run under variable system
load. The 24/33 MP differences are small enough to treat as noise; the large
LZW decompression difference is the measured benefit.

The original-preview cache readback and disk store were separately measured
at 7 + 23 ms on 24 MP and 7 + 35 ms on 60.2 MP. They delay cold open but are
not the dominant 60.2 MP bottleneck, so they were instrumented and left in
place.

## Export UI isolation

The export writer was `@MainActor` from full-resolution texture readback
through ImageIO finalization, preview-page creation and `.cube` formatting.
An isolated ImageIO measurement of a 24 MP 16-bit P3 TIFF put
`CGImageDestinationFinalize` alone at 516 ms. That synchronous call is now
made from a user-initiated detached task for both finished and DI exports;
the finished print's pooled texture lease remains held until the background
writer completes. The output format, colour transform, EXIF and TIFF preview
rules are unchanged. The focused writer test checks TIFF bit depth, profile
and EXIF; existing TIFF/DI writer tests pass (two fixture-dependent package
cases skip in this checkout). This is a main-thread responsiveness fix, not
a measured export-throughput increase. Batch throughput and live window frame
pacing still need instrumented end-to-end measurement.

## Reproduce

The `com.hanze.filmify` / Points of Interest signpost category now marks `Image
Decode`, `Original Preview`, `Engine Frame`, `Interactive Render`, `Export`,
`Export File Write`, `Frame Select UI`, and `Frame Present`. Physical parameter
and output adjustment changes are signpost events. `Frame Present` ends from
Metal's drawable-presented callback, giving a screen-visible boundary rather
than treating command-buffer completion as display. The callback requires a
real window; the snapshot harness cannot validate present timestamps.
Each interval has its own signpost ID, so overlapping
image loads and exports can be distinguished in Instruments. The existing
canvas log gives named open-stage milliseconds and superseded-render records.
Real-window display-link latency still needs a separate capture; no
parameter-event-to-present latency distribution has been reported yet.
The 24 MP `Time Profiler` + `Points of Interest` recording was exported with
`xctrace export --xpath '//table[@schema="os-signpost"]'` and contained paired
begin/end events for `Image Decode`, `Original Preview` and `Engine Frame`.
On a cold 60.2 MP TIFF selection, the synchronous sidecar lookup took 3 ms and
EXIF metadata lookup 2 ms. The same metadata lookup on real Sony RAWs instead
took 154–155 ms on the main actor. It has since moved to a cancelable utility
task; a selection generation prevents late metadata from replacing the next
frame's metadata.

## Real-photo cold-open measurements

These are individual cold runs on copies of the user's photographs in
`/private/tmp/silverphase-real-perf`; the source photos were not modified. The
60.2 MP ARW before/after inputs are copies of the same source with fresh file
identities. The 26 MP ARW is a crop-mode frame from the same camera family,
and the 31.4 MP JPEG is from the supplied collection. The app's `open path`
clock begins after synchronous selection; the selection column is separate.
Each run used the 1600×900 snapshot harness and reached a full native-resolution
render. Times are single samples, not a latency distribution.

| Input | Synchronous selection | Decode | Original texture | Engine frame | Solve | Reprint | Open path | Full render | Peak RSS |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 26 MP ARW, before EXIF change | ≥155 ms | 259 ms | 497 ms | 461 ms | 461 ms | 205 ms | 1925 ms | 1742 ms | 2.41 GB |
| 60.2 MP ARW, before | ≥154 ms | 239 ms | 911 ms | 1089 ms | 684 ms | 249 ms | 3251 ms | 4914 ms | 3.68 GB |
| 60.2 MP ARW, after | **4 ms** | 260 ms | 899 ms | 1015 ms | 733 ms | 251 ms | 3255 ms | 4758 ms | 3.51 GB |
| 31.4 MP JPEG, after | **4 ms** | 78 ms | 54 ms | 153 ms | 513 ms | 228 ms | 1080 ms | 2252 ms | 3.07 GB |

The before selection number is a lower bound because it only adds the logged
EXIF stage, not sidecar, state changes, or view invalidation. The after number
is the complete synchronous `select` interval. EXIF itself still takes 127–166
ms in the background; the optimization removes the UI stall, not the work.
The 60.2 MP final-print snapshot's central 800×450 area was pixel-identical
before and after. The 3251→3255 ms open-path difference is noise and is not
presented as an image-processing speedup. The RAW engine frame at 60.2 MP
(about 1 s), original texture (about 0.9 s), and full render (about 4.8–4.9 s)
are now the measured remaining cold-open costs.

Use a fresh source identity for each cold run, because the disk cache keys on
file identity. Run with a GUI session; the snapshot harness renders the canvas
offscreen, so its times do not measure display-link frame presentation.

```sh
SPEKTRAFILM_CANVAS_LOG=1 /usr/bin/time -l \
  build/DerivedData/Build/Products/Debug/Silverphase.app/Contents/MacOS/Silverphase \
  --snapshot 1600x900 /private/tmp/silverphase-perf/output.png \
  --open /private/tmp/silverphase-perf/source.tif --wait 90
```

The repository's reference RAW fixture tree and Python parity oracle are
absent from this machine; real user RAWs were used for the cold-open measures
above. Do not treat the missing engine parity checks as a pass. Pixel-parity
verification is required before any engine arithmetic or format change.
