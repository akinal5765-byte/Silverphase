# Open-source release review

Reviewed 2026-10-31 against main at `89f6de254f6f95def9dadb9e9c3c4fdb3f22c979`
plus the working-tree preparation. The source-release preparation and checks
below are complete. This review records source preparation and validation; it
does not announce a binary release or a repository visibility change. Git history,
original licence texts and the adopted upstream NOTICE are preserved.

## Public source scope

| Area | Current state |
|---|---|
| Code and dependency licensing | COPYING preserves the existing GPL text. Profile CC BY-SA and metal-cpp Apache texts remain unchanged; Colour BSD notice added. [LICENSES.md](../LICENSES.md) maps the component terms. |
| Upstream credit | Hanze Qiu / SpektraLab and Andrea Volpato / spektrafilm remain named in README, About and bundled notices. Adoption revisions and data hashes remain pinned. |
| Material catalog | 33 public materials: 24 films and 9 papers. Self-authored experimental profiles, generators, samples and unused covers are excluded from current public inputs; their historical commits remain. |
| Private local materials | Ordinary maintainer builds add twelve private films from an ignored archive. Public builds explicitly use `SILVERPHASE_LOCAL_MATERIALS=0`. Both hosts strip previous local resources when switching modes; see [local materials](LOCAL-MATERIALS.md). |
| Artwork | 117 candidate visual assets classified and hashed. All 33 public material covers and two workflow cards resolve. Available generation prompts and the [artwork rights boundary](../license/ARTWORK.md) are retained. |
| Scientific data | 71 stored arrays inventoried without rebaking or changing measurements. Original spektrafilm inputs for Hanatos, Canon and KG3 have been pinned and compared; see [data sources](../license/DATA-SOURCES.md). |
| Photographs and examples | Six approved current-window captures include 100% grain and halation on/off. RAW originals, private previews, exports and edit sidecars remain ignored. Inherited UI images are marked historical. See [current examples](../screenshots/current/README.md). |
| Retired research | The research did not land on main. Its local branch and stash were removed; matching remote branch checks were empty. The unrelated theme branch is retained. |
| Sensitive-data review | Gitleaks 8.30.1 scans of main history and existing candidate files reported zero unresolved findings. One exact public preference-value exception preserves all other default detection. |

## Distribution terms and provenance notes

Inherited non-profile engine data follows spektrafilm's published repository
GPL terms. Profiles, derived print LUTs and associated adopted fitted packs
follow upstream CC BY-SA terms. Colour's additional BSD notice is retained.
Original notices and source attribution remain intact; no new standalone grant
is claimed on behalf of an external contributor.

The exact historical Colour bake version and some standalone contributor
notices remain unidentified. These are documented provenance limitations,
not additional permission requests or release gates under this distribution
policy. No message has been sent to an upstream author or manufacturer.

The retained AI packaging-style illustrations have source records and an
explicit third-party rights boundary. The artwork licence covers only
contributor-controlled rights; it does not grant rights to manufacturers'
brands or packaging. Photographs are outside that artwork grant. Current
case screenshots are authorized for project demonstration; this does not
license distribution of RAW originals or general reuse of the photographs.

## Validation

Apple M1 Pro, Xcode 27.1 and its Metal Toolchain, selected through DEVELOPER_DIR.
No new performance benchmark or independent physical oracle is claimed.

| Check | Result |
|---|---|
| Engine `build.sh all`, GPU smoke and math guard | Passed. Shipped Metal uses safe/precise float32; GPU smoke reported zero failures. |
| Native B&W, camera filters and paper grades | Passed against the retained product profiles. |
| macOS actual application | Local and public modes built; reused build directories correctly switched between 45 and 33 profiles. |
| Full local desktop suite | 542 tests: 495 passed, 47 skipped, zero failures. Includes conditional material-browser and bundled-artwork checks. |
| Public StockListTests / ParamsTests / LicensingTests | 54 passed, zero skips or failures. |
| Fixed real-photo cases | 16 selected tests passed, zero skips or failures, including ten actual full-size JPEG exports and canvas/RAW DI checks. |
| Private material smoke | All twelve private films rendered through the native engine. No assertion of real-film accuracy. |
| iOS simulator application | Both modes built; actual public package contained 33 profiles and no LocalMaterials directory. |
| iPhone Duo installation | Current local device build signed, installed and launched; a surviving Silverphase process was confirmed. No fresh gesture, Photos-permission or full-resolution export acceptance is inferred. |
| Notices and sources | Ten canonical/bundled notice files match. Product adoption hashes, data/media inventories, both project generators, shell syntax and diff whitespace checks passed. |

The full-suite skips remain explicit partial coverage:

| Missing input / opt-in gate | Skips |
|---|---:|
| Historical A7 III RAW | 23 |
| Historical 1 MP smoke image | 12 |
| Historical Nikon Z7 II image | 3 |
| Historical A7R V RAW | 1 |
| Selected historical real-photo gate not configured | 4 |
| Explicit temporary device-colour RAW not supplied | 1 |
| Opt-in batch/export/stress benchmarks | 3 |

Detailed evidence: [fixed cases](../performance/VALIDATION-CASES-2026-10-31.md),
[public material cleanup](../performance/VALIDATION-MATERIAL-RETIREMENT-2026-10-31.md)
and [local/public overlay validation](../performance/VALIDATION-LOCAL-MATERIALS-2026-10-31.md).
Existing C-linkage warnings and Xcode script-phase/ad-hoc signing notes remain;
they were not hidden or counted as failures.

## Reproducible publication checks

```sh
modern_UI/Spektrafilm/Tools/bundle-licenses.sh
python3 tools/check-open-source.py
python3 modern_UI/Spektrafilm/Tools/gen-project.py --check
python3 ios/Silverphase/Tools/gen-project.py --check
git diff --check
```

The source checker verifies notice equality, product hashes, credits, inventories,
cover existence and exclusion of retired research references from candidate
source. It is not a legal certification. Review actual file changes before
accepting regenerated inventory hashes.

For a local secrets review, use official Gitleaks 8.30.1 with its verified
release checksum:

```sh
python3 tools/check-release-secrets.py \
  --gitleaks /path/to/gitleaks \
  --output /tmp/new-silverphase-release-scan
```

The review's official Darwin arm64 archive SHA-256 was
`b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5`.
The tool scans main history and a temporary copy of existing nonignored
candidate source. Reports are redacted, remain outside Git and are not uploaded.
The scan excludes ignored files, reflogs, unreachable objects and unrelated
branches; it cannot prove the absence of every secret. Branch/stash deletion
is not secure erasure of unreachable local objects.

## Publishing source and binaries

Review and commit the prepared source only when requested, then publish the
reviewed revision. Publish tracked source, rather than uploading the whole
working directory, `.git`, private archives or raw audit reports.

For binaries produced on the maintainer's machine, set
`SILVERPHASE_LOCAL_MATERIALS=0` for both resource preparation and Xcode build.
Provide the corresponding source for that exact binary revision, build scripts
and bundled notices through a method permitted by GPL section 6. A generic
repository URL alone does not establish exact-source availability. Signing,
notarization and release-specific device acceptance are separate binary-release
steps; they do not prevent publishing the prepared source.

Repository visibility changes and binary releases are separate publication
actions. Preserve this validation scope when describing a release.
