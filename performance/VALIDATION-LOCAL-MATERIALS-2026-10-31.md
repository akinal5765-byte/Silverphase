# Local material overlay validation — 2026-10-31

Apple M1 Pro, Xcode 27.1; current C++/Metal engine and the existing external
NumPy interpreter for native test driving. No Python reference runtime was
installed. No performance benchmark or new live-window visual audit is claimed.

## Result

The tracked catalog and base/product data remain public-only (33 materials).
Normal builds in the maintainer checkout add 12 ignored experimental films,
with catalog entries, native profiles, neutral-filter entries and cover images.
Both material browsers expose the local experiment category only when those
materials are bundled. No private profile, cover, generator or chart sample was
added to tracked product inputs.

`SILVERPHASE_LOCAL_MATERIALS=0` selects public resources. Both actual macOS and
iOS application builds were switched from local to public using their existing
build directories: each public app contained exactly 33 profiles and no
`LocalMaterials/` directory. Local builds contained 45 profiles, twelve local
catalog entries and twelve local covers. The final application builds were
returned to local mode. The tracked catalog stayed at 33 throughout.

## Checks

- Full local desktop suite: 542 tests, 495 passed, 47 skipped, zero failures.
  Skips are the existing missing historical fixtures and opt-in gates documented
  in `docs/OPEN-SOURCE-RELEASE.md`; coverage remains partial for those inputs.
- Public-mode StockListTests, ParamsTests and LicensingTests: 54 passed, no
  skips or failures. Browser tests cover the conditional experiment category;
  actual bundled artwork is decoded in the local full-suite run.
- All twelve local films rendered through the native engine with their bundled
  resources. This is a load/render smoke test, not physical validation of the
  experimental materials.
- An isolated local → public → local staging check passed, including removal
  of experimental profile files, filter entries, local catalog and covers.
- Actual macOS and iOS simulator Debug application builds passed in both modes.
  This does not establish iOS device gestures, permissions or full-size export.

Local logs are under `/tmp/silverphase-upstream-audit/`: `local-overlay-tests.log`,
`public-overlay-tests.log`, `local-overlay-native.log`, and the corresponding
`local-overlay-*` / `public-overlay-*` application build logs. No commit, push,
publication or history rewrite was performed.
