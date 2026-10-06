# Experimental black-and-white models

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
