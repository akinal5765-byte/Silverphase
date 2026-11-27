#!/bin/bash
set -euo pipefail
tools="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
xcrun_bin="$(xcrun --find swiftc)"
host="$(dirname "$xcrun_bin")/../lib/swift/host"
"$xcrun_bin" -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path "$work/modules" -I "$host" -L "$host" \
  -Xlinker -rpath -Xlinker "$host" "$tools/mobile-l10n-inventory.swift" -o "$work/inventory"
"$work/inventory" "$tools/../Sources"
