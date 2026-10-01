# SpektraLab 上游移植评估 — 2026-10-01

核对的上游：`4cab8b6a91fea88a1f23f5f00f03e35dd9ab38f0`（1.2.2）；本地 HEAD：`b70889f9a90c320b621dab2fdb38fc2737ffa400`，包含当前未提交改动。最初只读评估；用户随后确认范围并要求推进，现已按本文范围完成工作区移植。尚未提交或推送。

## 结论

可以分功能移植。不要整体覆盖或整批合并：本地 Session、Exporter、Renderer 和界面已经分叉，并有尚未提交的性能、导出及曝光菜单改动。GPL-3.0-or-later 代码可以在保留许可及作者署名的前提下复用；CC BY-SA 数据继续保留原许可。移植提交应注明源提交，保留原 Git 历史，绝不推送 upstream。

## 推荐顺序

| 顺序 | 内容 | 上游依据 | 本地情况与适配 |
|---|---|---|---|
| 1 | develop 期间修改参数丢失的竞态修复 | `5cd7a69`，RFC-027 §5.1 | 本地仍用 open 完成后的 `sidecar.params` 重置 scheduler。应记录实际送入 open 的参数快照，避免将期间的新设置误记为已经发送。保留本地异步 decode、取消旧渲染和内存生命周期优化。需移植能观察成片的回归测试。 |
| 1 | 导出临时文件完成后替换目标；批量期间锁定输入 | `2f6e460` | 本地写文件仍直接使用目标 URL，缺少上游 `.partial-*` 完成后替换流程。移植到本地 `nonisolated` writer，不能恢复上游主线程写盘。锁定规则应覆盖选择、粘贴和参数编辑。 |
| 2 | CLI / MCP | `3cbbb35`，RFC-026 | 本地没有 Agent 模块。可移植 AgentAccess、AgentCLI、MCPServer、JSONValue 与工具分发框架；AgentSchema 必须按本地真实 sidecar 重写，不能引用尚未存在的 SceneLatitude、ContrastMask、EffectStrengths。App 入口、设置、CLI 安装脚本需改为 Silverphase。 |
| 按差额评估 | 独立效果强度 | `cf8c316` + `43b70ed`，RFC-025 | 本地已经有 halationAmount、DIR 的 colorSeparation，以及 grainSizeScale 和镜头/放大机柔化强度，不应整体移植。实际新增差额是颗粒振幅 grain_amount、乳剂散射 halation_scatter_amount、眩光振幅 glare_amount，以及独立的颗粒 sublayer 开关。颗粒振幅与本地颗粒尺寸、乳剂散射与镜头柔化是不同控制。只在需要这些差额时适配字段和控件，保留本地现有控制；默认 1 保持原输出。 |
| 3 | 按组复制设置，多选粘贴 | `5cd7a69`，RFC-027 | 本地只复制整个 FilmParams，粘贴只作用当前帧。移植分组模型、离线 sidecar 更新和缓存失效。上游七组包含本地尚未实现的 Scene Placement 与 Mask，应按已存在字段裁剪。As Shot 白平衡保留目标帧自身数值，不能复制来源帧的 solvedEV。 |
| 3 | 裁剪、缩略图和导航器一致性修复 | `3fcffc4` + `912df4b` | 按本地布局适配裁剪边缘滑动、比例切换、遮罩缩略图和输入焦点规则。不要搬整套 v4 左右栏。使用上游 SurfaceAgreementTests 的契约检查各表面，区分“全图带裁剪遮罩”和“实际裁后画面”。 |
| 4 | Scene Latitude / Scene Placement | `14fc708` + `9aac338`，RFC-023 | 本地有研究 RFC，但缺少 latitude_fit、scene_latitude 代码。需要 C ABI、MSL、参数、缓存、Swift 解码与可视化一起移植。测量可以先落地；主动 Fit 改变胶片前场景，应作为显式可选控制。不能把固定 AE 阈值当作介质边界。 |
| 5 | Cineon Digital Intermediate | `9b73c4b` + `67e48be` + `37225a9` + `819a299` | 是完整新输出路径，不是现有 `spk_export_di` 的小补丁。需要 digital_intermediate 常数、渲染入口、缓存、Cineon 导出和显示解码表同步移植。必须包括后续 0.6 gamma 修复，否则会消除各胶片反差差异。与物理负片方向相容，但不能替代原有相纸输出。 |

## 两个容易误判的地方

CLI / MCP 复用 Session 类和 sidecar，并非实时控制正在打开的窗口。上游 RFC-026 明确把“驱动打开的窗口”留到第二阶段；headless 进程有自己的 Session 和 engine，可能与 GUI 同时占用 GPU 和内存。迁移后应验证 headless 调用得到的文件与 GUI 同参数输出一致。

上游 Tone Mask 已撤回：`FeatureFlags.toneMask = false`，AgentSchema 将其设为只读（`62f2084`）。不建议重新启用，也不能为了搬 CLI 顺带引入旧遮罩实现。RFC-030 的逐胶片颗粒仍等待真实 datasheet 数据，不是已完成的新功能。

## 验证边界

UI / clipboard / agent 适配先跑针对性测试；真实图像用来验证打开期间编辑、批量输入锁定和预览/导出一致性。新增 engine 字段、kernel、DI 或 render ABI 必须构建配套 dylib/metallib、同步 bundle，并跑适用 parity 与新功能测试；默认设置需保持兼容。新源文件须重新生成 Xcode 项目。集成边界再跑全套测试，检查 fixture 实际被执行。

当前本地定向测试存在 test bundle 加载失败，上一轮应用构建成功。移植前应先修复或隔离测试环境，不能把未执行的测试计为通过。

## 源码与设计记录

- https://github.com/JamesQiu2005/SpektraLab/blob/4cab8b6a91fea88a1f23f5f00f03e35dd9ab38f0/rfc/RFC-026-cli-and-mcp.md
- https://github.com/JamesQiu2005/SpektraLab/blob/4cab8b6a91fea88a1f23f5f00f03e35dd9ab38f0/rfc/RFC-027-settings-clipboard.md
- https://github.com/JamesQiu2005/SpektraLab/blob/4cab8b6a91fea88a1f23f5f00f03e35dd9ab38f0/rfc/RFC-025-decoupled-effect-strengths.md
- https://github.com/JamesQiu2005/SpektraLab/blob/4cab8b6a91fea88a1f23f5f00f03e35dd9ab38f0/rfc/RFC-028-digital-demask-and-invert.md
- https://github.com/JamesQiu2005/SpektraLab/blob/4cab8b6a91fea88a1f23f5f00f03e35dd9ab38f0/rfc/RFC-030-film-character-contrast-and-grain.md

## 用户选定范围与整体方案

2026-10-01：用户选定新增效果控制、复制粘贴、导出、裁切、场景宽容度、数字中间片，要求整体评估。CLI/MCP 不列入本轮实施范围；Tone Mask 与逐胶片颗粒数据仍不列入。

### 建议的四个集成阶段

1. **可靠性底座与裁切/导出修复。** 先隔离测试包加载问题，再修 open 参数快照竞态、批量期间修改输入、原子落盘、裁切边缘和焦点行为，以及各显示表面的几何一致性。保留当前解码、后台写盘、取消旧渲染、全分辨率与内存优化。输出画面和现有配方保持原语义。
2. **增量效果控制与场景宽容度。** 补颗粒振幅、乳剂散射、眩光强度及颗粒 sublayer 开关；沿用本地颗粒尺寸、光晕和 DIR 控制，若增设 DIR 开关须与强度独立保存。先完成宽容度测量，再接显式 Scene Placement/Fit。默认场景映射关闭；测量与主动修改场景分开呈现。旧 sidecar 的新增字段有兼容默认值，旧图不得因升级自行改变。
3. **分组复制粘贴。** 引擎/sidecar 字段稳定后确定分组，覆盖此次新增控制。复制设置与放置意图，不复制 solvedEV、拟合曲线、来源帧 As Shot 数值。目标帧重新测光与拟合，支持当前帧和选中帧，未打开的帧写 sidecar 并清失效缓存。一个当前帧粘贴对应一次 undo；跨多帧 undo 不作为此次移植隐含承诺。若要提前移植，先支持已有组，新增组随字段落地补齐。
4. **数字中间片整条链路。** 配套移植负片去色罩/反转、Cineon 编码、0.6 gamma 修复、显示变换、导出与配方选择、缓存区分和测试。作为相纸印相之外的输出选项，正片不开放不适用的负片反转。DI 使用时按上游规则禁用不适用的印相和 Scene Placement 环节，保留原设置供切回相纸时恢复；界面应解释当前不可用状态。可选蓝色补偿先保留默认关闭，不能自动纠正材料数据。

### 共同依赖与验收

- 所有新增渲染字段进入参数 delta、缓存失效、undo、复制、保存和导出；不能只接控件。
- 裁切同时牵涉显示、导出、宽容度统计与物理颗粒尺寸。沿用本地“裁切后是否重算物理效果”的开关语义；不因移植静默改变测光是否看 crop 的现有约定。统计的画面范围须能读懂，切换时失效缓存并重测。
- 宽容度的边界是该测量方法的**色调**边界，不保证阴影颜色可恢复。不能将 Fit 当作曝光模式的替代品，或承诺灰掉的阴影能恢复原色。
- DI 是模型派生的数字负片解释，不是相纸打印，也不是对真实扫描仪输出的完全复刻。显示变换与文件编码分开，避免将预览 tone curve 烘进 Cineon 文件。
- 旧 sidecar 的默认 render 不变；强度 1 保持原路径，强度 0 的行为可验证；默认 DI/Placement 关闭。DI 输出和相纸输出的缓存键必须区分。
- 四个阶段各自跑针对性测试，engine 变化执行适用 parity；集成边界跑全套含真实 fixture 的测试并做真实窗口 QA。测试包无法加载时不能以编译成功代替测试通过。

整体可行，主要工程量集中在场景测量/拟合和 DI 两条引擎到 UI 的完整链路；复制和导出会反复碰到 Session，所以采用小补丁适配，不覆盖上游整文件或整套 v4 界面。


## 已实施与验证（2026-10-01）

代码来源为上述 SpektraLab 1.2.2 快照，以文件级三方适配保留 Silverphase 分叉。没有覆盖本地镜头/放大机柔化、粒径、显影对比度、DIR 强度或异步导出与内存优化；没有修改实测胶片/相纸资源。新增 Cineon 视图 LUT 保留上游文件名和作者归属，随应用检查并随 DI 导出。

### 已落地

- 曝光菜单恢复六种选择，关闭 AE 明确显示“关闭自动曝光（RAW 基准）”；中央加权可以显式选择。旧 sidecar 仍使用原默认测光。
- 新增颗粒振幅、分层颗粒开关、乳剂散射振幅、DIR 开关、眩光振幅。已有反射光晕和 DIR 强度继续使用本地物理控件；DIR 上限维持 1.4，避免最先失去单调性的胶片进入不可靠范围。
- 场景宽容度测量和显式场景置放（高光/阴影拉回、有效 Fit、拒绝原因），默认关闭。面板说明统计完整输入，裁切不静默改变测光。
- 分组复制粘贴覆盖已有和新增物理字段；多选目标保存 sidecar、使缓存失效，各目标重新测光/拟合。As Shot 保留目标相机数值；当前帧整组粘贴可一次撤销。修复 develop/open 期间编辑被误记为已发送的竞态。
- 导出使用临时文件完成后替换目标；批量期间冻结选择、粘贴和编辑。保留后台全尺寸读回及 ImageIO 写盘；DI 预览先在 GPU 缩小。
- DI 可在相纸选择中选择，正片不开放；纸张切回时恢复原设定。Cineon 主文件为 16 位未标记 TIFF、带视图预览页；两个固定视图 LUT 同目录共享。普通 TIFF/JPEG 导出 DI 的显示视图。蓝色补偿默认关闭，在设置中显式开启。
- 胶片条、选择网格、导出网格/列表使用各帧自己的裁切遮罩及方向。裁切后的物理粒径重算保留本地开关，并补齐源帧/裁切长边的比例。直方图改用画布同一几何采样，避免把裁掉的区域计入显示统计。
- CLI/MCP 不在本次范围；Tone Mask 没有开放界面，相关模型/引擎依赖仍默认关闭。

### 验证结果与限制

- 新增功能定向组：54 项通过；裁切表面 3 项通过。裁切直方图回归先显示红，再修复至绿。DI 与剪贴板的新增端到端测试在素材缺失时使用明确标注的合成编码 TIFF，不声称验证真实 RAW 解码。
- 旧调色接口与打印 LUT 的定向复查通过；旧密度归一化 C ABI 和 Swift 适配仍保留用于表格 parity，产品 DI 导出已经改为 Cineon。
- `engine/build.sh all`、GPU smoke、安全浮点 math guard 通过。新 `engine/tests/upstream_controls.py` 核对全部原生扩展的精确 schema，并验证零强度、复位、只读宽容度测量和有限 DI 输出。
- 对移植前 HEAD 的独立引擎 A/B：Portra 400、Gold 200、Provia 100F，分别开启/关闭颗粒，默认输出逐像素一致。已有粒径/八种相纸对比度、四种柔化滤镜及各自复位检查通过。
- 全套最终运行：467 项、42 项跳过、3 条失败断言（2 个 CanvasViewTests 用例）。两用例在独立的移植前代码快照同样失败：`testTheCollapseIsMeasuredAndTheCanvasKeepsUp`（2 条）和 `testTheHoverBandIsCentredOnThePillItReveals`（1 条）。没有将这些失败改成 skip 或放宽断言。
- macOS 测试宿主无法读取 Documents 源码，完整测试在临时镜像执行。源码扫描原先将 `/private/tmp` 和 `/tmp` 前缀混用，现改为枚举相对路径；另将已有导出菜单的 9 pt 字面值迁到等值 Theme 令牌，保持外观。
- 冻结的 Python fork/oracle 及其环境当前缺失。找到的 Andrea 原始参考树没有此 parity 所需的 `model.colour_baked` 和 service 包，不能冒充冻结参考；六项 Python-reference parity 尚未执行。原生 A/B 和新功能 gate 不能替代这项限制。
- 用户明确接手操作/视觉验证；不再继续真实窗口自动操作。渲染快照已生成，但真实窗口交互不列为已验证。

完整测试日志位于 `/tmp/silverphase-final-integration.log`；移植前画布复现日志为 `/tmp/silverphase-baseline-canvas.log`；原生控制、物理控件和柔化检查分别为 `/tmp/silverphase-native-final.log`、`/tmp/silverphase-physical-controls.log`、`/tmp/silverphase-diffusion-controls.log`。

### 复制设置交互调整（Lightroom 式选择弹窗）

根据用户后续要求，从输入面板移除剪贴板区块。编辑菜单、画布右键和 ⇧⌘C 统一打开独立勾选弹窗，提供全选、全不选、取消及确认复制；仅确认时更新剪贴板及下次默认勾选。⇧⌘V 直接把已确认项目应用到选中照片。弹窗捕获来源照片的设置快照，取消不修改原剪贴板。

- 应用构建成功，未执行视觉或实际操作验证，由用户负责。
- CopySettingsDialogTests、SettingsClipboardTests、SettingsClipboardSessionTests 共 21 项通过。
- 来源快照回归测试在故意改为确认时读取当前照片后出现两项断言失败；恢复快照实现后通过。
- 本轮只变更界面和剪贴板请求状态，没有引擎变更。

### 多选与导航条右键修正

用户反馈多选网格没有粘贴入口，导航条右键缺少复制粘贴，复制弹窗用了系统默认控件样式。现将设置复制粘贴菜单同时接到导航条和多选网格：多选时复制禁用，粘贴保留；右键操作保持现有批量选择。粘贴可用条件及执行逻辑依据 pasteTargets，不要求一定有已打开的画布帧。复制弹窗改用 Theme 标题/说明字体、RailRows/ToggleRow、surface/primarySurface 按钮、主题分隔线与表面，并把弹窗宽度纳入 Theme.Metric。

新增多选回归测试先在旧实现失败，修复后通过；复制弹窗、剪贴板模型/集成与 ModernCalibrationTests 共 30 项通过。应用构建成功；没有进行实际操作或视觉验证。

### 复制弹窗的玻璃与布局修正

用户提供的截图显示弹窗是实底，且参数栏的标签左/开关远端布局过于松散。现在采用两列紧凑选择项，沿用共享 CheckBox 的视觉形状但放在文字前方；文字也可切换。标题及来源收紧，全选/全不选位于选项标题行，底部显示已选数量和取消/复制。

外壳复用 EditorChromeSurface，使用 Theme.modalGlassWash 并清除 sheet 的不透明呈现背景，保留 macOS 26 以前系统材质以及减少透明度降级。全局 UI-SPEC §2.2.1 明确玻璃的表面归属、背景所有权、禁止嵌套玻璃和选择型弹窗布局；删除两处旧的玻璃禁用描述，design/README 同步指向新规则。Apple 原生 API 文档链接在规范内。

24 项复制状态/模型与设计规范测试通过，应用构建成功。未进行实际操作或视觉验证；最终玻璃观感和布局由用户检查。

### macOS 模态玻璃宿主与标题结构

用户确认 SwiftUI sheet 内的玻璃仍是实底。Apple presentationBackground 文档明确说明 macOS sheet 始终不透明；此前“清除 sheet 背景即可”的实现和规范判断有误。已改为 CopySettingsPresentation 管理透明、无标题栏的 AppKit NSPanel，经父窗口 beginSheet 保持模态；NSHostingView 承载原有共享玻璃内容，取消/确认由请求状态驱动关闭。支持键盘焦点和 Escape，旧请求不能取消新请求。UI-SPEC 和 design/README 已修正对应平台限制。

标题使用 Font.railTitle，下一行是“从 [文件名] 复制以下设置。”(Font.caption)；选项头使用 Font.modernSectionTitle，右侧“全选 | 清除”是 Font.label 文字动作。不按参考图放大字体。

透明宿主/取消状态、剪贴板集成和 ModernCalibrationTests 共 19 项通过，应用构建成功。透明宿主测试在临时镜像故意设为 isOpaque=true 后失败；恢复透明配置再次验证。测试未将面板显示到屏幕，未进行视觉操作验证；实际玻璃观感仍由用户验证。

### 最终材质方向：浮动工具玻璃，模态任务沿用系统

用户确认按组件语义区分材质。复制设置恢复原生 SwiftUI sheet，保留当前标题、来源句、全选/清除与两列勾选布局；移除 CopySettingsPresentation 透明面板、自绘弹窗玻璃与专用 wash token，并删除已无对应实现的透明宿主测试。复制请求、确认、取消、勾选记忆和多选粘贴语义未改变。顶栏、浮动工具面板与检查器的 EditorChromeSurface 实现保持不变。

UI-SPEC §2.2.1 和 design/README 已更新：浮动导航及工具层保留原生玻璃，模态弹窗优先系统呈现，内容区域保持清晰表面。前两次试图通过透明宿主让弹窗明显透图的方案已撤回，以本节为最终方向。

30 项复制弹窗状态、剪贴板模型/集成与 ModernCalibrationTests 通过；应用构建成功。未进行运行中的视觉或操作验证，由用户负责。

### 背景设计语言收敛

用户反馈设置、复制弹窗、工具面板和顶栏的背景呈现像三套语言。源码确认设置页有 Theme.cardFill 的自绘渐变，复制弹窗使用原生 sheet 表面，而 EditorChromeSurface 在系统玻璃下叠加了 60% 黑底。

已去掉设置页的独立渐变，由系统窗口背景承载，与原生复制弹窗保持同一表面语义。顶栏和圆角工具面板复用同一个 regular 玻璃分支，不再叠黑底或额外 tint；边界统一到 Theme.chromeEdge。减少透明度分支使用 Theme.windowSurface(系统窗口背景色)，旧系统只使用 regularMaterial。布局、按钮、内容图表和照片像素保持原有规则。

UI-SPEC 与 design/README 同步明确两个背景角色：系统窗口/模态表面，及浮动导航/工具的系统 regular 玻璃。统一色彩来源及规则，不要求透过不同照片内容的表面呈现完全相同像素。

ModernCalibrationTests 和 CopySettingsDialogTests 共 12 项通过；应用构建成功。未进行实际操作或视觉验证，背景观感由用户检查。

### 可读性修正：顶栏和工具面板共用深色玻璃

用户确认移除黑底后亮照片上的说明及刻度失去可读性，并要求顶栏与工具面板必须统一，拒绝将顶栏保留较透明而给工具面板另一套较厚材质。

现两者全部共用 EditorChromeSurface：regular 玻璃、Theme.chromeBacking 的既有 60% 深色衬底、共享边缘、同一文字层级；只保留平直/圆角的形状区别。说明与刻度使用的 Theme.dim 从 #898989 提亮到 #B5B5B5，统一改善小字可读性。旧系统也使用同一衬底；减少透明度分支依然统一。设置窗口和复制弹窗继续由系统呈现，未再改成透明面板。

UI-SPEC 和 design/README 已撤回“regular 下禁止衬底”的绝对规则，改为统一可读性规则。这是本产品对密集摄影工具的选择，不宣称是 Apple 为 regular 指定的透明度，也不套用 clear 的 35% 暗化建议。

12 项设计规范和复制弹窗状态测试通过；应用构建成功。没有运行中的操作或视觉验证，亮/暗照片上的实际观感由用户检查。

### 全局勾选框对齐规则

用户要求勾选框与其他控件对齐并纳入全局规范。旧实现使用 28 点点击目标与 10 点方框之差来计算行尾负边距，而实际布局容器宽 16 点，导致可见方框右移 6 点。已改为共享 checkboxTrailingInset，按布局容器与可见方框计算；参数 ToggleRow、拍摄时设置、导出预览选项共用，右侧可见边缘与数值框及菜单的内容边界对齐。

点击区域扩展另用 checkboxHitOutset，按布局容器扩至 28 点；不再以可见方框扩展导致实际目标过大，也不影响布局。复制弹窗前置勾选布局不套行尾补偿。UI-SPEC §2.16d 已明确可见边缘、墨迹带与点击目标三者的职责。

ModernCalibrationTests、点击目标尺寸检查与复制弹窗状态共 13 项通过；应用构建成功。未执行实际操作或视觉验证，由用户检查。


## 统一背景与现代共享控件（2026-10-01）

用户确认推进全局设计规范。保留顶栏/工具面板共同的 regular Liquid Glass、
60% 黑色可读性衬底与 Ink 层级,设置和复制弹窗继续使用原生背景。
画布空白改为独立、不透明的中性 sRGB #303030;窗口/空画布/导出预览、
Metal clear/letterbox 与 backing layer 共用来源,Metal 值重新编码到 ProPhoto。
不改变照片像素或物理引擎模型。

共享菜单、单位选择和数值框改为平整圆角矩形;动作按钮保留胶囊。
删除控件的凸起/凹陷渐变,统一 default/hover/pressed 填充与细边界。
复选框加明确勾号,保留之前修复的可见右边缘对齐、独立 28pt 命中区和行高。
UI-SPEC §2.2–2.3、§2.12、§2.16d 与设计 README 同步。

针对性验证: ModernCalibrationTests 8、LayoutTests 16、CopySettingsDialogTests 4、
RendererTests.testOffscreenRenderShowsGroundOutsideImage 1,共 29 项通过。
标准 app 构建成功。按用户要求未做操作/视觉验证;玻璃可读性、控件观感由用户确认。


## 材质选择条去除整体托盘（2026-10-01）

FilmChoiceStrip 去除整条 EditorChromeSurface 和额外横向内容缩进。
胶片/相纸切换保留独立共享玻璃外壳;材料卡片、分类标签使用独立中性深色背景。
胶片、相纸、原片扫描、DI 共用 MaterialChoiceButtonStyle,选中为橙色细边框,
不再整卡反白。目录、分组、自动滚动、参数选择以及图片导航条交互不变。
字号和尺寸沿用 Theme token;UI-SPEC §2.2.3 记录规则。
未进行操作与视觉验证,由用户确认。

验证:标准 app 构建成功;ModernCalibrationTests 8 与 StockListTests 6,共 14 项通过。

## 按用户效果图重做材质浏览器（2026-10-01，取代上一轮仅去底板的方案）

顶部工具行承载胶片/相纸、分类、收藏、最近使用、搜索、卡片/列表、卡片大小与翻页。
不再把切换块和分组标题夹在材质卡片之间。窄宽度以分类菜单和浏览选项菜单降级,
保持工具行高度;外壳共用 EditorChromeSurface。卡片图片区按用户要求暂留空白,
名称与类型/感光度有独立字体角色,选中框/勾号/收藏星标分别表达状态和动作。
照片导航添加同高度工具行,两种底部条共同使用 modernBottomStripHeight = 184pt
(28pt 工具行 + 8pt 间距 + 148pt 内容)。已有画布遮挡计算引用同一高度。

MaterialBrowserLibrary 以 ID 存储收藏和最多 20 项最近使用,UserDefaults 持久化;
Session 的胶片、相纸、扫描和 DI 选择入口记录使用。搜索与分类/收藏/最近使用取交集。
浏览方式、卡片大小与材质页签持久化;搜索和当前筛选是临时 UI 状态,不会改渲染参数。
列表为横向多列紧凑行;翻页根据实际 scroll geometry 偏移计算并在边缘置灰。
卡片大小复用 ScrubSlider 的 trackOnly 工具栏模式和 28pt 目标区域,不引入第二套滑杆。

目录生成器补充 nominalSpeed / speedUnit / speedSource,20 个摄影胶片条目携带标称速度。
静态胶片显示 ISO,电影原片按厂家口径显示 EI;相纸和印片胶片不继承拍摄感光度。
Portra 800 的 push1/push2 仍显示标称 ISO 800,迫冲级数由名称表达。
这些是 UI 目录元数据,没有改 engine/resources/profiles 的测量数据或曝光逻辑。
来源:Kodak Professional 技术资料索引 https://www.kodakprofessional.com/en-gb/node/133 ;
Fujifilm Professional Film Data Guide https://asset.fujifilm.com/www/us/files/2020-04/9cdee030ab7fc76bbcfddbcd38650038/ProfessionalFilmDataGuide.pdf ;
Kodak camera films https://www.kodak.com/en/motion/products/camera-films/ ;
EI 示例 https://www.kodak.com/content/products-brochures/VISION3-50D-5203-7203-technical-information.pdf 。

验证:统一高度回归在原 72/92pt 规则下为红;感光度回归在旧目录缺少字段时为红,
修正后为绿。StockListTests 10、ModernCalibrationTests 8、LayoutTests 16、
FrontendPolicyTests 17、DigitalIntermediateTests 14,共执行 65 项:64 通过、1 跳过。
跳过项是 FrontendPolicyTests.testTheZoomLabelIsMeasuredAgainstTheNativeFrame,
因为镜像测试目录没有 A7m3/DSC03710.ARW。标准 app 构建成功,git diff --check 干净。
本轮没有运行 app 操作、截图或视觉验证;视觉与交互实测按用户要求交给用户。

## 用户纠正后的简化与材质外壳（2026-10-01，取代上一轮 184pt 双工具栏规则）

导航条移除新增的照片/数量/文件名工具栏,仍为纯照片缩略图。空图库由
Session.showsBottomStrip 隐藏底部内容,Session.bottomChromeOcclusion 为零;
EditorWindow 观察可见性变化并刷新画布遮挡,避免空图库仍留一大块底部空间。

材质浏览器改为整条一个 EditorChromeSurface,工具行不嵌套玻璃。
外壳沿用顶栏与工具面板共同的 regular 材质、深色可读性衬底和墨色。
胶片/相纸、分类与浏览方式按钮共用 Theme 中的 ToolbarSelectionButtonStyle,
选中用顶栏导航语法的 accent 文字/图标,删除局部白胶囊与白矩形选中背景。

按用户新增要求移除搜索、卡片大小滑杆和翻页按钮;滚轮/触控板承担横向浏览,
自动定位选中材质保留。删除无调用的 trackOnly 滑杆变体及翻页状态/计算。
卡片固定 144×112pt,封面占位由 72pt 缩到 48pt,保留两行名称与感光度说明。
整条高度由 184pt 缩到 164pt(8pt 上下内边距、28pt 工具行、8pt 间隔、112pt 卡片)。
照片导航缩略图采用 164pt 高度,视觉高度与整个材质条一致,不复制其工具行。
列表改为两行列,保持外壳高度;收藏、最近使用、ISO/EI 元数据及选择规则保留。
UI-SPEC §2.2.3 和设计 README 已纠正。

验证:空图库 regression 在 deliberately broken 的“始终显示”分支上为红,
隐藏和遮挡检查同时捕获错误;恢复正确分支后为绿。
StockListTests 10、LayoutTests 16、ModernCalibrationTests 8、CopySettingsDialogTests 4,
共 38 项通过,无跳过;标准 app 构建成功,git diff --check 干净。
按用户要求未运行 app 操作、截图或视觉验证。

## 材质卡片比例与单行名称（2026-10-01，取代上一轮卡片尺寸）

卡片从 144×112pt 改为 128×108pt,卡片内边距为共享 space4。
封面高度由可用宽度和 16:9 比例推导(120×67.5pt),取代固定 48pt 的扁长占位。
图片区仍暂留空。名称使用单行短名称,移除厂商品牌前缀,保留迫冲等型号信息;
完整目录名称保留在悬停提示和无障碍标签中,原始 stock 名称与 ID 不变。
删除名称后的重复选中勾号,由 accent 边框和无障碍 selected 状态表达选择。
字号沿用 chooserCard/caption,名称与元数据之间使用 space2,不压缩字体。
底部材质条与照片导航共用 160pt 高度,整体玻璃外壳及简化控件规则不变。
UI-SPEC §2.2.3 与设计 README 同步更新。

验证:短名称回归在旧名称行为下为红,修正后为绿;StockListTests 11、
ModernCalibrationTests 8、LayoutTests 16,共 35 项通过,无跳过。
标准 app 构建成功,git diff --check 干净。按用户要求未运行 app 操作、
截图或视觉验证。

## 卡片圆角、对齐与图片占位（2026-10-01）

修复材质卡片误用控件圆角的问题:卡片恢复共享 modernCardRadius 9pt,
面板沿用 modernContainerRadius 16pt。图片区裁切由全局 nestedRadius
按外圆角减内缩推导,卡片模式为 9−4=5pt,轮廓使用 continuous。
工具行删除额外 8pt 水平缩进,与卡片列表共用外壳左边界;首个按钮的
8pt 内容内缩与卡片文字的 8pt 内缩对齐。图片区内缩 4pt,文字内缩 8pt,
图片/文字间距 4pt、名称/元数据间距 2pt,均取共享 token。
图片区添加白色与淡色 photo 图标占位,便于用户检查比例、留白和裁切圆角。
尺寸仍为卡片 128×108pt、底部 160pt,全局 UI-SPEC 同步记载嵌套圆角规则。

验证:app 构建成功;StockListTests 11、ModernCalibrationTests 8、LayoutTests 16,
35 项通过,无跳过;git diff --check 干净。未执行 app 操作或视觉验证。

## 收藏字形与独立图片圆角纠正（2026-10-01）

卡片收藏和顶部收藏筛选使用同一 RoundedFavoriteStar 轮廓,尖端和内凹角
使用曲线连接;字形统一为 14pt。卡片按钮保留 28pt 透明命中区,
距右上角 space2,没有底板。未收藏为空心,收藏为 accent 实心。
独立图片裁切使用共享 modernControlRadius 4.25pt,保留 space8 留白。
纠正上一轮“图片圆角随卡片内缩推导”为 1pt 的规则:只有同一表面的
内描边才适用 concentric 内缩公式,独立图片按内容语义使用共享圆角。
UI-SPEC 同步修改。app 构建成功,ModernCalibrationTests 8 与 LayoutTests 16,
共 24 项通过,无跳过;git diff --check 干净。未运行 app 操作或视觉验证。

## Complete catalog packaging artwork (2026-10-01)

Generated 25 additional images with built-in imagegen, using text only and no
reference images. Together with the approved Portra 400 v2, 26 illustrations
cover all 28 material entries; Portra 800 Push 1/2 reuse the base stock artwork.
Paper and print-film prompts do not invent camera ISO ratings. Legacy JPGs remain.
Full prompts, template and aliases are in design/film-artwork/.

Stock.packagingArtworkURL resolves generated resources independently of legacy
catalog cover metadata. Cards and lists share cached 448px ImageIO thumbnails;
hover and favorite changes do not repeatedly decode full-resolution originals.
Existing proportions, margins and corner radii remain. Favorite marks over
artwork use light outlines and a subtle dark shadow, without a backing plate.
Scan and DI retain placeholders.

Validation: the all-material artwork regression failed with a deliberately nil
mapping, then passed with the correct implementation. StockListTests 12,
ModernCalibrationTests 8 and LayoutTests 16: 36 passed, none skipped. App build
succeeded; all 26 generated assets match their bundled copies byte for byte,
and aspect ratios pass. A source scan launched from Documents failed on privacy
permissions; the mirror-directory rerun passed. No app operations or visual QA.

## Virtual workflow artwork (2026-10-01)

Added text-only imagegen labels for Digital Intermediate and Film Scan / No Paper
Print, without fictional brands or camera ISO. Full prompts and filenames are
in design/film-artwork/generated-workflow-manifest.json. MaterialBrowserChoice
now resolves both stock packaging and virtual workflow artwork, sharing cached
thumbnail rendering, rounding, margins and favorite-mark contrast.

Validation: the virtual-image resource regression failed when only stock URLs
were resolved, then passed with both workflow mappings. StockListTests 12 and
ModernCalibrationTests 8: 20 passed, no skips. App build succeeded; both images
match bundled assets byte for byte. No app operations or visual QA.

## Photo navigator toolbar and library marks (2026-10-01)

The user approved reusing the material browser panel structure for navigation.
Modern navigation now shares the 160pt glass shell, 28pt toolbar, spacing and
108pt content height. Thumbnails retain their image aspect and selection frames;
no filename or metadata captions are added to individual photos. The toolbar
shows filename/selection count, capture aperture/shutter/ISO, and copy/paste.
Single-frame EXIF uses Session's background read. Batch EXIF reads in the
background, showing common values or mixed fields and omitting absent fields.
Exposure times above one second retain fractions instead of integer rounding.

Thumbnail overlays provide 0-5 rating and unflagged/pick/reject menus. Empty
controls appear on photo hover; applied marks remain visible. Hidden menus do
not accept pointer input. FrameMarks writes atomic LibraryMarks files separately
from render sidecars, preserves the source image, clamps ratings, and reports
write failures. Marks are not copied/pasted or removed by render reset.
UI-SPEC and design README now describe the revised navigator structure.

Validation: persistence regression failed with deliberately broken writes, then
passed with the implementation restored. SelectionModelTests, LayoutTests,
ModernCalibrationTests and SettingsClipboardSessionTests: 43 passed, none skipped.
App build succeeded. Documents privacy restrictions affected one source-scan run;
the mirror-directory rerun passed. git diff --check clean. No app operation or
visual validation; the user handles that verification.

## 首次成片的分层显影动画评估（2026-10-01）

核对 Andrea Volpato 的 spektrafilm `main`，提交
`3bb2c2d2801ff68b92019cf1dbcbb133d60832bc`。找到明确实现：
[`polaroid_animation.py`](https://github.com/andreavolpato/spektrafilm/blob/3bb2c2d2801ff68b92019cf1dbcbb133d60832bc/src/spektrafilm_gui/polaroid_animation.py)，
由 GUI 的 `controller_layers.py` 在首次显示 output 时调用。
这确实是动画，不能确认它是否就是用户记忆中的那段演示。

实现从最终 RGB 构造光学密度（`-log(img**2.2)`），拆成中性密度和
黄／品红／青三个色彩层，再构造 receiver、silver、anti、warm、stain
五个视觉层。各层用不同的延迟 sigmoid 和短暂脉冲混合，随后指数还原
RGB。GUI 默认播放 1600 ms、32 ms 一帧，只对不超过 150 万像素的图
启用；结束时恢复原始成片，后续参数更新不重播首次显影。

这些层是从成片推导的动画层，不是引擎中实测胶片或相纸的乳剂子层，
也没有随时间计算真实显影化学动力学。不能将其描述成“真实负片逐层
冲印”。但相比本地当前沿横向亮带混合负片、纸白和成片 RGB 的效果，
它更符合画面整体从浅到深、颜色逐渐稳定的显影体验。

建议移植其密度分层和时间曲线到 Metal 展示层，保留负片作为开始状态，
短暂转入纸白，再让密度与颜色在整张画面上连续浮现，移除横向亮带。
本地纹理是编码 ProPhoto 数据，不能直接照搬面向显示 RGB 的 gamma 2.2
假设：动画应在明确的显示颜色空间内计算，再接现有显示管线。最终帧
必须直接使用原始成片纹理，避免动画 clamp/gamma 改变正式输出。

无需将九层完整图像驻留，也不需要逐帧重新运行引擎；可以预先计算少量
全图归一化统计，其他逐像素量在 fragment shader 中重建，时间系数由
Renderer 的现有绘制时钟驱动。这里尚未测量 GPU 成本，不能承诺帧率。
首次流程保留现有触发范围；参数修改、切图、取消、Reduce Motion 和
全分辨率结果抵达时均应正确终止或平滑衔接。无相纸及 DI 输出不要使用
纸张显影隐喻。移植代码需保留上游作者和 GPL 许可记录。

本轮仅完成源码核对与方案评估，未修改动画或运行应用视觉验证。

### 分层显影实施与验证

用户确认推进后，已将上游的 sigmoid、延迟上升、暂态脉冲和中性／CMY
密度层移植到 Canvas/Shaders.metal，源码保留作者、源提交和 GPL 署名。
适配采用本地 ROMM 分段传递函数在 ProPhoto 线性域计算密度，固定密度
归一化代替全图 maxima，避免 CPU 读回和九张额外纹理。动画不修改
引擎输入、介质数据或导出路径。尾段平滑回到原始值，结束分支直接采样
原始纹理。没有运行 Python，也没有引入 Python 运行时依赖。

纸张动画改为 2.2 s 的整张分层浮现，移除横向光带及双重时间缓动。
DI 采用 0.35 s 扫描交叉淡入，无相纸直接显示成片。保留现有第一张负片
等待用户冲印的入口，不新增加载门槛。Reduce Motion 跳过动画，运行中
开启也终止；清除负片同时清除动画时钟。参数变化取消待冲印状态，异步
负片结果校验请求时的参数、引擎代次及当前照片。对比和 Space 优先使用
解码原图，不把负片误作原图。全分辨率替换不重启动画。

验证：新增“全图同时显影”GPU 测试在旧光带 shader 上出现三次左右像素
不一致断言失败，移植后通过。RendererTests 21 项及相关 CanvasViewTests
3 项共 24 项通过，无跳过。根目录 build/DerivedData 应用构建成功。
扩大运行 CanvasViewTests 全类时，收栏动画计数及已移除的悬停 tab 数量
两个测试失败（共三条断言），不计作本轮通过。未修改这些旧布局测试。
git diff --check 通过。未做应用操作或视觉 QA，由用户验收；尚未测量
实际窗口帧率，因此不报告性能提升数字。

## GitHub 提交前集成检查（2026-10-01）

本轮按引擎扩展与应用工作流／统一设计两组整理。保留原始 Git 历史和
Andrea Volpato、Hanze Qiu 的署名，目标远端仅为 Silverphase 的 origin。
生成图保留完整提示词清单；DI 表格保留上游来源说明。

最终应用构建成功。完整测试执行 492 项：448 项通过、42 项跳过、2 个
已在移植前快照复现的 CanvasViewTests 用例失败（共 3 条断言）；失败为
收栏时画布 resize/draw 计数和已移除 hover tab 的数量假设。未静默跳过
或放宽这些断言。缺少固定照片和未显式启用的性能用例仍计为跳过，不
声称完整真实 RAW fixtures 已验证。

原生扩展 gate、GPU smoke 与 math guard 再次通过；此前三胶片、颗粒
开／关的独立移植前 A/B 默认像素一致记录仍保留。Xcode 项目生成检查、
打包资源检查与 diff 格式检查通过。冻结 Python oracle 缺失，所以六项
reference parity 仍未执行。操作与视觉验收由用户完成。
