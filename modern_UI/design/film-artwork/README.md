# Silverphase stock artwork

The built-in material cards are flat 16:9 illustrations designed for Silverphase, not photographs or replicas of commercial packaging. The stock name identifies the simulated material, not an affiliation with its manufacturer. Each rendering profile keeps its own stable ID, settings and library entry. Four alternate-source profiles and two Portra push profiles reuse their corresponding stock illustration.

## Reusable text-only prompt

> 生成一张{胶片／印片／相纸}卡片封面，型号为「{型号}」。以这款材料经典包装的标志性配色为依据，重新设计一张有独立视觉风格的封面；字型、色块比例、构图和抽象图形自由发挥。只做平面包装图形，不加照片场景，不出现厂商 Logo 或版权文字。16:9 横向，平面正视满版；外缘保持直角，由应用处理圆角。保留轻微印刷纸质感，照顾缩小后的可读性和边缘安全区。只排入提供的型号和{目录中有可靠来源的 ISO／EI，可省略}，不编造规格。不传参考图，输出一张完整图片。

Only use verified ISO or EI when the stock catalog provides one. Papers and print stocks do not carry a photography speed. The prompt defines a shared format, not a shared color, typographic treatment or visual composition. Inspect the actual images for text, unexpected logos and readability before conversion. The [per-stock manifest](generated-stock-covers-v2-manifest.json) records the actual prompts rather than claiming that every image used identical wording.

## Derivatives and checks

- The app (macOS and iOS/iPadOS) bundles 57 stock illustrations as **1440 × 810** sRGB JPEGs; `FilmCovers/StockArtwork.json` maps all 63 public IDs to those images. The website uses eight **800 × 450** WebP derivatives from the same approved masters. Both are exactly 16:9. The two clean workflow-label images are separate and unchanged.
- To update the series from separately stored, reviewed PNG masters, run `python3 tools/stock-artwork.py --prepare /path/to/batch-plan.json /path/to/approved-masters` (requires Pillow only for generation). The plan contains `generator`, `references: false`, `items` (each with `id`, `stage`, `use` and the actual `prompt`), and `aliases` (alternate catalog ID → canonical ID). Masters are named `<id>.png`. Do not commit the private source masters or reference images.
- Verify the source and site derivatives without Pillow using `python3 tools/stock-artwork.py --web`. For the native distribution pipeline, supply the app resource directory with `--resources`. After changing derivatives, also refresh `python3 tools/inventory-release-media.py` and run `python3 tools/check-open-source.py`.

## Earlier collections

The previous packaging-style manifests, previous prompt and the prior artwork revisions remain in Git history; the manifests are kept here for historical provenance, not runtime lookup. The live stock selector does not fall back to old cover assets. The two workflow-label images retain their [separate provenance](generated-workflow-manifest.json). See [artwork scope and attribution](../../../license/ARTWORK.md) for project-controlled contributions and third-party exclusions.
