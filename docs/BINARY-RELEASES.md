# Binary releases

Find release notes and macOS packages on [GitHub Releases](https://github.com/akinal5765-byte/Silverphase/releases).
iPhone/iPad beta installation and updates use [TestFlight](https://testflight.apple.com/join/uwY3ZYJp).
The release notes name the exact source tag/commit, system requirements,
signing state and validation scope. Release builds may have incomplete features.

The platforms maintain independent versions and build numbers. Use GitHub Releases
and TestFlight for the versions available to install. Historical GitHub iOS
packages are unsigned.

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

## iPhone and iPad

Install the beta through [TestFlight](https://testflight.apple.com/join/uwY3ZYJp).
Open the invitation on your iPhone/iPad, install Apple’s TestFlight app if prompted,
then accept the invitation and install Silverphase. The available beta version is
the version shown in TestFlight; it can differ from the repository source version.
Each beta build is available for up to 90 days; see [Apple’s TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/).

### Historical unsigned IPA

The iOS source version is **1.1.3 (5)**. Check TestFlight for the currently available beta. The unsigned IPA instructions below apply to historical GitHub Release assets.

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
The platform build JSON records identify the source commit and packaged data.

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
No store distribution, Developer ID signing or notarization schedule is promised.
