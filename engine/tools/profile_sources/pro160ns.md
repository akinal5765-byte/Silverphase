# PRO160NS experimental profile, revision 2

## Current approximation (revision 2)

The original reconstruction failed colour plausibility checks. Revision 2
retains the reliable PRO400H dye spectra, mask/base absorption, shoulder and
Hanatos calibration as one coherent basis. It does **not** invert the printed
Status-M curves into three dyes or force-fit a neutral spectrum to their shapes.

The manufacturer's relative spectral sensitivity contributes 20% of a **linear
sensitivity mixture**, normalized per channel to the base's D55 response.
The arbitrary vertical chart zero therefore cannot change exposure placement.
The printed green midtone slope contributes one quarter of its relative
difference from the base; the resulting common contrast multiplier is bounded
to 0.9...1.1. CDF components are inherited from the base with their exposure
axes scaled consistently. Grain and unmeasured shoulders remain base priors.
The original source spectra are retained in the samples for research but do
not reconstruct dyes. These weights are conservative creative policy, not
measured characteristics of PRO160NS. Inherited colour calibration is explicitly
not a new stock-specific calibration.

Colour-paper filter packs are rebalanced. `experimental_color_quality.py`
checks the full -4...+4 EV neutral ramp with EDR on/off, added shadow cast,
bright neutrals, contrast retention, skin-like and saturated patches relative
to the stable basis. This establishes plausibility, **not real-film fidelity**.
The existing stock ID and saved parameters remain, but photographs using this
experimental stock deliberately receive the revised look after restarting.

`build_revision1()` remains only for reproducing historical numerical results;
the CLI and shipped profiles exclusively use `build()` (revision 2).
The sections below record revision 1 and its limitations; they are not the
current reconstruction procedure.

## Historical revision 1

This is a Silverphase approximation, not a Fujifilm-endorsed profile or a
measured reproduction. UI name: **Fujifilm PRO160NS (Experimental)**.
ID: `fujifilm_pro_160ns_experimental`. The separate ID prevents a future
measured profile from silently changing saved photographs.

## Sources and attribution

- Fujifilm publication **163AR109A (04.7-FG)**, page 8, figures 20/21/23:
  https://asset.fujifilm.com/www/jp/files/2024-04/6b75b1c1cb4253623fb2cd7a56ff7443/datasheet_pro160ns_01.pdf
- Andrea Volpato's `fujifilm_pro_400h.json` from spektrafilm, CC BY-SA 4.0:
  https://github.com/andreavolpato/spektrafilm
- Modified by Silverphase / akinal5765-byte; derivative remains CC BY-SA 4.0.
  Original licence and attribution are preserved in profile metadata and the
  bundled Profiles-and-LUTs-CHANGELOG.txt. The manufacturer's PDF is not bundled.

## What was extracted

The manufacturer PDF has cubic Bezier plots. `make_pro160ns.py --pdf <path>`
samples their vector paths, maps graph coordinates to exposure/density or
wavelength/relative log sensitivity, and saves `pro160ns_samples.json` with
the PDF SHA-256. RGB order is explicitly reversed from the printed B/G/R
paths. Characteristic samples retain base-plus-fog; the effective model
subtracts the measured channel minima before fitting three Gaussian CDFs.
The fourth sensitivity curve is recorded, but not treated as a fourth dye.

## Assumptions that matter

1. Independent cyan/magenta/yellow absorption is not supplied. The donor
   PRO400H dye shapes are a prior. A common wavelength correction matches
   the PRO160NS midscale-minus-minimum spectrum, without uniquely identifying
   the three dyes. This is an underdetermined reconstruction.
2. Characteristic curves are Status-M measurements. Revision 1 uses a
   650/550/450 nm narrow-band leakage matrix, **not** a full Status-M inverse.
   The reported fit errors are for effective density under that proxy, not
   evidence of colour accuracy against real film or exact Status-M matching.
3. The plotted exposure interval ends before saturation. The shoulder outside
   that interval is bounded by a donor-informed prior. No published maximum
   density or exact highlight latitude is claimed.
4. The fourth sensitized layer is not explicitly simulated. Its imagewise
   colour correction cannot be recovered from these neutral-exposure plots.
5. Relative exposure zero is placed at green effective density 0.7. ISO 160
   is display metadata, not an absolute sensitometric calibration. Sensitivity
   channels are white-normalized using the engine's baked D55 spectrum.
6. Donor Hanatos adaptation window/surface are deliberately NOT copied: they
   were fitted for a different stock. UV/IR sensitivity tails are extrapolated
   downward; unmeasured dye/base wavelengths remain null, as in upstream data.
7. Grain, couplers, scattering and antihalation use existing generic negative
   film settings. Three CDF populations are a mathematical decomposition,
   not measured physical sublayers. RMS granularity/MTF are not newly calibrated.
8. Neutral TH-KG3 filter packs are fitted through the native engine for all
   eight papers at a scene-linear grey of 0.184. This is white balance, not a
   complete colour target calibration. Existing stock profiles/packs stay intact.
9. Digital Intermediate export still uses the existing paper LUTs, baked
   against their original paired stocks (PRO400H for Crystal Archive). The
   engine returns its mismatched-film warning; no PRO160NS-specific LUT has
   been calibrated. Prefer the exact spectral normal print path for first tests.

## Reproduce and test

Offline regeneration requires Python with numpy/scipy, using saved samples:

```sh
python engine/tools/make_pro160ns.py
python engine/tools/make_pro160ns.py --calibrate
python modern_UI/Spektrafilm/Tools/gen-catalog.py
PYTHONPATH=engine/tests python engine/tests/pro160ns.py
```

`--calibrate` needs an up-to-date native dylib and Metal access. PDF extraction
additionally requires PyMuPDF. Neither Python nor these libraries are runtime
or normal application-build dependencies. Do not rebake or rewrite existing
profiles to accommodate this experiment.

Next scientific gate: a full Status-M inverse and independent validation with
colour targets/skin spectra or reliably characterized real negatives. Passing
headless engine tests alone does not establish a faithful PRO160NS look.
