# Silverphase 架构

[English](ARCHITECTURE.md) · **简体中文**

现行实现概览，原文于 2026-11-18 复核，包含随后补充的图库与看图页边界。Silverphase 源自 Hanze Qiu 的 SpektraLab 和 Andrea Volpato 的 spektrafilm 模型。产品更名不改变源码或配置的署名。[文档索引](docs/README.md)列出现行指南；[早期架构文档](docs/history/ARCHITECTURE.md)保留较早的测量和说明。代码及 RFC 引用章节号，因此尽量保持编号稳定。

## 0. 产品的完整路径

Silverphase 的 macOS 和 iOS／iPadOS 均为原生宿主，共用一个 C++20/Metal 引擎。macOS target 仍叫 `Spektrafilm`，构建产物是 `Silverphase.app`；iOS target 为 `Silverphase`。两个平台都将引擎链入应用并加载包内数据。没有运行时 Python、stdio 服务、子进程渲染器或 CPU 渲染回退；Python 脚本仅用于开发。

```text
相册／文件
  → 平台 ImageIO／Core Image 解码 → 场景线性 ProPhoto RGB float32
  → C ABI 与 JSON 参数 → C++ 初始化和 Metal 胶片／显影／印相／扫描
  → 自有纹理 → 平台画布／几何／目标色彩转换
  → 宿主 ImageIO 写入 → 成片，或 Cineon DI 与查看用 LUT
```

| 边界 | 源码 |
|---|---|
| 原生 ABI、所有权、取消 | `engine/include/spektrafilm/spk_engine.h` |
| 参数名称、范围与缓存层 | `engine/src/core/params.cpp` |
| 配置与校准初始化 | `engine/src/core/` |
| GPU 分配与完成同步 | `engine/src/gpu/metal_gpu.cpp` |
| 管线及全图／分条执行 | `engine/src/pipeline/` |
| 原生 kernel | `engine/src/shaders/` |
| macOS 宿主 | `modern_UI/Spektrafilm/Spektrafilm/` |
| iOS 宿主 | `ios/Silverphase/Sources/` |

### 职责归属

宿主负责解码、文档、裁切与呈现、UI 调度、导出策略和文件写入；引擎负责胶片和相纸的初始化与成像。材料配置描述材料能力。胶片曝光前的场景定位以及印相后的输出余量，不得通过篡改实测配置来掩盖。

已弃用前后端双会话的职责划分。[宿主与引擎契约](CONTRACT-frontend-backend.zh-CN.md)描述现在的原生边界。修改共用全局文档前先说明。

### 延伸阅读

见 [macOS 工程](modern_UI/Spektrafilm/README.md)、[iOS 工程](ios/README.md)、[iOS 控件审计](ios/CONTROL-AUDIT.md)、[验证](modern_UI/Spektrafilm/VALIDATION.md)、[API](API-SPEC-callable-render-service.zh-CN.md)和 [AGENTS](AGENTS.md)。RFC 记录其写作时的设计决策；采用的上游源码即使引用某个 RFC 编号，也不代表本仓库拥有对应文件。

### macOS Lightroom Classic 外部编辑（1.2.0）

Lightroom 渲染一张已调整的 JPEG/TIFF 副本并发送 macOS 文件打开事件。`LightroomInput.currentSenderIsLightroom()` 检查发送应用；`Session.openFromLightroom` 保留隐藏的输入副本并打开专用单图编辑器。`TopBar` 使用「保存」代替导出，隐藏照片导航条但保留材料选择器。保存按完整分辨率调用 `Exporter.filePixels`，通过 `writeFinishedTexture` 原子替换 Lightroom 登记的副本，成功后关闭编辑器；出错时保留窗口。这是宿主侧文件流程，不是额外的引擎后端，也不需要单独安装 `.lrplugin`。

普通图像读取器解码 TIFF/JPEG 源文件的 ICC 传递函数，得到线性 RGB 数值；这不会逆转 Lightroom 的相机配置、色调渲染，也不能恢复场景辐射度。物理引擎仍以场景光假设运作；与直接读取 RAW 使用相同参数，不保证画面相同。不额外施加 Lightroom 专用的曝光补偿、逆色调曲线或更柔和的材料默认值。

隐藏文件 `.<filename>.silverphase-input.<extension>` 保留最初输入；对应 sidecar 保存编辑。Lightroom 登记的副本仅作为写回目标。复用同一路径会恢复最初保留的输入，接收新的 Lightroom 调整需使用新副本／路径。这些是私人文件，不进入仓库。不根据文件名猜测没有发送方或被转发的事件。不支持 HDR、PSD 或批量往返。配置和截图见 [Lightroom 指南](docs/LIGHTROOM-CLASSIC.md)。

## 1. 物理模型

场景光依次经历相机曝光和滤光、胶片曝光与光谱响应、显影／密度／颗粒、放大机与相纸显影，以及扫描／输出转换。正片直扫和 Cineon 中间片路径绕过相纸阶段。场景曝光宽容度分析提出场景定位建议，实际修改通过显式参数增量提交。

镜头滤镜（`camera_filter`：空值、w8/w11/w12/w15/w21/w25/w47/w58）修改胶片感度并补偿曝光，且使底片失效。滤镜不会影响片边打印机或日期后背的曝光。镜头扩散、光晕与印相眩光是不同效果，所在的物理阶段不同。

### 胶片曝光前的预处理

两个宿主都能在场景线性图像上调整影调、细节和色彩。引擎首先测光，局部控件在分块胶片工序之前使用共用的全帧基底。逐点曝光和色彩预处理在光谱上采样前执行。旧影调与场景定位数据仍可解码。

对于支持的 RAW，两端通过所选外观，将起始曝光拟合到嵌入的相机预览并保护高光。编辑记录按照片保存拟合 EV 和手动偏移。「预处理」剪贴板组复制匹配开关；「胶片」组复制测光方式与手动胶片曝光。宿主将拟合 EV 与手动偏移合并为拍摄侧可累加的曝光参数。

### 产品材料数据

`engine/resources/` 包含原有的 28 个基础配置。自行创作的实验材料配置和生成器不在受跟踪的产品输入中。维护者构建可选择加入由 Git 忽略的本地覆盖层；公开构建用 `SILVERPHASE_LOCAL_MATERIALS=0` 排除该层。只有打包了 `LocalMaterials/StockCatalog.json` 时，共用目录才会合并它。「实验」分类还含经 Negs 改编的 29 款公开 Fotufilm 配置。`engine/resources_product/` 保存采用的 Tri-X 400、HP5 Plus 400、T-Max 100、Acros II 和 Multigrade IV RC 数据、相纸反差等级数据包和来源。构建将产品配置覆盖到已打包配置目录。已有编辑中的旧 Tri-X／HP5 实验 ID 解析为已采用的型号；已退役的本地实验 ID 须在本地覆盖层保留对应配置。见[黑白材料来源](engine/tools/profile_sources/blackwhite.md)。

`channel_model: bw` 使用中性银影像并关闭多层彩色颗粒行为；通用单色解码结构为兼容性保留。银盐相纸没有已校准的彩色相纸 EDR 映射，因此关闭 EDR。00–5 级相纸在宿主转换为滤色和曝光补偿，从而可复用底片。这些配置及近似不能证明对所有药液工艺、光线、颗粒或真实胶片样片均准确。共用模型还用模拟的中性光谱归一化 Hanatos 适配区段和 DI 中性响应。启用 DIR 时，曲线准备与运行时采用匹配振幅的响应。放大机用已验证的中性滤色数据包，颗粒柔化按胶片空间的像素间距缩放。校准的来源和适用范围见[数据来源](license/DATA-SOURCES.md)。

### 胶片呈现

`overscan.cpp`／`overscan.metal` 以物理尺度实现片窗、片边、齿孔、雾翳、漏光、标记和日期后背的曝光。画幅包括 135、半格、645 到 6×9、XPan、6×12 和 6×17。是否支持日期后背取决于画幅：全景画幅不支持；120 日期位于边缘，须启用片边。

测光／高光统计使用画布扩展前的照片。`film_overscan` 在曝光／增益后执行，再经过常规胶片处理。`print_film_present` 和 `print_edge_light` 处理后段呈现。输出形状可以改变；`spk_overscan_geometry` 返回供宿主映射的几何。改变尺寸的全局阶段之后，分条执行器重建处理带计划。

桌面组片是引用两张照片的 `.spektrapair` JSON 文档。宿主合成场景线性输入，并解析画框几何和日期；组片配置与各来源的拍摄信息分别保存。区域曝光宽容度的 B 字段用于第二格。iOS 目前支持单张半格片窗，不支持双照片组片。[片边说明](engine/tools/profile_sources/film_edge.md)解释建模假设，不是实测的扫描器复现。

## 2. 运行时结构

macOS `Session` 处理选中项、异步解码、参数代次、撤销／sidecar、缓存与渲染调度。`EngineClient` 串行执行原生调用，将具有明确所有权的结果交给画布。`Session+FilmPresentation.swift`、`FilmCanvasInput` 和 `PairComposer` 在材料模型之外解析呈现与合成。「模拟尺寸」在胶片阶段前重采样线性输入。裁切目标解析为有上限的工作画框；尺寸改变后为预览和全分辨率导出重开引擎会话。设置按照片保存，不计入剪贴板与半格组片流程。已导出的桌面成片包含 `xmp:Rating`。

iOS `MobileDocument` 协调已导入照片、逐张状态、操作、设置和配方。相册导入在具有读取授权时查找所选资产的 RAW 资源；在复制到本地图库之前，可下载云端原片。`MobileEngine` 封装相同 ABI。自 1.2.0 起，应用内相机（`MobileCamera`）通过同一引擎显影后写入本地图库；Camera Control 控件和 `LockedCameraCapture` 扩展（`ios/Silverphase/CameraExtensions/`）把锁屏拍摄影像暂存到会话容器，再交给主应用，不在扩展进程显影。通过相对引用编译桌面共用源码 `StockCatalogCore.swift`、`ParamValue.swift`、`Geometry.swift`。`DesktopControlDefaults.json` 记录桌面默认值，`MobileDesktopContractTests` 检测偏移。其他移动控件源码属于平台专用，须单独审计。

iOS 1.2.1 增加默认的近似胶片取景：`MobileCameraFastLook` 用 `spk_render_color_samples` 预生成独立颜色样本，并给最新视频帧应用具 HDR 响应形状的 Metal 查找表。曝光与扩散仍是近似，系统预览与实验的原生 `spk_render_viewfinder` 仍可选。`spk_replace_device_frame` 复用原生会话的初始化。视频是经过 ISP 处理的 SDR，不等同于 RAW。静态照片显影和材料配置保持通常的语义。处理帧冻结与输入代次覆盖快门、镜头及人像模式切换；相机布局留在设备坐标系，控件可旋转。锁屏拍照采用系统取景，继承胶片且只提供测光／扩散控件。可选前台位置记录由主应用负责，并遵循导出策略。iOS 1.2.5 增加拍摄 EV 和格式／分辨率选择；拍摄配方将所选胶片、测光、扩散及胶片 EV 交给静态照片显影。应用内的印相演示使用原生引擎。验证与限制见 [iOS 1.2.5 说明](ios/releases/1.2.5.md)。

来源或会话发生变化时，让进行中的工作失效；过时结果不能覆盖当前照片。移动端导入／导出有模态进度，日常调整预览仍可交互。导入的照片保存在应用自有的 Application Support 本地图库中。`MobileLibraryStore` 原子保存有版本的清单，包括照片标识、原片的相对文件名、编辑配方、几何、评分、标旗与上次预览选择。无效清单保留，不得被空会话覆盖。原片跨冷启动保留；删除时先提交删减后的清单，再移除应用自有文件。预览 JPEG 位于 Caches，以编辑意图作为缓存键；撤销历史和 GPU 资源均为临时数据。

`MobileLibrary` 管理网格状态、原片格式筛选、多选、复制／粘贴和批量导出。单张照片先进入 `MobilePhotoDetail`；后者负责翻页、原图对比、快速选片、照片检查器和看图预览会话。编辑是独立入口，使用自己的渲染会话。应用内相机的缩略图也打开同一看图页，返回相机不改变图库筛选。单张编辑隐藏照片条；批量编辑只显示所选照片，并在一个可撤销事务中应用选定的调整组。裁切剪贴板只复制数值比例，按目标照片调整方向，保留目标照片自身的裁切中心、校直、90° 旋转和翻转。

## 3. 阶段分类

引擎区分逐点、邻域和全图阶段。分带执行融合可融合的操作，并附带邻域所需的重叠边；全局统计仍按全图处理。空间参数取自物理胶片尺寸和源分辨率，不取任意预览像素尺寸。

`shoot` 参数使胶片／底片缓存失效，`print` 参数可复用已显影底片。片边、日期后背、镜头滤镜和场景定位属于拍摄侧。宿主把相纸反差等级映射到印相参数。用错代次的缓存底片属于结果错误。

## 4. 内存模型

GPU 图像使用引用计数缓冲区。释放最后一个 CPU 引用，并不表示已经编码的 GPU 命令读完了数据。节点提交和完成边界决定缓冲区何时可以复用；保留同步边界与结果所有权。缓存留存与临时工作分配分别预算。

分条路径为符合条件的阶段限制临时空间，但依然存在全图阶段和输出平面。片边可能扩大这些平面，桌面端使用文件后备分配和缓冲池修剪处理。对数曝光与颗粒平面在最后一次使用后释放。选择开启的颗粒累加器别名路径必须保持像素完全一致，由 `accumulator_alias.cpp` 检查。

iOS 真机的缓冲池回收不会保留同时满足三个条件的缓冲区：工作已完成且引用数为零、至少 64 MB、至少是所请求尺寸的四倍。移动 JPEG 导出显式请求 256 行一条，使用小尺寸对比占位图，并在宿主图像转换前释放引擎输入、底片和缓冲池。默认条带行数为零，不会自行开启受限内存路径。内存限制仍取决于进程可用额度。Increased Memory Limit 须由实际签名描述文件授权，存在 entitlement 文件不能证明已获授权。

## 5. 构建与发布

Apple 芯片；macOS 15+，iOS／iPadOS 18+。当前本地工具链是 Xcode 27.1 和 Metal Toolchain。若已选中 Command Line Tools，可逐个命令设置 `DEVELOPER_DIR`。命令和产物见各平台 README。

`engine/build.sh all` 构建原生库、kernel、驱动与桌面资源覆盖层。桌面 Xcode 构建编译引擎 C++ 源文件，并使用预制 metallib。iOS `Tools/build-engine.sh` 为真机和模拟器编译同一份源码，根据源码、头文件、编译器、SDK 与脚本指纹缓存。两端都使用 Metal float32 的 safe／precise 标志和运行时数学探针。

桌面包的数据目录为 `Resources/engine`；iOS 使用 `AppResources/engine`，避免 Foundation 按根目录下的 `Resources/` 推断为旧式程序包。iOS 将基础中性印相校准与产品补充内容合并；桌面宿主应用自己的相纸等级映射。不得用产品补充库替换完整的校准数据库。

两个工程都编译同一个 `Silverphase.icon`。[图标说明](design/app-icon/README.md)索引获准使用的素材与设计历史。工程生成器使用可确定的相对文件标识。新增或移除源文件后重新生成；缓存、签名描述文件和构建产物不要入 Git。

许可证全文、产品声明、数据来源与配置变更记录随应用分发。`bundle-licenses.sh` 维护这些文件，`check-bundle-resources.sh` 检查桌面输入。`package.sh` 归档并签名应用、签名 DMG、提交公证、附加公证凭据，再以 Gatekeeper 的打开／主签名语境评估磁盘映像。脚本存在并不能证明已有经过公证的公开发布版本。不得向 `upstream` 推送。

## 6. 耗时分布

解码、输入色彩转换与上传、胶片显影、印相、宿主输出转换和文件写入各自耗时。`Session.LoadClock` 和 `core=native-metal` 仍用于诊断。GPU 调度编码耗时不等于执行耗时；必须单独测量完成时间。引用耗时或内存数据前，核对竞争负载和温度状态。

较早的计时数据保存在历史架构与注明日期的报告里，不是当前验收上限。已记录真机审计的范围见 iOS 指南；本文件不据此作出新的真机性能结论。

## 7. 前端

### 7.1 结构

macOS 采用 SwiftUI／AppKit、Metal 画布、浮动工艺检查器、底部胶片／相纸浏览器与照片条。布局以 [UI-SPEC](modern_UI/design/UI-SPEC.md) 和当前源码为准。iOS 采用原生导航、玻璃材质面板、刻度尺和紧凑材料浏览器；iPad 保持横向工艺导航和右侧检查器。手机先使用横向工艺导航，系统报告有铰链后使用 Duo 布局。见 [iOS 设计](ios/DESIGN.md)。

### 7.2 工艺控件与兼容性

界面流程为 **预处理 → 胶片 → 显影 → 彩色放大（印相）→ 扫描**。裁切（macOS 为「构图」）与片边是独立工具；macOS 将最后一阶段标为「扫描／输出」。匹配支持的 RAW 的相机预览亮度是预处理内的选项，不是一级工艺。诸如 `camera` 的历史标识符不是当前界面标签。没有独立的通用调色工具条。旧调整字段与 sidecar 结构可为兼容性保留；源码存在不代表功能对用户开放。目前未发布局部蒙版编辑流程。

### 7.3 分辨率

macOS 渲染交互预览，再通过会话／代次保护调度完整源细节。iOS 根据屏幕像素调整适屏画质，合并交互更新，按需逐步请求可视区域细节直至原始像素。可通过手势或菜单切换适屏和 1:1。移动端没有固定预览尺寸选择器，仍可配置低功耗行为。导出分辨率独立于预览，并受源尺寸和内存策略限制。

### 7.4 宿主职责与局限

宿主负责文件解码、元数据策略、文档、裁切几何、撤销、设置、进度和交付。不会通过修改实测材料数据来弥补输入解码或输出限制。移动端没有桌面的组片、自定义 ICC 安装、软打样和导出比较网格；详见控件审计。

### 7.5 色彩链

RAW 由 Core Image 解码为场景线性数据，编码 RGB 按配置／传递函数解码。工作输入为场景线性 ProPhoto float32。白平衡／镜头 RAW 控件只适用于 RAW。外部渲染的 TIFF 无法恢复相机原始辐射度，也不能逆转其他软件应用的外观。

画布和宿主颜色转换须遵循工作／输出空间；绘入工作空间纹理的 UI 固定色也要转换。桌面共用输出 shader 同时服务移动端。普通导出写入目标 ICC；Cineon 母版有意不嵌入显示 ICC。

macOS 1.4.0 的导出和输出软打样共用同一条全画质文件像素路径，包括缩放和目标转换。ProPhoto 工作画布不是 sRGB 软打样。末端 CAM16 转换在接近目标色域边界时开始压缩彩度，不是把全部彩度一起压缩；sRGB 色域外颜色仍无法原样再现。见 [macOS 导出指南](modern_UI/Spektrafilm/README.md#图像与输出边界)。

## 8. 原生引擎

### 8.1 目录结构

`core/` 管理配置、参数、光谱与色彩初始化、滤镜和缓存；`gpu/` 管理 Metal 资源；`pipeline/` 管理阶段执行、会话与 C ABI；`shaders/` 存放 kernel。基础与产品数据是两套分别受跟踪的输入。

### 8.2 C ABI

JSON 承载小型参数请求与响应，纹理／像素缓冲区使用有类型的原生结构体。结果、字符串和会话都有明确的释放函数。以 ABI 头文件及运行时能力和 schema 为准。场景曝光宽容度、片边几何和输出转换入口见 API。

### 8.3 GPU 层

没有备用 CPU 渲染器。分配、调度、复制、提交／同步完成和缓冲池复用，均须保留待执行工作及已有保留引用的输出纹理。真机与模拟器的纹理兼容路径不改变材料模型。

### 8.4 Kernel

使用 `-fmetal-math-mode=safe` 和 `-fmetal-math-fp32-functions=precise` 编译。原生数学探针在启动时拒绝不兼容的 metallib。引擎 kernel 不得继承画布的 fast-math 设置。配置 NaN 和矩阵方向按 AGENTS 中的已知陷阱处理。

### 8.5 缓存

初始化缓存避免因无关编辑重新生成光谱／印相／色域查找表。胶片／底片缓存降低印相改动成本。宿主缓存可在内存受压时逐出结果；测试应验证渲染完成，而不要求可逐出的纹理继续留存。缓存键包括会影响该阶段的所有参数。

### 8.6 验证

现行验收包括原生 GPU 冒烟测试、数学保护、定向引擎检查、XCTest 与基于清单的真实照片流程。完整套件须报告跳过项。全图／分条相等、重置不变性、默认值契约，以及文件的 ICC／位深检查回答不同问题；均不能证明独立的物理准确性。

冻结的 Python 对照验证不再是必跑项。历史脚本和容差保留供显式研究使用，不因此声称已针对当前修订执行。见[验证指南](modern_UI/Spektrafilm/VALIDATION.md)与 `performance/` 中注明日期的报告。

### 8.7 性能证据

报告输入、设备、负载、温度状态、配方，以及内存数据是采样值还是峰值。模拟器构建不验证真机导出内存预算或手势。[历史架构](docs/history/ARCHITECTURE.md)保留早期测量；[iOS 审计](ios/CONTROL-AUDIT.md)保留有明确范围的移动端证据。

### 8.8 导出边界

引擎返回像素、转换与 LUT 表，宿主负责写文件。成片 JPEG／PNG／16 位 TIFF 带所选目标 ICC。`spk_render_digital_intermediate` 返回使用 ProPhoto 原色的 Cineon 对数数据，片基码值为 95；宿主交付无色彩标签的 16 位 TIFF、固定 Cineon→ProPhoto／Rec.709 查看 LUT 和可选预览页。这些不是所选相纸的 LUT。旧 `spk_export_di` 密度／印相 LUT 支持仍留在 ABI 中，但不定义当前界面的 DI 输出包。

### 8.9 计时

节点计时通常测量 CPU 编码时间。要测 GPU 完成须显式计时。保持各节点名称和打开路径监测；不要为了改善只含编码耗时的数字而移除必要的同步。
