# Silverphase 原生渲染 API

[English](API-SPEC-callable-render-service.md) · **简体中文**

现行集成参考于 2026-11-18 复核。文件名沿用历史命名，当前产品没有可调用的 Python 服务。以 [spk_engine.h](engine/include/spektrafilm/spk_engine.h) 的声明为准；参数元数据和验证位于 [params.cpp](engine/src/core/params.cpp)。[早期服务规范](docs/history/API-SPEC-callable-render-service.md)保留旧探针、Python 路径及计时结果，不作为当前运行指南。

## 1. 接口边界

macOS 的 `EngineClient` 和 iOS 的 `MobileEngine` 调用同一个链接进应用的 C++/Metal 引擎。JSON 承载参数增量和分析响应；像素缓冲区和纹理通过原生结构体传递，不以临时文件承载 JSON-RPC 像素。

| 操作 | 原生入口 |
|---|---|
| 生命周期／数据根目录 | `spk_engine_create`、`spk_engine_destroy` |
| 查找方法与参数 | `spk_capabilities`、`spk_params_schema` |
| 打开场景线性 float32 RGB/RGBA | `spk_open`、`spk_open_device` |
| 替换同尺寸连续设备帧 | `spk_replace_device_frame` |
| 读取／更新参数 | `spk_get_params`、`spk_set_params` |
| 求解曝光／滤色组 | `spk_solve`（`exposure`、`filter_pack`、`both`） |
| 胶片与印相／复用符合条件的底片 | `spk_render`、`spk_reprint` |
| 分析／显示几何 | `spk_scene_latitude`、`spk_overscan_geometry` |
| 中间片／预览／查找表 | `spk_render_digital_intermediate`、`spk_preview_scan`、`spk_preview_stock_lut`、`spk_print_lut_table` |
| 输出转换 | `spk_output_transform` |
| 进度／取消 | `spk_progress`、`spk_cancel` |
| 释放资源 | `spk_result_free`、`spk_string_free`、`spk_session_release` |

头文件还声明了其他诊断和兼容入口；本表用于宿主集成，不是自动生成的完整 API 列表。

## 2. 参数层与缓存失效

`spk_set_params` 接收以扁平 schema 名称为键的对象，返回包含 `invalidated` 和已解析 `params` 的有所有权 JSON。原生校验拒绝未知参数、错误类型、无效枚举值和超范围数值。通过 `spk_params_schema` 获取准确的默认值、类型和范围，不要重复维护易过期的字段数。胶片配置解析和产品默认值可能使最终值不同于原始 schema 默认值。

- `shoot`：使胶片／底片失效，例如胶片型号、镜头滤镜、曝光、颗粒、场景曝光宽容度、片边、日期后背和组片的区域映射。
- `print`：保留符合条件的底片并重新运行印相／输出，例如相纸、放大机与滤色组、印相曝光、扫描控件和 Cineon DI 选项。

schema 的 `live` 标志描述可调性，不表示可以复用底片。结果的 `reprint`／`negative_was_cached` 标志显示是否实际复用。胶片配置的 `targetPrint` 记录声明的默认搭配；换用其他相纸可以渲染，但并不证明具有实测兼容性。

桌面端可累加的预处理字段都属于 `shoot`：

- `camera_prep_exposure_ev` 以档为单位，范围 −3 到 +3。
- `camera_local_tone_brights`、`camera_local_tone_darks`、`camera_prep_contrast`、`camera_prep_lift`、`camera_prep_gain`、`camera_prep_detail`、`camera_prep_vibrance` 和 `camera_prep_saturation` 的范围是 −100 到 +100。

这些字段默认均为零。既有编辑内容仍可使用四个 `camera_tone_*` 字段。相机预览测量和逐张照片的基准由宿主保存，引擎只接收一个有效预处理曝光值。

## 3. 所有权与错误

`cinestill_800t` 是采用的 `kodak_vision3_500t` 元数据别名，复用不变的基础乳剂和中性印相数据包，并采用静态照片胶片元数据及无防光晕背层的设定。在 `antihalation_mode: profile` 下选择 SpektraLab 的背反射光晕；显式强／弱／无选项保留 Silverphase 现有的高斯预设。`halation_headroom_ev` 是可累加的拍摄侧浮点参数（0–8 EV，默认 4）。只对背反射模型，在胶片曝光和片边合成前估算被裁切的场景高光；设为 0 则使用记录下来的光量。关闭光晕、光晕量为零或使用其他光晕预设时不起作用。

调用者所有的输入内存在打开调用期间必须有效，引擎会复制需要保留的内容。`spk_device_image.buffer` 必须是引擎所用 Metal 设备上足够大的缓冲区，使用紧密排列的 float32，首行为图像顶部；忽略 alpha。

成功返回的 `spk_result.texture` 已保留（+1）。`rgba16` 与其内存共享地址，在纹理继续被保留时有效。读行要用 `row_stride_px` 而不是宽度，设备纹理对齐可能增补填充。Swift 只能转移一次所有权；C 调用者使用 `spk_result_free` 释放。JSON 是借用还是应由调用者释放，以头文件为准；不得释放借用的 schema 或数据表。

检查每个 `spk_status` 和引擎错误文本。错误类型包括无效参数或用户输入、资源、不支持的设置、GPU、I/O、取消和内部错误。失败调用不是有效的图像结果。

## 4. 输入与输出语义

输入必须符合声明的色彩空间和传递函数标志。宿主经 ImageIO／Core Image 解码后提供场景线性 ProPhoto RGB float32。编码 RGB 在输入边界解码，曝光在线性光中运算。已渲染的 JPEG/TIFF 不提供仅适用于 RAW 的控件。

常规输出由宿主显式配置。经过画布／软打样／导出转换时保持工作空间语义，常规图像文件写入目标 ICC。引擎只返回像素和数据表，不写 JPEG、TIFF 或 `.cube` 文件。

## 5. 材料数据与求解

打包基础数据 `engine/resources/` 和产品覆盖层。引擎读取一个合并后的数据根目录，不会自动查找 `resources_product/`。应将采用的来源、配置和来源声明一起保留。

`spk_solve` 和场景分析独立于手动控件。印相补偿可以归一化胶片曝光，不要把曝光控件等同于输出亮度增益（见 AGENTS 陷阱 30）。可变反差相纸的等级由宿主一次性转换为滤色及印相曝光，不是替代色调曲线，也没有专用的 `paper_grade` 引擎字段。

## 6. 分辨率

原生渲染级别仍为 `live`、`preview`、`full`。ABI 支持这些名称，不代表界面必须提供三档画质选择。桌面使用预览与全分辨率的调度方式；移动端自动调整适合窗口的预览及可视区域细节。`preview_long_edge` 影响交互分辨率；导出方案的分辨率独立。桌面端「模拟尺寸」在宿主几何中确定裁切后的目标尺寸，并在 `spk_open_device` 前重采样。有效输入尺寸发生变化时须新建会话。颗粒和空间尺度取决于物理胶片画幅尺寸和当前像素间距。

## 7. 内存与并发

平台封装应串行执行会话操作。取消可以按头文件约定从另一线程发出。宿主应保留代次和选中项保护，避免迟到的结果覆盖不同照片。

CPU 句柄释放后，待执行的 GPU 命令可能仍引用引擎缓冲区。只有在提交并确认完成后才可复用；不能仅凭引用计数推断安全。分条渲染须显式配置。会改变尺寸的片边会重新生成下游分条计划；处理带的重叠边和最后一段不满的条带仍属于像素契约。分条与全图结果一致，不等同于通过独立物理对照验证。

## 8. 导出与中间片

完成的成片由宿主在目标转换后使用 ImageIO 写入。现行 Cineon DI 使用 `spk_render_digital_intermediate`：无色彩标签的 16 位对数 TIFF，采用 ProPhoto RGB 原色，片基位于码值 95；宿主提供固定 DI 查看 LUT 和预览。查看转换是 Cineon→ProPhoto RGB／Rec.709，不是相纸印相 LUT。对 DI 导出普通 RGB 时应用查看变换与目标配置。旧 `spk_export_di` 的密度／印相 LUT 行为为兼容性保留在 ABI 中，不是当前 UI 的输出包。

## 9. 验证

验收门槛及测试素材政策见[桌面验证指南](modern_UI/Spektrafilm/VALIDATION.md)。使用原生 GPU／数学检查、相关功能测试，以及宿主文件和像素检查。完整 XCTest 报告须包括跳过项。历史 Python 对照脚本需要显式的外部参考实现，已废弃的冻结参考不是构建或验收依赖。

## 10. 版本协商

`SPK_TRANSPORT_VERSION` 和 `SPK_SCHEMA_VERSION` 目前均为 1。能力响应字段必须可由宿主解码；schema 通过具名原生字段扩展。破坏性契约变化需要协调提升版本并更新宿主，不得静默重新解释已有名称。遵循[宿主与引擎契约](CONTRACT-frontend-backend.zh-CN.md)。

## 11. 输出转换与诊断

`spk_output_transform` 提供原生目标转换数据；转换调度和文件标签由宿主管理。`spk_memory_report`、`spk_build_info`、进度和节点计时用于诊断。编码耗时不能单独证明 GPU 完成时间。基准测试须记录系统负载与温度背景。

## 12. 场景曝光宽容度

`spk_scene_latitude` 测量介质与场景、建议高光／阴影回拉并求解拟合；不执行渲染，也不会静默应用建议。请求可按头文件设置 `highlight_pull_back`、`shadow_pull_back`、`rolloff`、`max_lift`、`norm`、`margin` 和用于稳健估计极端值的百分位数。只有有效拟合才返回可应用的 `params_delta`，通过 `spk_set_params` 应用。

双画面支持新增 `scene_latitude_split`（0…1）、`scene_latitude_b_active`、B 画面高光／阴影拐点（−24…24 EV）及余量（0…24 档）。这些属于 `shoot`。宿主分别为每张照片及其在组片中的区域确定场景定位，共用的相纸等级仍在印相侧处理。

## 13. 片边、日期后背与镜头滤镜

这些新增参数属于 `shoot`，且 `live: false`。准确默认值见 schema 与 `Params`；文本、EXIF 和画框也由宿主解析。

| 字段组 | 名称与语义 |
|---|---|
| 片边选择 | `overscan_active`、`overscan_format`、`overscan_mode`（`strip`／`filed`） |
| 形状 | `overscan_gate`（`auto`、`square`、`rounded`、`eared`、`shouldered`、`kicked`）、`overscan_holes`（`white`／`black`）、`overscan_carrier`（`none`、`black`、`open`） |
| 随机种子 | `overscan_camera_seed`、`overscan_frame_seed`：0…2147483647 |
| 曝光与标记 | `overscan_fog`、`overscan_leaks`：0…4；另有 `overscan_edge_text`；`overscan_f_number`：0…64 |
| 帧号／组片 | `overscan_frame_number`：0…99（0 为自动）；`overscan_pair` |
| 日期曝光 | `date_imprint_active`、`date_imprint_text`、`date_imprint_text_b`、`date_imprint_data_text`；`date_imprint_ev`：−2…8 |
| 日期布局 | `date_imprint_placement`、`date_imprint_style`（`lcd`、`dots`、`data`）、`date_imprint_size`：0.4…3、`date_imprint_corner`、`date_imprint_inset_x`／`y`：0…30 mm |
| 镜头滤镜 | `camera_filter`：空值、`w8`、`w11`、`w12`、`w15`、`w21`、`w25`、`w47`、`w58` |

画幅为 `135`、`135_half`、`120_645`、`120_6x6`、`120_6x7`、`120_6x8`、`120_6x9`、`135_xpan`、`120_6x12`、`120_6x17`。所有 135／常规 120 画幅均支持已建模的日期字模；120 日期位于片边，须启用片边。全景画幅没有日期后背。宿主应隐藏或禁用不适用选项，不能保证引擎接受的任一字段可绘制在所有画幅上。

`spk_overscan_geometry(session, &out_json)` 返回供显示映射使用、由调用者释放的几何 JSON。片边会改变渲染尺寸，须使用返回的几何及结果尺寸，不用固定边框百分比。镜头滤镜改变图像的曝光感度并带补偿；片边打印和日期后背使用未通过滤镜的感度。来源和假设见 `engine/resources_product/UPSTREAM.json` 和[片边来源说明](engine/tools/profile_sources/film_edge.md)。

### 连续相机帧

`spk_replace_device_frame(session, input)` 只替换已有会话的输入。宽高须完全匹配，每像素 3 或 4 个 float32 通道，使用会话的输入色彩空间。调用者的 GPU 写入必须在调用前完成；缓冲区仅在同步调用返回前借用。输入无效或上传失败时保留旧输入。参数、管线和材料状态保留；各档图像、底片、测光及场景统计均失效。只与材料相关的场景曝光宽容度校准保留。已有结果纹理继续持有原像素。会话操作仍串行执行；不新增参数／schema 字段，不改变文件渲染默认行为。

`spk_render_viewfinder(session, long_edge, result)` 以 256..1600px 渲染临时相机显示，不改已保存参数或三个文档级别。保留自有设备端底片，不使用 mmap 副本；结果纹理依旧持有不可变的像素。测光使用独立的会话输入，而不是显示尺寸。关闭自动曝光不执行无用的测光分析；仍可显式求解曝光。

### 独立的相机预览颜色采样

`spk_render_color_samples(session, out)` 使用临时参数与管线副本，将会话输入作为互相独立的颜色样本求值。关闭空间和随机操作、几何、自动曝光、场景曝光宽容度、高光重建及增强、片边与日期，以及反差蒙版分析；保留非空间 DIR、扫描器参考、胶片与相纸颜色和逐点印相 EDR。不改变输入、保存的参数或缓存的文档底片。结果所有权与普通 `spk_render` 相同。该入口用于预生成预览色表，不可替代考虑空间关系的照片显影。

## Lightroom Classic 文件集成（macOS 1.2.0）

此工作流完全在宿主侧实现，没有新增 C ABI 或 schema 变化。Lightroom 的 JPEG/TIFF 副本经现有支持 ICC 的解码器与 `spk_open_device`；保存使用普通全分辨率渲染，以及宿主的输出转换与 ImageIO 写入。引擎不发现 Lightroom、不管理其目录，不在磁盘上保留原片，也不关闭窗口或替换文件。

将外部渲染图像线性化，不等于逆转相机配置或色调映射，不能保证等同直接读取 RAW。宿主将初始输入与写回目标分开保留；保存前取消不会修改目标，但设置可以独立保存。TIFF 以 16 位写回，JPEG 以 8 位写回，均带 ProPhoto RGB 标签。支持范围是单张 SDR 照片。见[设置、重复编辑与限制](docs/LIGHTROOM-CLASSIC.md)。
