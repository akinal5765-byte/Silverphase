# Silverphase documentation

Current index, reviewed 2026-10-28. Silverphase is an independent derivative of
Hanze Qiu's SpektraLab and Andrea Volpato's spektrafilm. Current source and the
platform guides govern shipped behavior; RFCs and dated reports retain their
original scope. Documentation review is not a new performance or visual audit.

| Need | Current entry |
|---|---|
| Product, origins, licensing, basic builds | [中文](../README.md) / [English](../README.en.md) |
| Whole-product implementation | [ARCHITECTURE.md](../ARCHITECTURE.md) |
| Working rules and debugging traps | [AGENTS.md](../AGENTS.md) |
| ABI, JSON, ownership, tiers, Cineon, film edge | [API reference](../API-SPEC-callable-render-service.md) |
| Host/engine invariants and shared-platform changes | [Contract](../CONTRACT-frontend-backend.md) |
| Desktop structure/build/export | [macOS engineering](../modern_UI/Spektrafilm/README.md) |
| Desktop layout | [UI-SPEC](../modern_UI/design/UI-SPEC.md) |
| Desktop acceptance and private photo fixtures | [VALIDATION](../modern_UI/Spektrafilm/VALIDATION.md) |
| Mobile build, import/export, diagnostics and memory | [iOS engineering](../ios/README.md) |
| Mobile layout and controls | [DESIGN](../ios/DESIGN.md) / [CONTROL-AUDIT](../ios/CONTROL-AUDIT.md) |
| B&W profile origin and limitations | [B&W notes](../engine/tools/profile_sources/blackwhite.md) / [provenance](../engine/resources_product/UPSTREAM.json) |
| Film edge/date-back model | [Film-edge notes](../engine/tools/profile_sources/film_edge.md) |
| Production icon and design iterations | [Icon guide](../design/app-icon/README.md) |
| Image/data/software licenses | [Bundled notices](../modern_UI/Spektrafilm/Spektrafilm/Resources/Licenses/README.txt) |
| Current integration verification | [2026-10-28 report](../performance/VALIDATION-REPORT-2026-10-28.md) |
| Earlier implementation and measurements | [Historical snapshots](history/) / [RFCs](../rfc/) / [dated reports](../performance/) |

The root architecture/API/contract were refreshed for the two-host native product.
Their preceding versions are preserved verbatim after a historical-scope banner
in `docs/history/`. Older section references can be resolved there. AGENTS retains
numbered debugging traps with an explicit historical/current distinction.

Do not recreate a retired Python environment, deleted baseline or old two-rail UI
just because a historical document describes one. Current acceptance uses native
checks plus host workflows; private real-photo fixtures stay outside the repo.
