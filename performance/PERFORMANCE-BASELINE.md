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

## Reproduce

Use a fresh source identity for each cold run, because the disk cache keys on
file identity. Run with a GUI session; the snapshot harness renders the canvas
offscreen, so its times do not measure display-link frame presentation.

```sh
SPEKTRAFILM_CANVAS_LOG=1 /usr/bin/time -l \
  modern_UI/Spektrafilm/build/DerivedData/Build/Products/Debug/Silverphase.app/Contents/MacOS/Silverphase \
  --snapshot 1600x900 /private/tmp/silverphase-perf/output.png \
  --open /private/tmp/silverphase-perf/source.tif --wait 90
```

The reference RAW fixture tree and Python parity oracle are absent from this
checkout. Do not treat synthetic TIFF numbers as RAW numbers or the missing
parity checks as a pass. Pixel-parity verification is required before any
engine arithmetic or format change.
