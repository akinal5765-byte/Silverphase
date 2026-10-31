#!/bin/sh
# check-bundle-resources.sh -- a pre-build check, run by the app target.
#
# Two things must be in `Spektrafilm/Resources/` before a build is worth
# shipping, and both are produced by a script rather than by Xcode:
#
#   engine/    the baked constants, the film profiles, the print-preview LUT
#              index and the Metal library -- `engine/build.sh bundle`.
#              This does not build them: making an Xcode build depend on a
#              bake step would put back exactly the thing RFC-014 exists to
#              remove. It only says what to run. Note that `engine/resources/`
#              is *tracked* in this repository, so the inputs are always here;
#              only the rsync into the app folder has to happen.
#
#   Licenses/  the GPL-3.0, CC BY-SA 4.0 and Apache-2.0 texts the .app is
#              obliged to carry -- `Tools/bundle-licenses.sh`. This is
#              checked here rather than trusted because a bundle that ships
#              without them is not licensed to ship, and nothing else in a
#              build would notice (HANDOFF-DISTRIBUTION §2.3).
#
# The dangerous case for the engine resources is **stale**, not absent: the
# pre-build check cannot tell a re-baked constants file from an old one. Re-run
# `engine/build.sh bundle` after changing anything under `engine/resources`.
set -eu
root=${SRCROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
res="$root/Spektrafilm/Resources"

missing=""
for f in spektrafilm_constants.bin spektrafilm.metallib neutral_print_filters.json print_luts.json paper_grades.json; do
  [ -f "$res/engine/$f" ] || missing="$missing engine/$f"
done
[ -d "$res/engine/profiles" ] || missing="$missing engine/profiles/"

if [ -n "$missing" ]; then
  echo "error: the engine's resources are incomplete under $res" >&2
  echo "error: missing:$missing" >&2
  echo "error: run \`engine/build.sh bundle\`, which rsyncs the tracked" >&2
  echo "error: \`engine/resources/\` into the app's Resources folder" >&2
  exit 1
fi

licences=""
for f in README.txt Silverphase-GPL-3.0.txt Profiles-and-LUTs-CC-BY-SA-4.0.txt \
         Profiles-and-LUTs-CHANGELOG.txt SpektraLab-BW-PROFILES-NOTICE.md metal-cpp-Apache-2.0.txt \
         Colour-BSD-3-Clause.txt Silverphase-Artwork-CC-BY-SA-4.0.txt \
         Silverphase-Artwork-NOTICE.md Runtime-Data-SOURCES.md; do
  [ -f "$res/Licenses/$f" ] || licences="$licences $f"
done

if [ -n "$licences" ]; then
  echo "error: the bundle is missing licence texts it is obliged to carry:$licences" >&2
  echo "error: run \`Tools/bundle-licenses.sh\`" >&2
  echo "error: (GPL-3.0 for the app and engine, CC BY-SA 4.0 for the profiles and the" >&2
  echo "error:  LUTs derived from them, Apache-2.0 for the vendored metal-cpp)" >&2
  exit 1
fi

# The DI canvas and export use the same shipped viewing tables.
for f in "SpektraLab DI view, Cineon to ProPhoto RGB.cube" "SpektraLab DI view, Cineon to Rec709.cube"; do
  [ -s "$res/DI/$f" ] || { echo "error: missing Digital Intermediate viewing LUT: $f" >&2; exit 1; }
done

# The product overlay is mandatory; an old bundle must not silently omit it.
for stock in kodak_tri_x_400 ilford_hp5_plus_400 kodak_tmax_100 fujifilm_neopan_acros_100_ii ilford_multigrade_iv_rc; do
  [ -s "$res/engine/profiles/$stock.json" ] || { echo "error: missing B&W profile: $stock; run engine/build.sh bundle" >&2; exit 1; }
done

# Optional ignored maintainer overlay, refreshed before Xcode copies Resources/.
python3 "$root/../../tools/stage-local-materials.py" "$res"
