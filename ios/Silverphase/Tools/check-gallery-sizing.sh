#!/bin/sh
# Fast host-only arithmetic regressions; does not boot or install on a device.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
xcrun --sdk macosx swiftc \
    "$here/../../modern_UI/Spektrafilm/Spektrafilm/Model/ParamValue.swift" \
    "$here/Sources/GalleryPreviewSizing.swift" "$here/Tests/GalleryPreviewSizingChecks.swift" \
    -o "$scratch/check"
"$scratch/check"
