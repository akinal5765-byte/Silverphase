# Contributing to Silverphase

Silverphase is an independent derivative of Hanze Qiu's SpektraLab and Andrea
Volpato's spektrafilm. Start with the [README](README.en.md),
[documentation index](docs/README.md), and [working rules](AGENTS.md).

Open an issue or pull request in
[Silverphase](https://github.com/akinal5765-byte/Silverphase). Describe the user
problem, resulting behaviour and validation, including failures and skips.
Use small changes with a clear purpose. Submit contributions to Silverphase;
the `upstream` remote points to the original SpektraLab project and is read-only
in this workflow.

## Licensing contributions

Contribute only material you have the right to submit. Code contributions use
GPL-3.0-or-later; derivatives of the CC BY-SA profiles/LUTs retain CC BY-SA 4.0.
Preserve existing notices and credit, and document source, revision, licence,
modifications and reproducible processing for adopted code or data. A pull
request does not transfer copyright or grant trademark rights. See
[LICENSES.md](LICENSES.md) for the component boundaries.

Do not submit private photos, edit sidecars, credentials, signing profiles,
proprietary reference datasets or packaging artwork without redistribution
permission. Prefer synthetic ramps and patches for bug reports; describe any
external fixture requirement without uploading the private fixture.

## Implementation and validation

Use SwiftUI/Observation/actors and the shared C++20/Metal engine. The supported
floors are macOS 15 and iOS 18 on Apple silicon. Build commands are in the
platform guides; select Xcode through `DEVELOPER_DIR`, not global settings.

The parameter schema is `engine/src/core/params.cpp`; the public ABI is
`engine/include/spektrafilm/spk_engine.h`. Boundary changes require matching
Swift mappings, both hosts and native tests. Follow the current
[API](API-SPEC-callable-render-service.md) and
[contract](CONTRACT-frontend-backend.md). Historical service documents do not
specify a supported runtime Python protocol.

Run focused checks for the change. After adding or removing source files,
regenerate the relevant project and run both project generators with `--check`.
Use the full desktop suite at integration boundaries and the engine checks
specified by AGENTS.md when changing rendering. Report skipped cases explicitly;
a build does not validate gestures, device export or visual appearance.

Before publication, run `python3 tools/check-open-source.py`. It verifies the
licence copies, source links, stored data hashes and visual inventory. Use
`python3 tools/check-release-secrets.py --gitleaks /path/to/gitleaks --output /tmp/new-release-audit`
with Gitleaks 8.30.1 to scan main history and candidate source locally. Reports
are redacted and remain outside Git; ignored private folders are never staged
for this scan. The single exact preference-value exception in `.gitleaks.toml`
was reviewed as non-secret; do not exempt whole files or rules.

Before a release, follow [OPEN-SOURCE-RELEASE.md](docs/OPEN-SOURCE-RELEASE.md).
