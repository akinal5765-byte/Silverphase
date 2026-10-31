# Material retirement validation — 2026-10-31

The current release tree excludes self-authored approximation profiles. This
cleanup preserves Git history, the original licence texts and upstream credits.
No commit, push or history rewrite is part of the cleanup.

## Material scope

Removed eight selectable colour approximations: PRO160NS, PRO160C, Superia
Reala 100, Natura 1600, Pro Image 100, Elite Color 200, Optima II 200 and
Portrait XPS 160. Removed four selectable B&W approximations: Delta 100,
FP4 Plus 125, XP2 Super 400 and Fomapan 100. Three superseded experimental
profile files for Tri-X, HP5 and synthetic neutral paper were also removed.

The public merged catalog has 33 materials: 24 films and 9 papers. Its
28 base profiles and the five adopted SpektraLab B&W profiles are unchanged.
The latter's hashes and NOTICE remain pinned in
`engine/resources_product/UPSTREAM.json`. Retention does not imply that every
material is an independently validated physical reproduction.

Associated generators, chart samples, generator-specific tests, calibration
entries and twelve unused cover images were removed. The macOS experiment
category is absent in public builds; maintainer builds can package the ignored
local archive and display its experimental films. iOS uses the same optional
overlay. See `docs/LOCAL-MATERIALS.md`. Existing
HP5 and Tri-X cover images were renamed to their adopted material IDs.

Old Tri-X, HP5 and neutral-paper IDs retain their established migration to the
adopted materials. Other experimental material IDs require the local overlay; without it they
fail with a missing-profile error; they are not substituted with donor stocks and saved edits are not
rewritten. Existing screenshots are dated illustrations; browser options may
show the earlier catalog.

## Validation

- All 28 retained base profile files match the pre-cleanup Git revision
  byte-for-byte. Remaining base neutral-filter entries compare equal after
  removing experimental keys; product profile and fitted-pack hashes match
  the unchanged adoption record.
- Native `product_blackwhite.py`, `camera_filters.py` and `paper_grades.py`
  passed. These include native rendering, missing retired IDs, the established
  migration aliases and supported paper grades. They are internal checks,
  not an independent real-film oracle.
- GPU smoke: zero failures. Safe-math guard accepts the shipped library and
  rejects the deliberately fast-math diagnostic library.
- Source-release checks, both project generators and diff whitespace checks
  passed. All 33 material covers and two workflow cards resolve; 117 current
  visual assets and 71 stored arrays are inventoried.

- Full desktop suite: 541 tests, 494 passed, 47 skipped, zero failures.
  The skips retain the fixture and opt-in limitations listed in
  `docs/OPEN-SOURCE-RELEASE.md`. The first cleanup run exposed an outdated
  expected catalog count of 45 in the cover test; after updating it to 33,
  the complete rerun passed.
- Actual macOS Debug application and iOS simulator Debug application builds
  passed using Xcode 27.1 on Apple M1 Pro. Both final application bundles
  contain exactly 33 profiles and 33 catalog entries, no retired experimental
  profile/cover files, and ten notices identical to their final source copies.
  No device validation is inferred.
- Final Gitleaks 8.30.1 review: main history and 671 existing candidate files
  each reported zero findings. Local report:
  `/tmp/silverphase-release-secrets-material-retirement/summary.json`.
  Ignored private files and unreachable Git objects are outside that scope.

Local logs: `/tmp/silverphase-upstream-audit/desktop-retirement-tests-final.log`,
`native-retirement.log`, `math-retirement.log`, `mac-app-retirement-build-final.log`
and `ios-retirement-build-final.log` (same directory).
No new UI interaction, photograph adjustment or performance benchmark is
claimed by this cleanup.
