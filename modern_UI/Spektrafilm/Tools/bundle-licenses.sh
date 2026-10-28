#!/bin/bash
# bundle-licenses.sh -- put the licence texts the .app is obliged to carry
# into `Spektrafilm/Resources/Licenses/`, from their canonical copies.
#
# HANDOFF-DISTRIBUTION §2.3. Three obligations, and the second is the one that
# is easy to miss:
#
#   GPL-3.0-or-later   the application and the C++ engine. Distributing
#                      binaries requires the licence text and an offer of the
#                      corresponding source.
#   CC BY-SA 4.0       the 28 film and paper profiles, and the 8 baked print
#                      LUTs derived from them. They are Andrea Volpato's, and
#                      the licence names "an app's About screen" as a place
#                      the attribution must survive -- so the bundle carries
#                      the text and the app shows the credit.
#   Apache-2.0         vendored metal-cpp, compiled into the binary.
#
# Copied rather than written by hand, and copied by a script rather than once:
# a licence text that drifts from the code it covers is worse than none, and
# the GPL is 674 lines nobody will diff.
#
# The result is checked in, so a fresh clone builds without running this. Run
# it when a source text changes, and `Tools/check-bundle-resources.sh` (the
# app's pre-build phase) fails the build if the directory is missing.
set -euo pipefail

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$here/../../.." && pwd)     # the repository
out="$here/../Spektrafilm/Resources/Licenses"
mkdir -p "$out"

# The GPL's written offer: where the source of *this binary* is. It must match
# `AboutWindow.sourceURL`, and `LicensingTests` asserts that it does -- the two
# disagreed through two product renames, with the panel pointing at this
# application and the licence file still pointing at the upstream project,
# which is the source of the profiles and not of this app. If the repository is
# renamed, change it in both places and re-run this script.
source_url="https://github.com/akinal5765-byte/Silverphase"
predecessor_url="https://github.com/JamesQiu2005/SpektraLab"
# The upstream project, whose profiles and print model this application uses.
# A different work under a different licence; not a substitute for the above.
upstream_url="https://github.com/andreavolpato/spektrafilm"

cp "$root/license/LICENSE" "$out/Silverphase-GPL-3.0.txt"
cp "$root/license/SPEKTRAFILM_LICENSE.txt" "$out/Profiles-and-LUTs-CC-BY-SA-4.0.txt"
cp "$root/engine/third_party/metal-cpp/LICENSE.txt" "$out/metal-cpp-Apache-2.0.txt"

# The CC BY-SA text asks that changes to the profiles and LUTs be recorded in
# a CHANGELOG shipped beside them, rather than by editing the licence. This is
# that file, and it is written here rather than checked in on its own so it
# stays next to the reason for it.
cat > "$out/Profiles-and-LUTs-CHANGELOG.txt" <<'CHANGELOG'
Changes to the spektrafilm profiles and LUTs in this application
================================================================

Required by SPEKTRAFILM_LICENSE.txt ("Changes to profiles and LUTs should be
tracked in a separate CHANGELOG.txt file shipped with them").

Original author:  Andrea Volpato
Canonical source: https://github.com/andreavolpato/spektrafilm
Licence:          CC BY-SA 4.0


The 28 film and paper profiles  --  UNMODIFIED
----------------------------------------------

The original 28 profiles (excluding Silverphase experimental additions) are
byte-for-byte copies of
`src/spektrafilm/data/profiles/*.json` from the upstream project. Nothing in
this application edits them; `engine/tools/bake_resources.py` copies them and
`engine/src/core/profile.cpp` reads them.

PRO160NS experimental profile -- DERIVED, 2026-10-04
---------------------------------------------------

Added by Silverphase / akinal5765-byte, derived from Andrea Volpato's
spektrafilm PRO400H dye basis. Licensed CC BY-SA 4.0 with the attribution above.
Canonical source of the donor: https://github.com/andreavolpato/spektrafilm

PRO160NS manufacturer curves replace sensitivity, response, base density and
neutral spectral density. No PRO400H Hanatos correction is copied. Dye
separation, unmeasured shoulder, grain and layer effects remain approximations.
Source: Fujifilm 163AR109A (04.7-FG), page 8:
https://asset.fujifilm.com/www/jp/files/2024-04/6b75b1c1cb4253623fb2cd7a56ff7443/datasheet_pro160ns_01.pdf
Reproducible generator: engine/tools/make_pro160ns.py

Three experimental negative profiles -- DERIVED, 2026-10-04
-----------------------------------------------------------

Added by Silverphase / akinal5765-byte, derived from Andrea Volpato's
spektrafilm Gold 200 (Pro Image) and PRO400H (REALA/NATURA) dye bases.
Derivatives remain CC BY-SA 4.0; original attribution above is retained.
Each stock replaces characteristic, sensitivity, base and neutral spectra
with its own manufacturer curves. No donor Hanatos correction is copied.
Dye separation, unmeasured shoulder, grain and fourth-layer effects remain
approximations. Not manufacturer-endorsed or validated against real negatives.

Kodak Pro Image 100: Kodak E-4L (July 1997), page 3, archive copy:
https://vklaboratori.com/wp-content/uploads/2018/07/kodak-pro-image-100.pdf
Fujifilm SUPERIA REALA 100: AF3-967E (EIGI-00.12-HB), page 4, archive copy:
https://filmcolors.org/wp-content/uploads/2025/12/Fujicolor-Superia-Reala_AF3-967E.pdf
Fujifilm NATURA 1600: 013AR313B (06.4-FP), page 4:
https://asset.fujifilm.com/www/jp/files/2024-04/96b634a89ec6a5abda6b70437f4d75a4/datasheet_natura1600_01.pdf
Reproducible generator: engine/tools/make_negative_profiles.py
PDFs are not bundled; saved numerical samples and SHA-256 identify sources.

Four further experimental negative profiles -- DERIVED, 2026-10-04
-----------------------------------------------------------------

Added by Silverphase / akinal5765-byte; CC BY-SA 4.0 derivatives with Andrea
Volpato's attribution retained. Each uses its own published characteristic,
sensitivity, minimum and neutral spectra. No donor Hanatos correction copied.
Agfa Portrait XPS 160 uses spektrafilm Portra 160 as a dye-separation prior;
Agfa Optima II 200 and Kodak Elite Color 200 use Gold 200; Fujifilm PRO 160C
uses PRO400H. This does NOT establish shared emulsion chemistry. Generic grain
and spatial effects remain unchanged. Colour accuracy needs photographic
evaluation; curve-fit/runtime tests do not constitute real-film validation.

Agfa Portrait XPS 160 / Optima II 200: Technical Data PF, 09/1998 first edition,
pages 8 / 7, original manufacturer document in archive:
https://cacreeks.com/photos/agfaPro.pdf
Kodak Elite Color 200: E-4039, July 2006, page 7, archive copy:
https://125px.com/docs/film/kodak/e4039-Elite.pdf
Fujifilm PRO 160C: Professional Film Data Guide, 2005, printed page 59:
https://asset.fujifilm.com/www/ca/files/2020-03/d52487c5c6f84e7f935c299491c5c1ff/ProfessionalFilmDataGuide.pdf
Reproducible generator: engine/tools/make_negative_profiles.py
Saved numerical samples identify the exact PDF hash. PDFs are not bundled.


The 8 baked print-preview LUTs  --  DERIVED
-------------------------------------------

Inside `Resources/engine/spektrafilm_constants.bin`, as `print_lut/<stock>`
and `print_lut_axes/<stock>`: one 33x33x33x3 float32 table per print stock,
plus its per-channel density axes.

These are derivatives of the profiles, and the licence is explicit that they
are ("LUTs and similar artifacts are interpreted as direct encodings of the
information in the original profiles"). How they were made:

  - `scripts/bake_all_print_luts.py` evaluated this project's own physical
    print+scan simulation over a 33^3 grid of film densities, for each print
    stock paired with one film stock. The pairing is recorded per stock in
    `Resources/engine/print_luts.json` as `paired_film`, along with whether
    the profile data declared that pairing or the bake chose a default
    (`declared_pairing`).
  - `scanning.glare` is deliberately excluded. It is a spatial, stochastic
    veiling field and cannot be represented in a pointwise table.
  - The output is Display P3 with its transfer function applied, stored
    unclamped -- so a print colour outside P3's gamut is a negative
    coordinate rather than a clipped one.

They are not a scanned reference print. They are this simulation's output.

Distributed under CC BY-SA 4.0, the same licence as the profiles they derive
from, as the share-alike condition requires.


Eight experimental colour negatives -- REVISION 2, 2026-10-04
------------------------------------------------------------
The colour-film derivation descriptions above record historical revision 1.
Revision 2 supersedes their dye reconstruction and removed-adaptation procedure.
The original 28 profiles are still unchanged. Each experimental colour film now
retains its CC BY-SA base film's coherent dye spectra, base absorption, shoulder
and Hanatos calibration. Manufacturer relative sensitivity contributes 20% of
a daylight-normalized linear sensitivity mixture; a common contrast multiplier
is bounded to +/-10%. No Status-M inverse or neutral-spectrum dye rescaling is
performed. These weights are conservative creative approximations, not measured
stock properties or verified reproductions. Source samples and attribution are
preserved; all colour-paper filter packs for these derivatives are rebalanced.
Modified by Silverphase / akinal5765-byte, retaining Andrea Volpato's attribution
and CC BY-SA 4.0 terms. See engine/tools/profile_sources/experimental_negatives.md.

Six experimental B&W films and a synthetic neutral print -- DERIVED, 2026-10-04
-----------------------------------------------------------------------------
HP5 Plus 400, Tri-X 400, Delta 100, FP4 Plus 125, XP2 Super 400 and Fomapan 100
Classic use manually estimated manufacturer chart knots. Their neutral density,
CDF components, unmeasured shoulders and grain are approximations; XP2 is a
chromogenic C-41 monochrome model. Silverphase Neutral B&W Print is a synthetic
neutral response, NOT a measured or branded paper. No manufacturer PDFs are
redistributed. Sources, versions, hashes, processing and limitations are recorded
in engine/tools/profile_sources/blackwhite_samples.json and blackwhite.md.
These profile containers derive from Andrea Volpato's spektrafilm CC BY-SA 4.0
profiles; attribution and share-alike terms remain. Original profiles are unchanged.

B&W revision 2, 2026-10-04: re-digitized HP5, FP4, Delta 100 and XP2 characteristic
curves from the original ILFORD embedded raster charts; Tri-X characteristic and
D=1 sensitivity from Kodak PDF vector paths. Source hashes, chart axes and methods
are recorded. Fomapan remains hand-estimated. Worst local fitting error is checked
alongside RMS. Neutral density, shoulder, grain and paper assumptions remain
approximate. Modified by Silverphase / akinal5765-byte, CC BY-SA 4.0 retained.

The constants that are not derived from the profiles
----------------------------------------------------

The rest of `spektrafilm_constants.bin` -- the 1931 standard observer, the
illuminant SDs, the colourspace primaries and matrices, the CAT cone
matrices, the Mallett basis, the Hanatos irradiance spectra, and the measured
KG3 and lens filter curves -- is published colour-science data, not Andrea
Volpato's profile work, and is not covered by this file.
Film edges, date backs and half-frame composition -- ADOPTED, 2026-10-12
------------------------------------------------------------------------
Native film-edge and date-back rendering, brand markings, paired-frame regional
curves and scene-linear pair composition adopted from Hanze Qiu's SpektraLab
commit 01d32a2b767fbdb447bbc3ab156dfa1f2388580c, GPL-3.0-or-later.
Silverphase adapts the controls, input framing, session cache and document UI.
Source provenance is recorded in engine/resources_product/UPSTREAM.json.

CHANGELOG

cat > "$out/README.txt" <<README
Licences and credits
====================

Silverphase is free software. This directory carries the full text of every
licence the application is distributed under, because a binary that ships
without them is not licensed to be shipped.

  Silverphase-GPL-3.0.txt
      The application and the C++ render engine, GPL-3.0-or-later. You have
      the right to the corresponding source code of this application:
      $source_url

  Profiles-and-LUTs-CC-BY-SA-4.0.txt
      The 28 film and paper profiles, and the 8 baked print-preview LUTs
      derived from them, by Andrea Volpato, CC BY-SA 4.0.
      $upstream_url
      Redistribution and derivatives must credit the author, link the
      project, and preserve that licence.

  Profiles-and-LUTs-CHANGELOG.txt
      What this application did and did not change about them. The profiles
      are unmodified; the LUTs are derivatives, and this says how they were
      made.

  metal-cpp-Apache-2.0.txt
      metal-cpp, Apple's C++ bindings for Metal, Apache-2.0, compiled into
      the binary.

Silverphase is an independent derivative of SpektraLab ($predecessor_url).
The first link above is for Silverphase's corresponding source. The film
simulation, measured profiles and print+scan model originate in Andrea
Volpato's spektrafilm at the second link. Silverphase is not affiliated with
or endorsed by either original project.
README

# Preserve Hanze Qiu's notice verbatim; expose it through About's licence reader.
cp "$here/../../../engine/resources_product/NOTICE.md" "$out/SpektraLab-BW-PROFILES-NOTICE.md"
cat >> "$out/Profiles-and-LUTs-CHANGELOG.txt" <<'BWNOTICE'

B&W adoption, 2026-10-12
------------------------
Tri-X 400 and HP5 Plus 400 now use SpektraLab 1.3.3's profiles by Hanze Qiu;
T-Max 100, Acros II and Ilford Multigrade IV RC are added from the same source.
These product profiles are copied unchanged and are separate from Andrea
Volpato's original 28 CC BY-SA profiles. See SpektraLab-BW-PROFILES-NOTICE.md.
Delta, FP4, XP2 and Fomapan retain Silverphase's experimental models.
The Wratten lens filter table and exposure weighting are adopted from the same
SpektraLab commit, with Hanze Qiu's source attribution retained. The table
transcribes Kodak B-3 data; No. 58 has the factor uncertainty recorded in its
source header. No original measured film or paper profile is altered for it.
BWNOTICE

printf 'licences   -> %s\n' "$out"
ls -1 "$out" | sed 's/^/             /'
