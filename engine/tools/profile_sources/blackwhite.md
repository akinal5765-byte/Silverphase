# Adopted black-and-white materials

Silverphase uses Hanze Qiu's SpektraLab Tri-X 400, HP5 Plus 400, T-Max 100,
Acros II and Ilford Multigrade IV RC profiles unchanged. Sources, assumptions
and exact adoption hashes are preserved in `engine/resources_product/NOTICE.md`
and `UPSTREAM.json`. The original NOTICE ships verbatim in both applications.

The four film stocks use the upstream single-layer grain path with strength
multipliers 1.70, 1.49, 0.74 and 0.64 respectively. These are inherited modelling
choices, not new photographic calibrations. Multigrade grades 00–5 use the
upstream fitted filtration and exposure-compensation packs; grade 2 is the
default (C=0, M=0, Y=68). Eight Wratten lens filters are available independently.

Self-authored Delta, FP4, XP2, Fomapan and other approximation profiles, their
curve samples, generators and product tests were removed on 2026-10-31. They
are excluded from public builds. Maintainer builds can stage a private ignored
overlay; its archived experimental materials remain selectable locally. The source history and historical
licence/change records remain preserved.

The three established migration aliases for old Tri-X, HP5 and neutral B&W
paper IDs remain, mapping to the adopted versions of those materials. Other
experimental IDs require the local overlay; without it the native loader
reports a missing profile rather than selecting a donor stock. Existing edit files are not rewritten by this cleanup.

Validation: native `product_blackwhite.py`, `camera_filters.py` and
`paper_grades.py` cover the four supported films and adopted paper. A green
internal consistency check is not an independent real-film oracle.
