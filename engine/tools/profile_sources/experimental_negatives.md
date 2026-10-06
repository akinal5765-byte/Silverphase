# Experimental negatives, revision 2

## Current method

All eight experimental colour negatives, including PRO160NS, now use the
constrained approximation described in [pro160ns.md](pro160ns.md). The stable
base dye spectra, mask/base absorption, maximum density and Hanatos colour
calibration stay together. Manufacturer relative sensitivity contributes 20%
after per-channel D55 normalization; the printed green midtone slope produces
a common contrast change bounded to +/-10%. These are creative approximation
weights, not recovered physical properties of the named films. No Status-M
inverse or wavelength-wise dye rescaling is performed in revision 2.

All eight colour-paper filter packs per film were regenerated, without changing
any original filter entries or B&W profiles. Film IDs and saved parameter values
stay unchanged; existing photographs intentionally receive a revised look.

Run `engine/tests/experimental_color_quality.py` alongside the existing native
contracts. It checks whole neutral ramps and colour patches with EDR on/off,
using the stable base film as a plausibility control rather than as ground truth
for the new film. Real-film colour accuracy still requires independent reference
negatives or characterized colour-target photographs. No UI visual inspection
or manufacturer endorsement is claimed.

The remaining sections retain the revision-1 extraction record, source URLs
and limitations. Statements about dye reconstruction and removed adaptation
below describe **historical revision 1**, superseded by the method above.

## Historical revision 1 and sources

Silverphase approximations, not manufacturer-endorsed or measured reproductions.
All UI names include **(Experimental)**. Distinct IDs keep saved edits stable.

| ID | Manufacturer publication | Donor dye basis |
| --- | --- | --- |
| `kodak_pro_image_100_experimental` | Kodak E-4L, July 1997, page 3 | spektrafilm Gold 200 |
| `fujifilm_superia_reala_100_experimental` | Fujifilm AF3-967E, EIGI-00.12-HB, page 4 | spektrafilm PRO400H |
| `fujifilm_natura_1600_experimental` | Fujifilm 013AR313B, 06.4-FP, page 4 | spektrafilm PRO400H |
| `agfa_portrait_xps_160_experimental` | Agfa Technical Data PF, 09/1998 first edition, page 8 | spektrafilm Portra 160 |
| `agfa_optima_ii_200_experimental` | Agfa Technical Data PF, 09/1998 first edition, page 7 | spektrafilm Gold 200 |
| `kodak_elite_color_200_experimental` | Kodak E-4039, July 2006, page 7 | spektrafilm Gold 200 |
| `fujifilm_pro_160c_experimental` | Fujifilm Professional Film Data Guide, 2005, printed page 59 / PDF page 29 | spektrafilm PRO400H |

Source URLs and PDF SHA-256 hashes are in each `*_samples.json` and generated
profile. Pro Image and REALA use archived copies of original manufacturer
publications; NATURA uses Fujifilm's hosted PDF. REALA is the historic SUPERIA
REALA, **not Reala ACE**. These sheets describe their stated revisions, not all
later manufacturing batches. PDFs and their artwork are not distributed.

Agfa and Elite also use archived original manufacturer documents. The Agfa
names deliberately retain **XPS** and **II** to distinguish their 1998 revision
from later products. Elite **Color** is a negative, not Elite Chrome. PRO 160C
is extracted from the right-hand page of the two-page guide spread, not 160S.
Donor choice is an explicitly approximate dye-separation basis, not a claim
that Agfa and Kodak emulsions share chemistry or measured colour response.

Modified by Silverphase / akinal5765-byte. Derived dye bases remain **CC BY-SA
4.0**, retaining Andrea Volpato's metadata and bundled attribution/changelog.
Canonical donor source: https://github.com/andreavolpato/spektrafilm

## Reconstruction and limits

Each stock gets its own vector-extracted RGB characteristic curves, spectral
sensitivity, base-plus-fog and midscale neutral absorption. Kodak uses vector
polylines; Fuji uses Beziers. RGB ordering and graph ticks are publication-
specific, with count checks preventing silent use of different PDF layouts.
REALA has a tiny vector join overlap (<0.1 nm), sorted before interpolation.
Fuji fourth-layer plots are preserved in samples, **not** modelled as a fourth
dye. Samples are numerical reconstructions of plotted manufacturer data.

The shared fitting algorithm and scientific limits are in [pro160ns.md](pro160ns.md):

- Aggregate neutral spectra cannot uniquely identify CMY dyes. Donor separation
  is an explicit prior, not evidence the two emulsions share chemistry.
- Status-M density inversion uses a 650/550/450 nm narrow-band proxy. Fit RMS
  is an internal effective-density fit, **not** real-film colour accuracy.
- Unmeasured shoulder uses a bounded prior. No exact highlight latitude claim.
- Three CDF populations are mathematical sublayers, not measured emulsion layers.
- Sensitivity uses D55 white normalization; no donor Hanatos correction is reused.
- Exposure zero is green effective density 0.7. ISO/EI labels do not multiply
  exposure, grain or halation. Pro Image's sheet specifies **EI 100**.
- Grain, couplers, halation and scattering retain generic negative defaults.
  NATURA's high speed does not make its grain stock-calibrated. MTF/granularity
  are not converted into invented grain sizes.
- Eight TH-KG3 print filter packs per stock are fitted with the native engine
  at 0.184 scene-linear gray. This is one-point neutral balance, not a colour
  target calibration. No existing stocks or their filter rows are modified.
- Existing Digital Intermediate paper LUTs have different paired film dyes;
  their mismatch warning remains. Prefer normal spectral print rendering for
  initial evaluation; no stock-specific DI LUT calibration is claimed.

## Reproduce

```sh
python engine/tools/make_negative_profiles.py proimage100
python engine/tools/make_negative_profiles.py reala100
python engine/tools/make_negative_profiles.py natura1600
python engine/tools/make_negative_profiles.py portrait160
python engine/tools/make_negative_profiles.py optima200
python engine/tools/make_negative_profiles.py elite200
python engine/tools/make_negative_profiles.py pro160c
python engine/tools/make_negative_profiles.py natura1600 --calibrate
python modern_UI/Spektrafilm/Tools/gen-catalog.py
python engine/tests/experimental_negatives.py
```

Each generator also accepts `--pdf <file>` to re-extract the pinned publication
(requires PyMuPDF); regeneration from checked-in samples only needs numpy/scipy.
`--calibrate` requires native dylib/Metal access. No Python runtime dependency.
Tests are structural/native checks, not visual verification or measured-film QA.
