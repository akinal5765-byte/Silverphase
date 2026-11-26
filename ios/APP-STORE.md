# iOS App Store distribution

Silverphase is available on the [App Store](https://apps.apple.com/us/app/silverphase-film-simulator/id6829987567) including the [China mainland storefront](https://apps.apple.com/cn/app/id6829987567). [TestFlight](https://testflight.apple.com/join/uwY3ZYJp) is the beta channel. Check the storefront for the currently installable version; the GitHub release tag is a source milestone. In the 2026-11-20 check, the US, Japan and Hong Kong storefronts listed **1.2.5** and the mainland China lookup returned no listing. The developer confirmed that the mainland China listing was live on 2026-11-25.

## 1.3.1 (11) · 2026-11-25

Xcode confirmed delivery to App Store Connect on 2026-11-25 and reported that the build was processing. The archive and dSYMs are retained locally. The signed app and both camera extensions passed version and signature checks, and the app retains the Increased Memory Limit entitlement. The public-material build uses source commit `c65902c`. [Source tag](https://github.com/akinal5765-byte/Silverphase/tree/v1.3.1) · [Release notes](releases/1.3.1.md)

## 1.3.0 (10) · 2026-11-20

See the [1.3.0 release notes](releases/1.3.0.md) for changes and device validation. App Store Connect record **6829987567** uses SKU `silverphase-ios` and bundle ID `com.silverphase.editor`. The deployment floor is iOS and iPadOS 18.

The App Store archive was built from merge commit `187a0df` using public materials. The signed package and its three components passed signature, version, minimum OS and resource checks. The app retains the Increased Memory Limit entitlement and includes the privacy manifest. The archive and dSYMs are retained locally. Xcode confirmed delivery of **1.3.0 (10)** to App Store Connect on 2026-11-20. App Store Connect processing and App Review have separate statuses. [Exact source tag and release notes](https://github.com/akinal5765-byte/Silverphase/releases/tag/v1.3.0)

## 1.2.1 (7) candidate · 2026-11-09

See [release preparation](releases/1.2.1.md) for changes, validation and the
remaining signing/device/store gates. Main app, widget and locked extension use
matching versions. Capture location is enabled by default but requires When In
Use permission; privacy/support copy now describes local GPS metadata and export
stripping. Recheck store privacy answers against this behavior before upload.
This source preparation does not upload, submit for review, merge or publish.

## Historical store preparation · 2026-11-03

The preparation and upload status below records the 2026-11-03 session.

At that time, the planned first release was free, targeting global
availability including China mainland. App Store Connect record **6829987567**
has been created with SKU `silverphase-ios`, bundle ID `com.silverphase.editor`
and Simplified Chinese as its primary language. Build **1.1.1 (3)** was uploaded
successfully on 2026-11-03. Apple finished processing it; TestFlight showed at the time
“Ready to Submit” after the export-compliance answers were saved. No review
submission or public app release has been performed.
The deployment floor is iOS/iPadOS 18.

Chinese promotional text, description, keywords, version 1.1.1, copyright and
review notes were saved in App Store Connect. Login is not required; release is
set to manual after approval. Subtitle is “胶片、显影与印相模拟” and primary category
is Photo & Video. The age questionnaire calculates 4+ for the current editor.
No paid advertising is included; the Layerlight entry is an unpaid own-app link.

[Privacy policy](../docs/PRIVACY.md) and [support page](../docs/SUPPORT.md) are
prepared in Chinese and English. Settings/About link to their public GitHub
`blob/main/docs/` URLs; verify publication before upload and enter the same URLs
in App Store Connect. Both public pages were verified after publication; the
support URL and privacy-policy URL are saved in the store record. The
“Data Not Collected” privacy answers were published after the user's explicit
confirmation. The user authorised committing and pushing this release
preparation to origin/main on 2026-11-03.
At the time, the account reported an updated Apple Developer Program agreement;
the user chose to handle it later. No agreement was accepted by the agent.
China mainland ICP applicability remains unresolved: the app processes photos
locally, but exemption has not been confirmed. No number is supplied or reused
from Layerlight.

Free pricing was saved for all 175 storefronts. Availability is configured for
all 175 countries/regions, including China mainland, subject to Apple's local
requirements and review. iOS-on-Mac and Vision Pro availability are disabled;
this submission targets iPhone/iPad.

Signed Release archive and App Store export succeeded. The exported IPA contains
the privacy manifest and related-app icon, and the archive contains a dSYM.
Public-resource checks found no local-material overlay or experimental profiles.
The source corresponding to this archive is commit `b19d870`; subsequent edits
to this preparation document do not change the binary. Review contact details
were copied from Layerlight at the user's request, saved and verified after reload.
Store screenshots will be supplied by the user; all simulators were shut down
and temporary screenshot source changes were restored. Automated screenshot test
execution failed to start, so it provides no UI acceptance evidence.
Build association with the App Store version remains unverified: App Store Connect
subsequently returned blank pages even when re-entered from the apps list and a
fresh tab. Licensing and regional questions below also remain unresolved.
No device acceptance was repeated during this upload.

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

## Distribution maintenance

- Resolve GPL-3.0-or-later compatibility with the intended Apple distribution
  terms, including any necessary permissions from the relevant rights holders.
  No App Store exception was found in this checkout. Free pricing does not
  change licence obligations. Preserve attribution and exact corresponding source;
  see [LICENSES.md](../LICENSES.md).
- Keep the existing App Store Connect record **6829987567** and app bundle
  identifier `com.silverphase.editor`. Keep the existing embedded identifiers
  `com.silverphase.editor.camera-control` and
  `com.silverphase.editor.locked-camera`. Changing the app identifier after a
  build has been uploaded requires a different App Store record and is not an
  update to the current app. See [Apple's bundle ID documentation](https://developer.apple.com/documentation/xcode/changing-the-bundle-identifier).
- Select the correct signing team in Xcode and retain
  `com.apple.developer.kernel.increased-memory-limit` for the app's distribution
  provisioning. Check storefront availability, pricing and pending agreements
  in App Store Connect.
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
python3 ios/Silverphase/Tools/check-release-identity.py
DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer \
SILVERPHASE_LOCAL_MATERIALS=0 \
xcodebuild -project ios/Silverphase/Silverphase.xcodeproj \
  -scheme Silverphase -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/silverphase-appstore-derived \
  -archivePath /tmp/silverphase-appstore-preflight.xcarchive \
  CODE_SIGNING_ALLOWED=NO archive
python3 ios/Silverphase/Tools/check-release-identity.py /tmp/silverphase-appstore-preflight.xcarchive
```

This is an unsigned preflight archive, not an uploadable distribution build.
For distribution, use an appropriate signing team and provisioning, validate in
Xcode Organizer, rerun the identity check on the signed archive, inspect the
signed entitlements and generate a privacy report.
Confirm that `LocalMaterials/` and `*_experimental.json` are absent, and that both
base/product data and licence notices are present.

2026-11-03 verification: the unsigned device Release archive succeeded with
Xcode 27.1. Project generation and plist checks passed. Archive inspection found
the root privacy manifest, engine constants, product provenance/licence notices
and app dSYM, with no local-material directory or experimental JSON profiles.
The build emitted C-linkage, Swift capture/concurrency/style warnings and an
App Intents metadata skip. No XCTest, simulator, or device acceptance run was
performed for these packaging changes. The subsequent signed upload was accepted
and finished processing; this does not establish App Review approval.

Before submission, test the signed Release build on iPhone and iPad: cold launch,
Photos/file import (including denied permission), editing, persistence, export
to Files and Photos, and memory-pressure behavior. Follow [README.md](README.md)
for device checks. Compilation and archive checks do not establish visual,
gesture, full-resolution export, or App Review acceptance.
