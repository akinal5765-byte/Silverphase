# iOS App Store preparation

Status: preparation, 2026-11-03. First release is completely free, targeting global
availability including China mainland. App Store Connect record **6829987567**
has been created with SKU `silverphase-ios`, bundle ID `com.silverphase.editor`
and Simplified Chinese as its primary language. No build upload or review
submission has been performed.
Current product version is 1.1.1 (3); deployment floor is iOS/iPadOS 18.

Chinese promotional text, description, keywords, version 1.1.1, copyright and
review notes were saved in App Store Connect. Login is not required; release is
set to manual after approval. Subtitle is “胶片、显影与印相模拟” and primary category
is Photo & Video. The age questionnaire calculates 4+ for the current editor.
No paid advertising is included; the Layerlight entry is an unpaid own-app link.

[Privacy policy](../docs/PRIVACY.md) and [support page](../docs/SUPPORT.md) are
prepared in Chinese and English. Settings/About link to their public GitHub
`blob/main/docs/` URLs; verify publication before upload and enter the same URLs
in App Store Connect. The user authorised committing and pushing this release
preparation to origin/main on 2026-11-03.
The account currently reports an updated Apple Developer Program agreement;
the user chose to handle it later. No agreement was accepted by the agent.
China mainland ICP applicability remains unresolved: the app processes photos
locally, but exemption has not been confirmed. No number is supplied or reused
from Layerlight.

Free pricing was saved for all 175 storefronts. Availability is configured for
all 175 countries/regions, including China mainland, subject to Apple's local
requirements and review. iOS-on-Mac and Vision Pro availability are disabled;
this submission targets iPhone/iPad.

The user requests checking whether the local-only editor can be distributed in
China mainland without an ICP filing. If Apple requires clarification, use the
following factual draft rather than asserting that an exemption has been granted:

> Silverphase is an on-device photo editor. Photo import, film/print simulation,
> editing and export operate locally without a developer-operated backend,
> account registration, hosted content feed, user-to-user messaging or automatic
> photo upload. System Photos/Files may access the user's chosen cloud originals
> or destinations. Settings/About include an optional link that opens the
> developer's separate Layerlight App Store listing. Please confirm whether this
> functionality requires an ICP filing for China mainland distribution and, if
> applicable, the process for demonstrating that the app falls outside the filing
> requirement.

Settings and About include an optional Layerlight promotion linking directly to
App Store ID 6756343255, without tracking parameters or an advertising SDK. The
card includes the owner-supplied production app icon and describes ordinary-photo
HDR conversion and photographic-style editing in the iOS Photos app. The copy
discloses supported-device/system requirements and that some features require Pro. This is a related-app
recommendation, not a requirement for using Silverphase. Apple permits promotion
of the developer's own apps under review guideline 3.2.1(i); this does not resolve
the separate upstream licensing question.

## Distribution prerequisites

- Resolve GPL-3.0-or-later compatibility with the intended Apple distribution
  terms, including any necessary permissions from the relevant rights holders.
  No App Store exception was found in this checkout. Free pricing does not
  change licence obligations. Preserve attribution and exact corresponding source;
  see [LICENSES.md](../LICENSES.md).
- Select the developer team locally in Xcode. Confirm that
  `com.silverphase.editor` is available and register that exact identifier with
  the Increased Memory Limit capability. Distribution provisioning must retain
  `com.apple.developer.kernel.increased-memory-limit`.
- Create an iOS app record in App Store Connect using the confirmed bundle ID;
  select the intended primary language, SKU, free price and release territories.
  Name availability and account agreements have not been checked.
- Publish a privacy policy and support page with the maintainer's contact details.
  Add an accessible privacy-policy link inside the app before submission.
- Supply current iPhone and iPad screenshots, description, keywords, category,
  age-rating answers, review contact/instructions and export-compliance answers.
  Use public or expressly authorised photographs in store artwork.

## Privacy manifest audit

`Silverphase/PrivacyInfo.xcprivacy` is copied to the app root through the generated
project's resource phase. Current declarations:

| Category | Reason | Source/use |
| --- | --- | --- |
| User defaults | CA92.1 | App-private preferences, export recipes and presets |
| System boot time | 35F9.1 | Preview retries and elapsed export timing |
| File timestamp APIs | C617.1 | App-container file metadata and `fstat` for bundled engine constants |

The manifest declares no tracking or collected data. This reflects the inspected
native app sources, which contain no analytics/upload client. Reassess if services
or SDKs are added. Local photo metadata, edits and export diagnostics still need
to be described accurately in the privacy policy. OS-managed backup, chosen cloud
file destinations and Photos/iCloud behavior must not be described as disabled.
The store privacy questionnaire is a separate step.

Apple references: [required reason APIs](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype),
[privacy policy requirements](https://developer.apple.com/help/app-store-connect/reference/app-information/app-privacy/),
[screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications).

## Archive verification

Generate and check the project, then use the shared `Silverphase` scheme. It
archives Release and produces a dSYM. Public builds must disable local materials:

```sh
python3 ios/Silverphase/Tools/gen-project.py --check
DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer \
SILVERPHASE_LOCAL_MATERIALS=0 \
xcodebuild -project ios/Silverphase/Silverphase.xcodeproj \
  -scheme Silverphase -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/silverphase-appstore-derived \
  -archivePath /tmp/silverphase-appstore-preflight.xcarchive \
  CODE_SIGNING_ALLOWED=NO archive
```

This is an unsigned preflight archive, not an uploadable distribution build.
For distribution, use an appropriate signing team and provisioning, validate in
Xcode Organizer, inspect the signed entitlements and generate a privacy report.
Confirm that `LocalMaterials/` and `*_experimental.json` are absent, and that both
base/product data and licence notices are present.

2026-11-03 verification: the unsigned device Release archive succeeded with
Xcode 27.1. Project generation and plist checks passed. Archive inspection found
the root privacy manifest, engine constants, product provenance/licence notices
and app dSYM, with no local-material directory or experimental JSON profiles.
The build emitted C-linkage, Swift capture/concurrency/style warnings and an
App Intents metadata skip. No XCTest, simulator, or device acceptance run was
performed for these packaging changes; Apple upload validation is still pending.

Before submission, test the signed Release build on iPhone and iPad: cold launch,
Photos/file import (including denied permission), editing, persistence, export
to Files and Photos, and memory-pressure behavior. Follow [README.md](README.md)
for device checks. Compilation and archive checks do not establish visual,
gesture, full-resolution export, or App Review acceptance.
