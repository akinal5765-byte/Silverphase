# Silverphase artwork: scope, sources and attribution

Reviewed 2026-10-31. The maintainer confirms that the film covers were generated
with AI prompts and requested retention of the current packaging-style artwork.
This notice records provenance and separates project-controlled artwork from
third-party rights. It does not certify that every packaging element is cleared.

## Project-controlled artwork

To the extent copyright is held by Silverphase contributors, Silverphase's
AI-generated material/workflow covers and newly authored icon artwork are made
available under **CC BY-SA 4.0**. Credit **Silverphase contributors /
akinal5765-byte**, link to https://github.com/akinal5765-byte/Silverphase, retain
this notice and indicate changes. Full legal text: `license/CC-BY-SA-4.0.txt` in
the source, `Silverphase-Artwork-CC-BY-SA-4.0.txt` in the application bundle.
No exclusive copyright claim is made over machine-generated elements.

The scope of this grant is limited to these project-controlled contributions:

- Current material/workflow `.png` covers under
  `modern_UI/Spektrafilm/Spektrafilm/Resources/FilmCovers/`, identified by the
  `generated-*-manifest.json` files in `modern_UI/design/film-artwork/`.
  Those manifests record actual prompts, filenames and aliases. The three
  product B&W covers added on 2026-10-31 used built-in imagegen with text only.
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

Several saved prompts explicitly request resemblance to real packaging. AI
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
README promotion; it is excluded from Silverphase's GPL and CC BY-SA grants.
The owner-supplied production source hashes and native export settings are in
`screenshots/related-apps/layerlight-source.json`. No Layerlight application
source code is included or relicensed here.
