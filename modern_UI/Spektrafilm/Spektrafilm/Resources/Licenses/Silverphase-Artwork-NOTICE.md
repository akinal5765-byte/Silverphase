# Silverphase artwork: scope, sources and attribution

The maintainer confirmed AI generation and retention of the historical
packaging-style artwork on 2026-10-31. The current library series uses newly
generated illustrations, based on text and stock color palettes rather than
packaging images. This notice separates project-controlled artwork from
third-party rights; it does not certify rights clearance.

## Project-controlled artwork

To the extent copyright is held by Silverphase contributors, Silverphase's
AI-generated material/workflow covers and newly authored icon artwork are made
available under **CC BY-SA 4.0**. Credit **Silverphase contributors /
akinal5765-byte**, link to https://github.com/akinal5765-byte/Silverphase, retain
this notice and indicate changes. Full legal text: `license/CC-BY-SA-4.0.txt` in
the source, `Silverphase-Artwork-CC-BY-SA-4.0.txt` in the application bundle.
No exclusive copyright claim is made over machine-generated elements.

The scope of this grant is limited to these project-controlled contributions:

- Built-in stock illustrations in
  `modern_UI/Spektrafilm/Spektrafilm/Resources/FilmCovers/` and their resized
  website derivatives in `docs/site/covers/`. The
  `modern_UI/design/film-artwork/generated-stock-covers-v2-manifest.json`
  records the text-only prompts, source and derivative hashes, and aliases.
  The two separately generated workflow labels remain identified by
  `generated-workflow-manifest.json`.
- Silverphase icon SVG layers, Icon Composer documents and icon-only previews
  under `design/app-icon/` and the production `Silverphase.icon` document.
  The production document is generated locally by `Tools/make-icon.py`; the
  generator remains GPL-3.0-or-later software. Apple's system renderer supplies
  platform lighting/material effects; no Apple artwork ownership is claimed.

The maintainer also identifies legacy cover images as AI-generated. Earlier
per-image prompts are not present for all `.jpg` covers or files under
`modern_UI/film_covers/`; do not claim that the new manifests prove their exact
original generator, generation date or prompt. Preserve their repository history.
The project-controlled portion of these legacy covers uses the same CC BY-SA
terms above; third-party elements are excluded as below.

## Rights outside this grant

Brand names, logos and recognizable manufacturer packaging are third-party
elements. This project does not grant trademark rights or purport to relicense
third-party packaging design. Material names identify the simulated materials;
no manufacturer affiliation, certification or endorsement is implied.

Several historical prompts explicitly request resemblance to real packaging. AI
provenance and this disclaimer do not establish permission for those elements.
Recipients must consider their intended use; retain this distinction when
redistributing artwork. The decision to keep these illustrations is not a finding
that all third-party rights have been cleared.

Photographs, photo-bearing UI screenshots, third-party application captures and
inherited upstream artwork are outside this new Silverphase grant. Existing
upstream notices and applicable terms remain in force. Do not infer a new photo
licence from the code licence or from this notice.

## Photographs and current screenshots

Source photographs and personal sidecars stay outside Git. The maintainer does
not authorize publishing private photographs by default. The six current UI examples in `screenshots/current/` use selected test
photographs authorized for project demonstration, including the approved
record-display case. Their manifest records sources and permitted use. This
permission does not authorize distributing RAW originals or granting a general
photo-reuse licence. Earlier dated UI captures are historical material inherited
from upstream, distinct from the current Silverphase examples.

## Related application icon

`screenshots/related-apps/layerlight-icon.png` identifies the maintainer's separate
proprietary App Store application, Layerlight. The app owner authorized its
README and iOS Settings/About promotion; it is excluded from Silverphase's GPL and CC BY-SA grants.
The owner-supplied production source hashes and native export settings are in
`screenshots/related-apps/layerlight-source.json`. No Layerlight application
source code is included or relicensed here.

## Ordinary iPhone layout captures

`screenshots/ios/2026-11-02/` contains native simulator UI captures with a
self-authored Core Image gradient fixture, not private or third-party photographs.
Original PNGs and provenance are recorded in the adjacent manifest. Application
UI and generated fixture follow the project terms; Apple system UI, fonts and
bundled material packaging retain their existing rights and notices. These
layout examples do not grant additional rights to third-party material artwork.
