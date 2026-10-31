#!/bin/bash
# iOS host of the current engine. Derived from the working poc/ios probe;
# resources and sources come from this checkout, never the old PoC worktree.
set -euo pipefail
here=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
repo=$(CDPATH= cd -- "$here/../.." && pwd)
sdk=${PLATFORM_NAME:-${1:-iphonesimulator}}
case "$sdk" in
    iphoneos) target=arm64-apple-ios18.0; metal_min=-mios-version-min=18.0 ;;
    iphonesimulator) target=arm64-apple-ios18.0-simulator; metal_min=-mios-simulator-version-min=18.0 ;;
    *) echo "Unsupported iOS platform: $sdk" >&2; exit 1 ;;
esac
out=${DERIVED_FILE_DIR:-$here/build/$sdk}
mkdir -p "$out/objects" "$out/air" "$out/module-cache"
export CLANG_MODULE_CACHE_PATH="$out/module-cache"
includes=(-I"$repo/engine/include" -I"$repo/engine/src" -I"$repo/engine/src/core" -I"$repo/engine/third_party/metal-cpp")
# Headers are dependencies too. Hashes prevent a stale library from silently
# surviving a source edit, including additions to the current engine.
fingerprint=$(find "$repo/engine/src" "$repo/engine/include" "$repo/engine/third_party/metal-cpp" -type f -print0 | sort -z | xargs -0 shasum -a 256 | shasum -a 256)
toolchain=$(xcrun --sdk "$sdk" --show-sdk-path)
compiler=$(xcrun --sdk "$sdk" clang++ --version)
script_hash=$(shasum -a 256 "$here/Tools/build-engine.sh")
stamp="$fingerprint $toolchain $target $compiler $script_hash"
if [[ ! -f "$out/stamp" || "$(cat "$out/stamp")" != "$stamp" ]]; then
    for src in "$repo"/engine/src/{core,gpu,pipeline}/*.cpp; do
        xcrun --sdk "$sdk" clang++ -std=c++20 -O2 -target "$target" "${includes[@]}" -c "$src" -o "$out/objects/$(basename "$src" .cpp).o"
    done
    objects=()
    for src in "$repo"/engine/src/{core,gpu,pipeline}/*.cpp; do objects+=("$out/objects/$(basename "$src" .cpp).o"); done
    rm -f "$out/libSilverphaseEngine.a.tmp"
    xcrun --sdk "$sdk" ar rcs "$out/libSilverphaseEngine.a.tmp" "${objects[@]}"
    mv "$out/libSilverphaseEngine.a.tmp" "$out/libSilverphaseEngine.a"
    airs=()
    for src in "$repo"/engine/src/shaders/*.metal; do
        air="$out/air/$(basename "$src" .metal).air"
        xcrun --sdk "$sdk" metal -fmodules-cache-path="$out/module-cache" \
            -fmetal-math-mode=safe -fmetal-math-fp32-functions=precise "$metal_min" -Werror -c "$src" -o "$air"
        airs+=("$air")
    done
    xcrun --sdk "$sdk" metallib "${airs[@]}" -o "$out/spektrafilm.metallib"
    echo "$stamp" > "$out/stamp"
fi
if [[ -n ${TARGET_BUILD_DIR:-} ]]; then
    resources="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/AppResources"
else
    resources="$out/AppResources"
fi
mkdir -p "$resources/engine" "$resources/Licenses"
rsync -a --delete --exclude='spektrafilm.metallib' "$repo/engine/resources/" "$resources/engine/"
cp "$out/spektrafilm.metallib" "$resources/engine/spektrafilm.metallib"
cp "$repo"/engine/resources_product/profiles/*.json "$resources/engine/profiles/"
cp "$repo"/engine/resources_product/paper_grades.json "$resources/engine/paper_grades.json"
xcrun --sdk macosx swift -sdk "$(xcrun --sdk macosx --show-sdk-path)" "$here/Tools/merge-neutral-filters.swift" \
    "$repo/engine/resources/neutral_print_filters.json" "$repo/engine/resources_product/neutral_print_filters.json" "$resources/engine/neutral_print_filters.json"
cp "$repo"/engine/resources_product/NOTICE.md "$resources/engine/PRODUCT_PROFILES_NOTICE.md"
cp "$repo"/engine/resources_product/UPSTREAM.json "$resources/engine/PRODUCT_PROFILES_UPSTREAM.json"
cp "$repo"/modern_UI/Spektrafilm/Spektrafilm/Resources/Licenses/* "$resources/Licenses/"
cp "$repo"/modern_UI/Spektrafilm/Spektrafilm/Resources/StockCatalog.json "$resources/StockCatalog.json"
rsync -a --delete "$repo/modern_UI/Spektrafilm/Spektrafilm/Resources/FilmCovers/" "$resources/FilmCovers/"

python3 "$repo/tools/stage-local-materials.py" "$resources"

cp "$here/Resources/DesktopControlDefaults.json" "$resources/DesktopControlDefaults.json"
# The desktop output transform is compiled unchanged for iOS as a UI library.
ui_stamp="$(shasum -a 256 "$repo/modern_UI/Spektrafilm/Spektrafilm/Canvas/Shaders.metal" "$here/Shaders/MobileView.metal") $sdk"
if [[ ! -f "$out/ui-stamp" || "$(cat "$out/ui-stamp")" != "$ui_stamp" ]]; then
    xcrun --sdk "$sdk" metal -fmodules-cache-path="$out/module-cache" -fmetal-math-mode=safe -fmetal-math-fp32-functions=precise "$metal_min" -c "$repo/modern_UI/Spektrafilm/Spektrafilm/Canvas/Shaders.metal" -o "$out/ui.air"
    xcrun --sdk "$sdk" metal -fmodules-cache-path="$out/module-cache" -fmetal-math-mode=safe -fmetal-math-fp32-functions=precise "$metal_min" -c "$here/Shaders/MobileView.metal" -o "$out/mobile-view.air"
    xcrun --sdk "$sdk" metallib "$out/ui.air" "$out/mobile-view.air" -o "$out/SilverphaseUI.metallib"
    echo "$ui_stamp" > "$out/ui-stamp"
fi
cp "$out/SilverphaseUI.metallib" "$resources/SilverphaseUI.metallib"
rsync -a "$repo/modern_UI/Spektrafilm/Spektrafilm/Resources/DI/" "$resources/DI/"
