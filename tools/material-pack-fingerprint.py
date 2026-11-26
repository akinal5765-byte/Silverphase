#!/usr/bin/env python3
"""Identify the material files actually staged into a Silverphase app bundle."""
import argparse
import hashlib
import json
from pathlib import Path

MANIFEST = "material-pack-fingerprint.json"
CORE_INPUTS = (
    "neutral_print_filters.json",
    "paper_grades.json",
    "print_luts.json",
    "spektrafilm_constants.bin",
)


def digest_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(block)
    return digest.digest()


def describe(engine):
    profiles = sorted((engine / "profiles").glob("*.json"))
    if not profiles:
        raise ValueError("No staged profiles")
    files = [engine / name for name in CORE_INPUTS] + profiles
    digest = hashlib.sha256(b"silverphase-material-pack-v1\0")
    for path in sorted(files, key=lambda p: p.relative_to(engine).as_posix()):
        digest.update(path.relative_to(engine).as_posix().encode("utf-8"))
        digest.update(b"\0")
        digest.update(digest_file(path))
    return {
        "algorithm": "silverphase-material-pack-v1",
        "sha256": digest.hexdigest(),
        "profile_count": len(profiles),
        "includes_local_materials": any(p.name.endswith("_experimental.json") for p in profiles),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("engine", type=Path, help="Path to the staged app's engine resource directory")
    parser.add_argument("--check", action="store_true", help="Verify the stored manifest against staged bytes")
    args = parser.parse_args()
    manifest = args.engine / MANIFEST
    try:
        description = describe(args.engine)
        payload = json.dumps(description, sort_keys=True, indent=2) + "\n"
        if args.check:
            if json.loads(manifest.read_text(encoding="utf-8")) != description:
                raise ValueError("Stored fingerprint does not match staged material files")
        else:
            if not manifest.is_file() or manifest.read_text(encoding="utf-8") != payload:
                temporary = manifest.with_suffix(".json.tmp")
                temporary.write_text(payload, encoding="utf-8")
                temporary.replace(manifest)
    except (OSError, ValueError) as error:
        parser.exit(1, f"Material pack fingerprint: {error}\n")
    print(description["sha256"])


if __name__ == "__main__":
    main()
