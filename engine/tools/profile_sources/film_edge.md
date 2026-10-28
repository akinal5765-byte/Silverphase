# Film presentation integration

Adopted from Hanze Qiu / SpektraLab commit
`01d32a2b767fbdb447bbc3ab156dfa1f2388580c` under GPL-3.0-or-later.
The native overscan C++ and Metal files remain unchanged; the surrounding
pipeline retains Silverphase's native session and export boundaries.
Hashes and adaptation notes are in `engine/resources_product/UPSTREAM.json`.

Framing precedes exposure. Film and print profiles are unchanged by presentation
controls. The lens-filtered scene sensitivity is kept separate from the bare
sensitivity used for edge fog and date illumination. Cached negatives retain
film layout for paper reprints and DI export. Neutral medium probes disable
both regional scene curves and presentation effects.

The independent film-edge inspector controls ten gate formats, brand markings,
perforations, carrier, fog, leaks and body/frame seeds. Dates can use captured
EXIF or custom text, with LCD, dot or shooting-data faces and appropriate gate
restrictions. Paired documents reference two source photographs; each has its
own placement, exposure meter and scene latitude, with shared film, development
and paper. Changing a shoot-stage control reopens the pair to refit both meters and
regional curves; print-stage edits retain the cached negative. Global geometry
does not apply to pairs. Source identities enter the
cache key, and nested paired documents are rejected. Imported documents with optional upstream per-hole print trims, output grades
or film-wide per-hole exposure scopes are refused rather than silently ignoring
those treatments. Silverphase uses one shared enlarger and print for the pair.

Native regression: `engine/tests/overscan_checks.py` covers disabled-path
identity, film codes, all gate formats, perforations, cached reprints, DI,
regional paired curves, striping and dates. `FilmPresentationTests` covers
legacy decoding, controls, framing, pair save/cache identity and scene-linear
composition. Reference Python parity needs the separate reference checkout;
these native regressions do not substitute for physical calibration or live
GUI inspection.

Final validation (2026-10-12): 137 native edge/date/pair checks passed. The full
Swift suite ran 537 tests with zero failures, including 46 skips for unavailable
original-photo fixtures. The subsequent pair shoot-stage meter refresh was
checked with the targeted presentation, parameter, clipboard and scene-placement
suite. The final app builds successfully. Synthetic application snapshots verify
simultaneous pair, film edge and date rendering; these are offscreen captures,
not live-window proof or real-photograph calibration. Python-reference parity
was not run because the separate reference checkout is unavailable.
