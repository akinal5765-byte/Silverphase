# Licensing and attribution

Silverphase is an independent derivative of [SpektraLab](https://github.com/JamesQiu2005/SpektraLab)
by **Hanze Qiu**, built on [spektrafilm](https://github.com/andreavolpato/spektrafilm)
by **Andrea Volpato**. Silverphase changes are maintained by **akinal5765-byte**.
Retain original copyright notices and Git history. Neither upstream author or
project endorses Silverphase.

This is a map of the repository's existing terms, not a replacement licence or
a blanket grant for every image in the repository.

| Material | Terms and source of authority |
|---|---|
| Application code, shared C++/Metal engine, development tools and Silverphase code changes | GPL-3.0-or-later. Full text: [COPYING](COPYING), identical to [license/LICENSE](license/LICENSE). Preserve per-file notices. |
| Andrea Volpato's original film/paper profiles and direct derivatives, including baked print-preview LUTs; former experimental derivatives have been removed from the current tree | CC BY-SA 4.0 with the upstream preamble, preserved verbatim in [license/SPEKTRAFILM_LICENSE.txt](license/SPEKTRAFILM_LICENSE.txt). Attribution and changes: [bundled changelog](modern_UI/Spektrafilm/Spektrafilm/Resources/Licenses/Profiles-and-LUTs-CHANGELOG.txt). |
| Hanze Qiu's independently constructed product B&W profiles and grade/filter packs | The adopted upstream [README licensing table](https://github.com/JamesQiu2005/SpektraLab/blob/01d32a2b767fbdb447bbc3ab156dfa1f2388580c/README.md#credits-and-licence) assigns film/paper profiles to CC BY-SA 4.0. Preserve Hanze Qiu's [NOTICE verbatim](engine/resources_product/NOTICE.md) and the exact commit/hashes in [UPSTREAM.json](engine/resources_product/UPSTREAM.json). These profiles are independently authored, not Andrea Volpato's measured arrays. Fitted grade/filter packs are distributed with these profiles under the same upstream CC BY-SA terms, preserving their derivation record. |
| Apple's vendored metal-cpp | Apache-2.0; full text and copyright notices in [engine/third_party/metal-cpp](engine/third_party/metal-cpp/LICENSE.txt). |
| Colour-derived colour-science data | BSD-3-Clause notice now preserved in [license/Colour-BSD-3-Clause.txt](license/Colour-BSD-3-Clause.txt) and both app bundles. Exact historical bake inputs remain partly unidentified; see [data sources](license/DATA-SOURCES.md) and [array inventory](license/data-inventory.json). |
| Silverphase-controlled AI cover artwork and newly authored icon artwork | CC BY-SA 4.0 to the extent of contributor-held copyright. Attribution, exact scope and third-party exclusions: [artwork notice](license/ARTWORK.md); full legal text: [CC BY-SA 4.0](license/CC-BY-SA-4.0.txt). |
| Other inherited engine data, including Hanatos spectra and filter curves | Follow spektrafilm’s published repository GPL terms and retain upstream credits. Exact input comparisons and missing standalone contributor notices are recorded in [data sources](license/DATA-SOURCES.md); no new standalone grant is claimed. |
| Layerlight promotional icon | Separate proprietary app artwork, reproduced at the owner’s request for README identification and promotion only. Excluded from Silverphase GPL and CC BY-SA grants; see [related-app artwork](screenshots/related-apps/README.md). |
| Photographs, inherited screenshots and third-party designs | No new blanket grant. Historical UI captures are inherited reference material, not current product screenshots. See the [release review](docs/OPEN-SOURCE-RELEASE.md). |

The maintainer confirms (2026-10-31) that film covers were generated using AI
prompts and requests retaining the packaging-style images; available generation
records are in `modern_UI/design/film-artwork/`.
This provenance statement does not grant rights to third-party packaging.

Profile names identify materials; brand names and logos belong to their owners.
No trademark permission or manufacturer endorsement is implied. Generated images
that reproduce retail packaging still require a separate rights review.

## Source and binary distribution

The source repository for **this application** is
[akinal5765-byte/Silverphase](https://github.com/akinal5765-byte/Silverphase),
not either upstream repository. Distribute the corresponding source for the exact
binary revision, including modifications and build scripts, using a method
permitted by GPL section 6. A generic repository URL alone is not a written offer
or proof that the complete source for a particular binary is available.

Regenerate bundled notices with `modern_UI/Spektrafilm/Tools/bundle-licenses.sh`.
Both hosts package that directory. Keep About credits visible, preserve the full
licence texts, and record profile/LUT changes beside the data. Do not edit the
upstream licence or NOTICE to describe local changes.

The [GNU GPL text](https://www.gnu.org/licenses/gpl-3.0.html) and
[CC BY-SA legal code](https://creativecommons.org/licenses/by-sa/4.0/legalcode.en)
are authoritative. The release review records provenance limitations. Silverphase follows upstream
distribution terms for inherited data and preserves its notices; these notes do
not introduce an additional permission process.
