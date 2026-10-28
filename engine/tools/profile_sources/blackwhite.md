# Current black-and-white selection (2026-10-12)

Silverphase uses SpektraLab 1.3.3's Tri-X 400, HP5 Plus 400, T-Max 100 and
Acros II profiles, by Hanze Qiu, unchanged in `engine/resources_product/`.
`UPSTREAM.json` pins the source commit and exact file hashes. The upstream notice
is bundled beside the data and in the About panel's licence directory.

Delta 100, FP4 Plus 125, XP2 Super 400 and Fomapan 100 remain our experimental
models, unchanged. Their particle-size priors, shared grain streams and XP2 dye
cloud approximation remain. Upstream films instead use the original grain
particle path, sublayers off, with the upstream strength multipliers (Tri-X
1.70, HP5 1.49, T-Max .74, Acros .64). HP5's published grain reference is for
motion-picture stock; Acros's figure is in Microfine against a D-76 curve.
These limitations are inherited, not new calibrations by Silverphase.

All eight default to Ilford Multigrade IV RC, grade 2 (C=0, M=0, Y=68).
The print rail offers grades 00, 0, 1, 2, 3, 4 and 5 from the unchanged upstream
`paper_grades.json`. Each pack's exposure compensation multiplies Print Exposure.
Older sidecars default to grade 2; the selection is retained while scanning,
using DI, or printing on colour paper, where it has no rendering effect.
Colour filtration shifts are retained but gated off for Multigrade printing.
Copy/paste includes the grade in the Print group.
The upstream pairing was checked for its four films; the other four pairings
remain experimental. The Camera rail also offers the unchanged upstream
Wratten spectral filters, with neutral exposure compensation.
Existing colour-paper cross-process choices remain available.

Old HP5/Tri-X experimental IDs and the synthetic-paper ID resolve to their
upstream replacements in the engine, catalog, and sidecar decoder. Their old
JSON files are kept as historical generator fixtures, excluded from the picker,
and never selected for rendering. The generator no longer overwrites them.
Opening an old edit therefore adopts the replacement's rendering.

## Final integration validation

The missing Apple Metal component was installed for the final integration.
All engine shaders and the canvas shader were freshly compiled. Because Xcode's
build phase still resolves its broken default compiler, the canvas was compiled
separately with the installed toolchain and copied to the built bundles.
`check_math_guard.sh` passed its negative and positive cases. Native B&W,
filter and grade regressions passed again with the rebuilt engine.
Film-edge/date/pair validation is recorded in `film_edge.md`.
Reference Python parity and real-photograph calibration remain unavailable.

## Initial adoption validation (superseded build limitation)

`engine/tests/product_blackwhite.py` passed on the rebuilt native dylib: upstream
file hashes, unchanged local profiles, legacy IDs, neutral print/grain, EDR gate,
exposure ramps and Cineon DI export for all eight films. The alias regression
failed on the old dylib before the implementation. GPU boundary smoke passed.
49 targeted Swift tests passed (ParamsTests, StockListTests, LicensingTests and
FrontendPolicyTests' black-and-white switching case).

The local Xcode installations lack the Metal compiler component. C++ and Swift
were rebuilt; the unchanged engine and canvas metallibs were reused from the
existing build. The app build passed with canvas compilation excluded, then its
existing canvas metallib restored. A fresh Metal build, safe-math negative test,
Python-reference parity, and live GUI/real-film verification were not run.

Paper-grade validation: the grade-5 sidecar regression failed under the fixed
filter-2 implementation before the control was added. `engine/tests/paper_grades.py`
checks all seven grades on eight stocks: ordered midtone contrast, compensated
mid-grey (spread below .04 D), neutral print, and cached negative on reprint.
Hard-grade endpoints can saturate, especially on Fomapan; middle tones verify
that grades 4 and 5 still differ. The grade control adds no engine/kernel changes.
66 targeted Swift tests passed, including SettingsClipboardTests and the grade
sidecar/wire cases. The app was rebuilt with the same unchanged Metal binaries.

## Historical implementation notes (revision 2)

Six camera films: HP5 Plus 400, Tri-X 400, Delta 100, FP4 Plus 125,
XP2 Super 400 and Fomapan 100 Classic. All remain in the experimental tab.
XP2 is a C-41 chromogenic monochrome model; the others are silver-image models.

`blackwhite_samples.json` records the manufacturer publication, process,
download URL, SHA-256 and digitized chart samples. The ILFORD PDFs are
the November 2018 editions archived by 125px, not a claim about later revisions.
Tri-X uses the 400TX 35 mm curve, not 320TXP. Fomapan uses Microphen curve 2.
Revision 2 reads the original embedded raster charts for the four ILFORD stocks,
excluding grid lines and resampling 85 points per curve. Tri-X uses the PDF vector
paths for the 7-minute characteristic curve and D=1 spectral sensitivity; the
first version overestimated parts of its green/red sensitivity. Fomapan retains
coarse hand-estimated knots: its multi-curve figure has not been redigitized.
Digitization still has plotting/axis uncertainty; a small fitting error against
these samples is NOT proof of physical fidelity. PDFs are not redistributed.

ILFORD's tungsten wedge-spectrogram chart and FOMA's uncalibrated relative
sensitivity axis are approximated as linear relative response; Kodak's explicitly
logarithmic axis is treated as log10. Illuminant/spectrogram calibration has not
been recovered. The arbitrary vertical scale is normalized to the existing
engine's Portra-green D55 response convention, not interpreted as absolute ISO.
The principal differences are spectral colour-to-gray weighting
and tone response, not accurate grain, ISO placement or microscopic structure.

All three transport channels carry the same latent response. Their wavelength-
flat density bases each contribute one third of the optical density. This is a
neutral silver/dye proxy, not the measured spectral density of any stock.
Three fitted CDF components are computational sublayers, not three physical
colour emulsion layers. Unmeasured shoulders are bounded priors. Grain-size
priors are creative estimates, not conversions of published RMS granularity.
The existing format/size/amount controls still operate on these priors.
Monochrome channels share the grain stream and particle parameters, and colour
DIR couplers do not run. XP2 adds an approximate dye-cloud blur; silver models
do not. No late-stage RGB desaturation is used for the finished print.

The default `Silverphase Neutral B&W Print (Experimental)` is a synthetic
neutral print response, not a branded paper simulation. It has no measured EDR
map, so the EDR stage is inapplicable. Raw film scans retain negative polarity;
the gradeable intermediate uses the monochrome neutral-axis transform instead
of trying to invert a singular three-colour response matrix. Colour paper
selection is still available as an intentional cross-process experiment.

Rebuild (generator only; runtime is native):

```sh
python3 engine/tools/make_blackwhite_profiles.py  # numpy + scipy
engine/build.sh all
python3 modern_UI/Spektrafilm/Tools/gen-catalog.py
```

To repeat chart extraction from the exact source PDFs (PyMuPDF + numpy + scipy):
`python3 engine/tools/read_blackwhite_charts.py <pdf-directory> --write`.
The directory must contain `hp5.pdf`, `fp4.pdf`, `delta100.pdf`, `xp2.pdf` and
`trix.pdf` with the pinned hashes. Selection guides and axes are pinned in the
script; output is reproducible. Chart-anchor regressions were red on revision 1
(HP5 midtone density underestimated by 0.12–0.14) and green on revision 2.
The generator now bounds both RMS and worst local fitting error, to avoid hiding
toe/shoulder errors in an average. Neither the synthetic print nor the grain
priors is claimed to be calibrated by this chart correction.

Profile containers derive from Andrea Volpato's spektrafilm CC BY-SA 4.0
resources, retaining their licence and attribution. Original profiles and
neutral filter-pack entries are unchanged. None of these approximate models is
manufacturer-approved. Six packaging-style covers were generated with built-in
imagegen using the existing cover template; they are illustrations, not scans or
manufacturer-provided assets. Prompts are recorded in
`modern_UI/design/film-artwork/generated-blackwhite-packaging-manifest.json`.

## Implementation checks (2026-10-04)

The six profiles passed headless tests against the resources in the Debug app:
distinct colour-to-gray responses; neutral print, layered/simple stochastic
grain and raw-negative scan; monotonic exposure ramps and contrast controls;
strip/full-frame equality; DI display and full-resolution Cineon export;
stock switching without stale cache data. The pre-change Portra colour patch
render remains byte-identical. The original 28 profile files and original
neutral filter entries are unchanged. GPU smoke and the safe-math guard passed.
Targeted Swift tests cover the catalog, pairing, preference retention and
licences. No visual inspection or real-film calibration was performed. The
external Python reference environment is unavailable here, so these checks
are not a full numba-reference parity run.

## Wratten lens filters (2026-10-12)

Silverphase adopts `engine/src/core/camera_filters.hpp` byte-for-byte from
SpektraLab commit `01d32a2b767fbdb447bbc3ab156dfa1f2388580c` (Hanze Qiu).
The exposure-weighting block in `film_sensitivity` is also adopted unchanged.
Eight choices, No. 8/11/12/15/21/25/47/58, shape the light before film exposure.
Compensation uses the green-sensitive layer under the profile's reference
illuminant, exactly as upstream; colour film retains the filter's cast.
These are transcribed Kodak B-3 curves, not newly measured filter samples.
The upstream header records the No. 58 factor's 0.67-stop discrepancy with
Tri-X's published daylight factor. Compensation is for reference grey, not
for preserving every subject's brightness.

The camera group saves and copies the choice. A filter edit invalidates the
negative and sensitivity-keyed exposure LUT; a subsequent paper edit reuses
that negative. `engine/tests/camera_filters.py` checks all eight choices on
all eight films, neutral print, reference grey, red/blue response, reset,
unknown-name rejection, and both sides of the cache boundary. The regression
failed with `unknown parameter 'camera_filter'` before the engine change.

Validation: 58 targeted Swift tests (Params, SettingsClipboard, EngineClient)
passed; the native filter, B&W adoption and paper-grade checks passed. The
C++ dylib and application built with unchanged existing Metal libraries,
because this machine lacks the Metal compiler component. The external Python
reference is unavailable, so full reference parity has not been run.
