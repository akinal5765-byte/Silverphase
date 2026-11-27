# Silverphase · 数字暗房作品展示

**简体中文** · [English](README.md)

[简体中文主页](../../README.md) · [英文主页](../../README.en.md) · [下载](../BINARY-RELEASES.zh-CN.md)

四张展示卡均为 **2560 × 1600**、sRGB，由 Silverphase 的 Metal 引擎渲染，并非实体相纸扫描，也不是当前 App 的界面截图。模拟印相均启用了颗粒与光晕。照片来自获准展示的项目样片，不随卡片分发 RAW 原文件。

| 展示卡 | 配方与对照 |
|---|---|
| [01 · 同一张底片，两种相纸](01-paper-study.png) | 荷花，Portra 400，较测光基准增加 +0.67 EV。在 Portra Endura 和 Supra Endura 上印制同一张缓存底片，印相曝光设定均为 0.88。两种相纸分别用各自的内置中性标定。RAW 参考是 Apple 的显示解码结果，未应用胶片模拟。下排细节从宽 4096 px 的渲染结果中直接取相同位置的像素。 |
| [02 · 三个场景，三款胶片](02-film-studies.png) | 荷花：Portra 400／Portra Endura；白鸟：Acros II／Ilford Multigrade IV RC；店面：CineStill 800T／Kodak Vision 2383。这是独立案例，并非受控的胶片对照。 |
| [03 · 入夜之后](03-800t-night.png) | CineStill 800T／Kodak Vision 2383，较胶片测光基准增加 +0.67 EV，印相曝光设定为 0.84，35 mm 颗粒为 1×，启用胶片光晕。完整渲染为 7008 × 4672；两处细节按 1:1 裁取，无放大或后期锐化。 |
| [04 · 画框以外](04-film-edge-covers.png) | 使用 Silverphase 的 135 胶片带模式渲染的 Portra 400 荷花。穿孔、边缘标记和帧号均由引擎生成，不是在排版时叠加。四张历史封面取自早期应用内素材库；现行设计见网站单独的封面网格。 |

荷花、白鸟与夜间店面三张原始照片均获维护者授权作为项目案例，记录见 [2026-10-31 样片与捕获记录](../../screenshots/current/manifest.json)。这项许可仅涵盖本项目展示，不意味着照片可供一般用途再利用。[作品授权范围](../../license/ARTWORK.md) · [桌面原始界面档案](../../screenshots/current/README.md)

四张素材库封面由 **Silverphase 贡献者／akinal5765-byte** 创作，并为展示重新调整尺寸与排版。项目拥有权利的部分使用 CC BY-SA 4.0；胶片型号、商标标志与可辨认的第三方包装不在该许可内。不声明与胶片制造商有从属关系或获其背书。网站上的 Layerlight 独立图标指向作者的专有应用，不在 Silverphase 的许可范围内。

[暗房笔记](https://akinal5765-byte.github.io/Silverphase/site/notes.html#comparison-lab)并列展示 Portra Endura 与 Supra Endura 的印相。链接内的 PNG 保留了 RAW 参考、采样位置和原尺寸细节裁切。[照片集](https://akinal5765-byte.github.io/Silverphase/site/study.html)将各张成片与对应的相机原始参考并列展示。

### 原生界面与六组附加照片案例

网站图库新增的六个场景均用 Silverphase 1.3.1 引擎在 Apple Metal 上渲染。同一场景的两张图采用一致的几何变换。RAW 参考是 Apple 默认显示解码结果，不是未经处理的传感器数据。模拟印相保留颗粒与光晕。WebP 导出保留完整画面，采样框只出现在链接的注释对照图板上。原照片是发布样片清单中获准使用的项目案例，不分发 RAW 原文件。

| 场景 | 胶片 | 相纸 | 胶片曝光 | 印相曝光设定 |
| --- | --- | --- | --- | --- |
| 蒸汽机车 | Fujifilm Eterna 500（Fotufilm） | Kodak Vision 2383 | +0.84 EV | 0.91 |
| 红色屋檐 | Fujifilm Pro 160NS（Fotufilm） | Supra Endura | +0.67 EV | 0.96 |
| 荷叶露水 | Fujifilm Reala 100（Fotufilm） | Fujifilm Crystal Archive Type II | +0.67 EV | 0.97 |
| 枝叶中的白鸟 | Ilford HP5 Plus（Fotufilm） | Ilford Multigrade IV RC，2 级 | +0.50 EV | 1.00 |
| 云下的黄色列车 | CineStill 400D（Fotufilm） | Portra Endura | +0.34 EV | 0.94 |
| 穿云的落日 | Kodak Vision3 250D | Kodak Vision 2383 | +0.34 EV | 0.89 |

曝光偏移相对于每个场景各自的测光基准。场景、配方均不相同，不应当作固定场景的胶片横评。源自 Fotufilm 的实验配置经 Negs 移植，参见[配置来源及许可](../../license/DATA-SOURCES.md#experimental-fotufilm-profiles)。

黑白案例的两张印相使用同一份缓存的 Acros II 底片与 Ilford Multigrade IV RC 相纸，胶片曝光为 +0.333 EV，使用 TH-KG3 放大机。00 级采用 199.0 黄滤色与 0.5323 补偿印相设定；4 级采用 39.1 洋红滤色与 1.334 补偿印相设定。这些都是 App 随附的相纸反差等级配置，没有通过额外调整夸大差异。两张图均以 4096 × 2731 渲染，启用颗粒与光晕，且无画面叠框。

Mac、iPhone 和 iPad 截图均来自运行中的原生 App，分别取简体中文和英文界面。iPhone 竖屏使用获准展示的黄色列车照片，iPad 横屏与 Mac 使用获准展示的荷叶露水照片。iPhone 与 iPad 截图已在 iOS 26.1 上通过 XCTest 核查；除了隔离的截图样片流程，App 代码不作改动。iPad 图省略了系统状态栏。两版网站首页均未使用合成照片、样机或旧的渐变截图。

[首页印相回放](https://akinal5765-byte.github.io/Silverphase/#develop)以静态的原片与印相对照开场。动画使用同一张荷叶照片的两张经色彩管理的 SDR sRGB WebP 作为两端；它们由 Metal 引擎连续生成，分别是 Reala 100（源自 Fotufilm）／Fujifilm Crystal Archive Type II 印相（+0.67 EV，印相曝光设定 0.97），以及通过 `spk_preview_scan` 从缓存底片生成的负片阶段预览。网站移植了 Silverphase 2.2 秒的相纸着色器；备用视频也由该网页着色器渲染。浏览器并不运行胶片模拟引擎。

网站的[胶片封面网格](https://akinal5765-byte.github.io/Silverphase/#film-covers)展示了当前应用内插画的缩小版。封面统一为 16:9，用胶片各自的配色搭配原创字体编排与版式，而非照搬厂商包装。参见[提示词与来源记录](../../modern_UI/design/film-artwork/README.md)。

[网站媒体来源](../site/media-provenance.json)记录已发布的照片及界面衍生素材，八张新封面衍生图也已列入[胶片封面清单](../../modern_UI/design/film-artwork/generated-stock-covers-v2-manifest.json)。这些记录不授予新的权利。
