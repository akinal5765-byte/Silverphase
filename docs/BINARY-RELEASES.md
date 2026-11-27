# Binary releases

[简体中文](BINARY-RELEASES.zh-CN.md) · **English**

Find release notes and macOS packages on [GitHub Releases](https://github.com/akinal5765-byte/Silverphase/releases).
iPhone and iPad users can install Silverphase from the [App Store](https://apps.apple.com/app/id6829987567). Beta builds are available through [TestFlight](https://testflight.apple.com/join/uwY3ZYJp).
The release notes name the exact source tag/commit, system requirements,
signing state and validation scope. Release builds may have incomplete features.

The platforms maintain independent versions and build numbers. GitHub Releases lists source milestones and macOS installers. The App Store and TestFlight show the iOS builds available for installation. Historical GitHub iOS packages are unsigned.

The current Mac installer is 1.4.0 (build 7). For iOS/iPadOS [1.4.0 (build 12)](../ios/releases/1.4.0.md), see the [dated upload and review record](../ios/APP-STORE.md#140-12--2026-11-27). App Store and TestFlight availability are independent.

## macOS

Use a separate `macos-v<version>` release tag for desktop packages. The desktop
update checker also recognizes older unprefixed tags that carry a macOS DMG.

- Apple Silicon (arm64), macOS 15 or later. Intel Macs are not supported.
- Open `Silverphase-<version>-macOS-arm64.dmg`, then drag Silverphase into Applications.
- Public builds produced by the repository packaging script use an ad-hoc signature for Apple Silicon code execution,
  **no Developer ID signature, and no notarization**. This is not Apple approval.
- If macOS blocks opening it, review System Settings → Privacy & Security and
  use Open Anyway only after verifying the source and checksum. No global
  Gatekeeper disablement is needed. Apple's [opening-app guidance](https://support.apple.com/102445)
  describes the system controls; local security policies may restrict them.

Download **macOS 1.4.0 (build 7)** from its [GitHub Release](https://github.com/akinal5765-byte/Silverphase/releases/tag/macos-v1.4.0). See the [version notes](../modern_UI/Spektrafilm/releases/1.4.0.md) or the [previous 1.3.1 installer](https://github.com/akinal5765-byte/Silverphase/releases/tag/macos-v1.3.1).

The 1.4.0 release uses Silverphase's own bundle identifier and keeps desktop data separate from SpektraLab. Edits and preferences from 1.3.1 or earlier are not automatically adopted. Before replacing the old app, follow [the macOS upgrade guide](MACOS-IDENTITY-UPGRADE.md) to back up and selectively copy your edits and export recipes. The published 1.3.1 package is unchanged.

macOS 1.2.0 (build 4) introduced Lightroom Classic single-photo external editing.
Install Silverphase in Applications and select it under Lightroom's additional
external editor settings; no separate `.lrplugin` is needed. See the
[illustrated guide](LIGHTROOM-CLASSIC.md) and [source version notes](../modern_UI/Spektrafilm/releases/1.2.0.md).

## iPhone and iPad

Install the public version through the [App Store](https://apps.apple.com/app/id6829987567). The previous iOS 1.3.1 (build 11) source milestone is documented in the [GitHub Release](https://github.com/akinal5765-byte/Silverphase/releases/tag/v1.3.1) and [source notes](../ios/releases/1.3.1.md).

Install the beta through [TestFlight](https://testflight.apple.com/join/uwY3ZYJp).
Open the invitation on your iPhone/iPad, install Apple’s TestFlight app if prompted,
then accept the invitation and install Silverphase. The available beta version is
the version shown in TestFlight; it can differ from the repository source version.
Each beta build is available for up to 90 days; see [Apple’s TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/).

### Historical unsigned IPA

See the [iOS 1.2.5 release announcement](https://github.com/akinal5765-byte/Silverphase/releases/tag/v1.2.5) and its [source notes](../ios/releases/1.2.5.md). The unsigned IPA instructions below apply to historical GitHub Release assets.

- iOS/iPadOS 18 or later, arm64.
- The source includes a portrait-only conventional iPhone layout with
  floating controls and vertical film/paper lists; see the [phone captures](../screenshots/ios/2026-11-02/README.md). Duo and iPad retain their own navigation.
  Simulator captures do not establish real-device export or memory coverage.
- `Silverphase-<version>-iOS-unsigned.ipa` is an **unsigned device build**, not a
  simulator app, App Store download or an already provisioned installation.
- Users arrange their own signing, provisioning and installation. This project
  does not supply a shared signing service or device-specific profiles.
- The app requests `com.apple.developer.kernel.increased-memory-limit`.
  `Silverphase-iOS-RequiredEntitlements.plist` records this request. A signing
  tool/account must handle the capability appropriately; not every sideloading
  method authorizes it. Available memory and full-resolution export capacity
  depend on device and signing configuration.
- The IPA contains no developer certificate, private key, provisioning profile,
  personal test photographs or private experimental materials.

See Apple's [registered-device distribution documentation](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices)
for the standard signing/provisioning model. Alternative installation tools
have their own requirements; no particular tool is endorsed or guaranteed.

## Checksums and corresponding source

Download `SHA256SUMS.txt` into the same directory as the assets and run:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

Each release provides the corresponding source under that exact tag through
GitHub's **Source code (zip/tar.gz)** downloads. The source includes build scripts,
engine code and tracked public resources; the binary bundles include licences.
For downloadable binary assets, the accompanying build records identify the source commit and packaged data.

## Reproduce a release build

Use the documented Xcode/Metal toolchain. From a clean, committed checkout:

```sh
export DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer
python3 tools/package-public-release.py --platform macos \
  --tag macos-v<version> --output output/releases/macos-v<version>
python3 tools/package-public-release.py --platform ios \
  --tag v<version> --output output/releases/v<version>
```

The script enforces Release configuration and `SILVERPHASE_LOCAL_MATERIALS=0`,
checks actual platform/architecture floors, stock counts, absence of private
materials, and bundled notice equality. It records the clean source commit,
checks the ad-hoc macOS signature and DMG integrity, and removes iOS signatures
before making the IPA. Only curated assets, installation notes, entitlement
request, build records and checksums belong in a release; do not upload the
build work directory or logs.

The desktop `Tools/package.sh` separately supports a Developer ID archive,
export and notarization workflow when the required credentials are supplied.
The iOS [store record](../ios/APP-STORE.md) documents distribution and upload verification.
