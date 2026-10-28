# Silverphase app icon

The approved icon is the horizontal two-layer design: orange film beneath a silver-white photographic print. It uses the rounded Layerlight-family silhouette with two layers, a shared center axis and native glass materials.

The production source for both macOS and iOS is `modern_UI/Spektrafilm/Spektrafilm/Silverphase.icon`. Regenerate it with `python3 modern_UI/Spektrafilm/Tools/make-icon.py`. Both Xcode projects compile this same document with `ASSETCATALOG_COMPILER_APPICON_NAME = Silverphase`; there is no separate iOS copy to drift.

SVG layers contain geometry and material gradients only. The document declares Display P3, so the generator converts the design's sRGB colors before writing SVG values. Apple's renderer supplies glass, refraction, lighting, shadows, appearance variants and the platform mask. `previews/v6-default.png` and `previews/v6-dark.png` record the approved native iOS rendering. `Silverphase-v6.icon` is the approval snapshot.

Earlier `Silverphase-v2` through `v5` documents, generators and preview images are design history, not alternate production inputs. Only the shared production document above is compiled into either app.
