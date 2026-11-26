#!/usr/bin/env python3
"""Verify the existing App Store identity in the project and built archive."""
import argparse
from collections import Counter
from pathlib import Path
import plistlib
import re

# This is the published App Store record's contract, not a value read
# from the generator. Keep it stable if project/signing code is refactored.
APP_ID = "com.silverphase.editor"
EXTENSIONS = {
    "CameraControl.appex": APP_ID + ".camera-control",
    "LockedCamera.appex": APP_ID + ".locked-camera",
}
EXPECTED_BUILD_IDS = Counter(
    {identifier: 2 for identifier in (APP_ID, *EXTENSIONS.values(), APP_ID + ".uitests")}
)
PROJECT = (
    Path(__file__).resolve().parents[1] / "Silverphase.xcodeproj" / "project.pbxproj"
)


def check_project():
    ids = re.findall(
        r'\bPRODUCT_BUNDLE_IDENTIFIER\s*=\s*"?([^";\s]+)"?\s*;',
        PROJECT.read_text(encoding="utf-8"),
    )
    actual = Counter(ids)
    if actual != EXPECTED_BUILD_IDS:
        raise ValueError(f"unexpected iOS project bundle identifiers: {dict(actual)}")


def check_bundle(bundle, expected):
    info = plistlib.loads((bundle / "Info.plist").read_bytes())
    actual = info.get("CFBundleIdentifier")
    if actual != expected:
        raise ValueError(f"{bundle.name}: expected {expected}, found {actual!r}")


def check_archive(archive):
    app = archive / "Products" / "Applications" / "Silverphase.app"
    check_bundle(app, APP_ID)
    for name, identifier in EXTENSIONS.items():
        matches = [path for path in app.rglob(name) if path.is_dir()]
        if len(matches) != 1:
            raise ValueError(f"{app.name}: expected one {name}, found {len(matches)}")
        check_bundle(matches[0], identifier)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path, nargs="?", help="optional Xcode .xcarchive")
    args = parser.parse_args()
    try:
        check_project()
        if args.archive is not None:
            check_archive(args.archive)
    except (OSError, ValueError, plistlib.InvalidFileException) as exc:
        parser.exit(1, f"iOS identity check failed: {exc}\n")
    print("iOS app and camera extension identities match the published bundle-ID policy.")


if __name__ == "__main__":
    main()
