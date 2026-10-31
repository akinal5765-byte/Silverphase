# Runtime data sources and licence evidence

Reviewed 2026-10-31. `data-inventory.json` records the current constants file and
each stored array's SHA-256, shape, type and input family. The inventory is
standard-library-only and does not rebuild the retired Python environment or
change measured arrays. `tools/inventory-release-data.py --check` checks drift.

## Distribution policy

Silverphase follows the original repositories' published open-source terms:
inherited non-profile engine data follows spektrafilm's repository GPL terms;
film/paper profiles, their derived LUTs and adopted fitted grade/filter packs
follow the upstream CC BY-SA 4.0 profile distribution. Colour's additional
BSD-3-Clause notice is retained. Original notices, attribution and change
records remain intact; no new licence is assigned to an external contributor
on the basis of a source URL alone.

The source-history limitations recorded below remain provenance notes, not
additional requests for permission or release gates. This policy follows
upstream distribution and does not claim a newly obtained standalone grant.

## What the producer actually reads

| Stored family | Input documented by `engine/tools/bake_resources.py` | Evidence and scope |
|---|---|---|
| `colour/*` | All arrays in the upstream `model/colour_baked.py` NPZ | Colour's datasets include colour spaces, observer/illuminant data, chromatic-adaptation matrices and the Mallett/Yuksel basis. The historical bake does not record its exact Colour package version or NPZ source revision. Preserve the BSD notice below; matching every array to an exact historical source remains open. |
| `hanatos/spectra_lut` | `spektrafilm/data/luts/spectral_upsampling/irradiance_xy_tc.npy` | The spektrafilm source credits hanatos for coefficients/sample code and computes spectra from them. This is not a film-profile array. The stored float16 payload exactly matches the original repository at the pinned revision below. A separate coefficient-origin licence has not been established; do not describe it as public domain or as cleared by the profile licence. |
| `filters/kg3`, `filters/lens_canon` | `model/color_filters.py` filter objects, loaded from upstream CSV data | SCHOTT KG3 heat-filter and generic Canon-lens transmission measurements. Names and code paths identify the sources, but are not standalone redistribution grants for the original measurements. Exact CSV inputs have now been pinned and compared below; separate measurement-reuse evidence remains open. |
| `filters/dichroic_custom_ref` | Analytic custom dichroic-filter model in spektrafilm | Computed reference values from Andrea Volpato's model; preserve GPL attribution for the implementation. The custom model is distinguished from manufacturer measured arrays. |
| `print_lut/*`, `print_lut_axes/*` | Upstream print-preview NPZ files and metadata | Derivatives of Andrea Volpato's CC BY-SA profiles. Preserve `SPEKTRAFILM_LICENSE.txt` and the bundled profile/LUT changelog. |
| `spectral/wavelengths` | Upstream `SPECTRAL_SHAPE.wavelengths` | Numeric sampling grid, rather than a measured material profile. |

The table identifies the committed producer's input families. The comparisons
below establish particular source matches; they do not reconstruct the entire
historical bake environment.

## Verified Colour licence evidence

Colour Developers publish their library and the inspected dataset modules under
**BSD-3-Clause**. The following primary-source files were inspected:

- [Colour v0.4.6 LICENSE](https://github.com/colour-science/colour/blob/v0.4.6/LICENSE),
  Git blob `a70f873f32fd602019091d4fd9096a4894ac50fc`.
- [Mallett/Yuksel dataset module](https://github.com/colour-science/colour/blob/v0.4.6/colour/recovery/datasets/mallett2019.py),
  Git blob `9effc2a89d3521d0ffe97187bc64f367a2f21d0c`, explicitly BSD-3-Clause.
- [Observer dataset module](https://github.com/colour-science/colour/blob/v0.4.6/colour/colorimetry/datasets/cmfs.py),
  Git blob `79c78fabc6bfed74acdbe6aede922c57f0c3681c`, explicitly BSD-3-Clause,
  retaining its scientific source references.

The full notice is copied unchanged to `Colour-BSD-3-Clause.txt` and bundled in
both apps. This fixes a missing third-party notice; **v0.4.6 is the inspected
licence-evidence version, not a claim about the unidentified historical bake**.
The dataset references do not grant rights to republish the source articles or
standards documents. Credit Mallett and Yuksel's 2019 spectral-primary work when
describing that basis; credit Johannes Hanika / hanatos for the upsampling work.

## Additional origin evidence

The original [spektrafilm repository](https://github.com/andreavolpato/spektrafilm)
was inspected at commit `3bb2c2d2801ff68b92019cf1dbcbb133d60832bc`.
Its package metadata declares GPLv3 and includes `data/**/*`; its profile
exception covers original film/paper profiles and their direct derivatives.
That exception is not a blanket licence for third-party measurement tables.

[upstream-data-match.json](upstream-data-match.json) records exact paths, Git
blob IDs, SHA-256 hashes and comparison methods:

- `irradiance_xy_tc.npy`: its float16 payload exactly matches the stored
  `hanatos/spectra_lut` bytes. The upstream update is commit
  `98b1cdefd78e913ee9841c4cf430f8c46cad479f` (2025-03-05). Upstream credits
  hanatos for the supplied coefficients and sample code. No separate licence
  appears in the inspected coefficient-table footer.
- Canon transmission CSV: the original loader's wavelength selection,
  percentage conversion and Akima interpolation reproduce the stored array
  byte-for-byte. The data was introduced in commit
  `29d5efa994bfcc0dde3209794ad4a15d23d51807` (2025-03-17). Its adjacent info
  file points to Lensrentals' [2018 spectrometry article](https://www.lensrentals.com/blog/2018/03/a-geek-of-many-colors-adventures-in-spectrometry/),
  credited to Roger Cicala, Brandon Dube and Aaron Closz.
- KG3 CSV: the same upstream loader reproduces the stored array to a maximum
  absolute difference of `1.1102230246251565e-16`; this is not a byte match.
  It was introduced in commit `e9710c27e0b1b3df5324d64e8dbc1e0ce320ea92`
  (2025-03-11). Its adjacent info file points to Newport's
  [heat-absorbing glass filters](https://www.newport.com/f/heat-absorbing-glass-filters).

These checks used an existing external NumPy 1.23.3 / SciPy 1.10.1 interpreter,
without installing spektrafilm or recreating its retired rendering environment.
They compare data provenance, not rendering accuracy. The source matches close
input-identification gaps; they do not establish a separate redistribution
grant from the original measurement or coefficient contributors.

The [vkdt README](https://github.com/hanatos/vkdt/blob/master/readme.md) states
BSD-2-Clause by default with explicitly marked exceptions; its BSD text credits
Johannes Hanika (2019). That does not establish that the particular externally
supplied `hanatos_irradiance_xy_coeffs_250304.lut` used by spektrafilm came from a
specific vkdt revision or is covered by that default. Preserve the attribution
and do not silently resolve this missing link by assigning the whole spectra
array a licence from an unrelated file.

## Product B&W profiles and fitted packs

`engine/resources_product/UPSTREAM.json` pins the adoption at SpektraLab commit
`01d32a2b767fbdb447bbc3ab156dfa1f2388580c`. Its README's licensing table explicitly
assigns film/paper profiles to CC BY-SA 4.0, with Hanze Qiu credited for the B&W
profiles. The original NOTICE describes `paper_grades.json` and
`neutral_print_filters.json` as fitted on engine renders from those profiles.
Keep this evidence and the NOTICE unchanged. The README does not separately
name the fitted packs; Silverphase distributes them with the associated profiles under the same
upstream CC BY-SA terms, preserving that derivation record and the unmodified
NOTICE rather than presenting a new grant from Hanze Qiu.

No new permission request has been sent to upstream authors. Exact historical
bake versions and missing standalone contributor notices remain recorded as
source-history limitations; distribution follows the upstream policy above.
