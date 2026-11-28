#!/usr/bin/env python3
"""Verify the existing App Store identity in the project and built archive."""
import argparse
from pathlib import Path
import plistlib
import subprocess

# This is the published App Store record's contract, not a value read
# from the generator. Keep it stable if project/signing code is refactored.
APP_ID = "com.silverphase.editor"
EXTENSIONS = {
    "CameraControl.appex": APP_ID + ".camera-control",
    "LockedCamera.appex": APP_ID + ".locked-camera",
}
EXPECTED_TARGET_IDS = {
    "Silverphase": APP_ID,
    "CameraControl": EXTENSIONS["CameraControl.appex"],
    "LockedCamera": EXTENSIONS["LockedCamera.appex"],
    "SilverphaseUITests": APP_ID + ".uitests",
}
EXPECTED_CONFIGURATIONS = {"Debug", "Release"}
BUNDLE_ID_SETTING = "PRODUCT_BUNDLE_IDENTIFIER"
PROJECT = (
    Path(__file__).resolve().parents[1] / "Silverphase.xcodeproj" / "project.pbxproj"
)


def load_project(project_path):
    # Xcode uses OpenStep plists; plutil parses objects and references without
    # depending on generator formatting, comments or the order of the records.
    result = subprocess.run(
        ["plutil", "-convert", "xml1", "-o", "-", "--", str(project_path)],
        capture_output=True,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).decode(errors="replace").strip()
        raise ValueError(f"could not read Xcode project: {detail}")
    return plistlib.loads(result.stdout)


def check_project_document(document):
    objects = document.get("objects") if isinstance(document, dict) else None
    if not isinstance(objects, dict):
        raise ValueError("missing Xcode project objects")

    def resolve(reference, kind):
        record = objects.get(reference) if isinstance(reference, str) else None
        if not isinstance(record, dict) or record.get("isa") != kind:
            raise ValueError(f"missing {kind} object for {reference!r}")
        return record

    project = resolve(document.get("rootObject"), "PBXProject")
    target_refs = project.get("targets")
    if not isinstance(target_refs, list):
        raise ValueError("missing Xcode project targets")

    seen_targets = set()
    for target_ref in target_refs:
        target = resolve(target_ref, "PBXNativeTarget")
        name = target.get("name")
        if not isinstance(name, str) or name not in EXPECTED_TARGET_IDS:
            raise ValueError(f"unexpected iOS build target {name!r}")
        if name in seen_targets:
            raise ValueError(f"duplicate iOS build target {name!r}")
        seen_targets.add(name)

        listing = resolve(target.get("buildConfigurationList"), "XCConfigurationList")
        config_refs = listing.get("buildConfigurations")
        if not isinstance(config_refs, list):
            raise ValueError(f"{name}: missing build configurations")
        seen_configs = set()
        expected = EXPECTED_TARGET_IDS[name]
        for config_ref in config_refs:
            config = resolve(config_ref, "XCBuildConfiguration")
            config_name = config.get("name")
            if not isinstance(config_name, str) or config_name not in EXPECTED_CONFIGURATIONS:
                raise ValueError(f"{name}: unexpected build configuration {config_name!r}")
            if config_name in seen_configs:
                raise ValueError(f"{name}: duplicate build configuration {config_name!r}")
            seen_configs.add(config_name)

            settings = config.get("buildSettings")
            if not isinstance(settings, dict):
                raise ValueError(f"{name} ({config_name}): missing build settings")
            actual = settings.get(BUNDLE_ID_SETTING)
            if actual != expected:
                raise ValueError(
                    f"{name} ({config_name}): expected {expected}, found {actual!r}"
                )
            for key, value in settings.items():
                if key.startswith(BUNDLE_ID_SETTING + "[") and value != expected:
                    raise ValueError(
                        f"{name} ({config_name}) {key}: expected {expected}, found {value!r}"
                    )

        if seen_configs != EXPECTED_CONFIGURATIONS:
            missing = sorted(EXPECTED_CONFIGURATIONS - seen_configs)
            raise ValueError(f"{name}: missing build configurations {missing}")

    if seen_targets != EXPECTED_TARGET_IDS.keys():
        missing = sorted(EXPECTED_TARGET_IDS.keys() - seen_targets)
        raise ValueError(f"missing iOS build targets {missing}")


def check_project():
    check_project_document(load_project(PROJECT))


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
