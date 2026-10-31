# Silverphase macOS 工程

本目录是 Silverphase 的 SwiftUI／AppKit 应用工程。Xcode target 和部分
内部路径仍叫 Spektrafilm；产品名称为 Silverphase。项目保留 Hanze Qiu
的 SpektraLab 原生移植基础及 Andrea Volpato 的 spektrafilm 模型与配置。
来源和许可见 [仓库说明](../../README.md)。

## 当前结构

- `Spektrafilm/Model/Session.swift`：异步解码、引擎会话、参数调度、渲染缓存、
  多选、剪贴板、撤销及照片状态。
- `Spektrafilm/Service/EngineClient.swift`：直接调用 C ABI。Service 路径名称
  是历史命名；没有 Python 服务、stdio 代理或运行时子进程。
- `Spektrafilm/Canvas/`：Metal 画布、ProPhoto 显示、几何、直方图和分层显影。
- `Spektrafilm/Panels/`：浮动工艺面板、胶片／相纸条和照片导航条。
- `Spektrafilm/Export/`：导出配方、软打样、后台纹理读回和 ImageIO 文件写入。
- `Spektrafilm/Resources/`：引擎资源、目录、包装插画、DI 视图 LUT 和许可。
- `SpektrafilmTests/`：独立 XCTest target，同时编译应用及引擎源码。
- `Tools/`：工程生成、资源检查、验证及签名／公证／DMG 打包工具。

界面使用单一现代布局：顶栏、浮动工艺面板、底部胶片选择／照片导航条。
Metal 画布保持窗口尺寸；浮动控件的遮挡仅改变适合窗口的可见区域。
没有另一套传统界面或独立的通用调色栏。历史 sidecar 的旧调色信息仍有
兼容读取路径。当前布局规范见 [UI-SPEC](../design/UI-SPEC.md)。

## 构建

Apple Silicon、macOS 15+、安装了 Metal 工具链的 Xcode（本机 27.1）。若选中的是 Command Line Tools，给以下命令设置 `DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer`。仓库根目录执行：

```sh
engine/build.sh bundle
xcodebuild -project modern_UI/Spektrafilm/Spektrafilm.xcodeproj \
  -scheme Spektrafilm -configuration Debug \
  -derivedDataPath build/DerivedData build
```

输出 `build/DerivedData/Build/Products/Debug/Silverphase.app`。`engine/resources/`
和 `engine/resources_product/` 的配置及来源受版本管理；产品配置在打包时覆盖到同一 profile 目录，纸等级表及原始声明一并随包。
Metal 库由 `engine/build.sh` 编译，并同步到
应用 Resources/engine。资源检查拒绝缺失数据，但不自动重新烘焙配置。

添加／删除 Swift、Metal 或 engine C++ 源文件后执行：

```sh
python3 modern_UI/Spektrafilm/Tools/gen-project.py
python3 modern_UI/Spektrafilm/Tools/gen-project.py --check
modern_UI/Spektrafilm/Tools/check-bundle-resources.sh
```

构建没有 Python 环境依赖，工程／目录生成脚本只使用 Python 标准库。
`Tools/make-smoke.py` 属于旧 Python fork 的素材生成流程，当前不作为
验证入口；新素材的选择与隔离由 `Tools/validate.py` 完成。

## 图像与输出边界

RAW 使用 macOS 解码。送入引擎的是场景线性输入，原图对比使用显示解码。
不同 RAW 解码器的相机配置、色调和镜头处理可能给出不同输入；不能通过
改写胶片或相纸实测配置来抵消这类差异。

JPEG、带编码的 TIFF 等 RGB 文件在输入边界解码其传递函数。它们可能
已有外部色调处理，不能据此声称恢复了原始场景辐射。现有验证区分 RAW
解码与编码 RGB 输入，不将处理过的 TIFF 当作 RAW 参考。

工作空间与普通画布纹理为 ProPhoto RGB。预览与全分辨率使用同一工艺
参数，颗粒及空间效应按物理画幅换算。缩放不会改变胶片配置。全尺寸
导出经过同一几何和颜色路径，使用临时文件完成后替换目标。

| 路径 | 当前输出 |
|---|---|
| JPEG | 8-bit、所选目标 ICC、JPEG 质量由配方设置 |
| PNG | 8-bit、所选目标 ICC、无损 |
| TIFF | 16-bit、所选目标 ICC、当前成片路径使用无压缩 TIFF |
| DI package | `<name>_DI.tif`：未标记的 16-bit Cineon 主图及视图预览页；旁边共享两个固定 DI 视图 `.cube` |

DI 使用 ProPhoto RGB 原色的 Cineon 对数代码，保留胶片反差并绕过相纸
印相和后期输出调色。两个 65³ 视图 LUT 是 Cineon → ProPhoto RGB、
Cineon → Rec.709；它们是观看变换，不是当前相纸的印相表。
应用画布使用随包的 ProPhoto 视图 LUT。普通 RGB 导出 DI 时先应用该
视图，再执行配方的目标颜色变换和 ICC 写入。

不要将 Cineon 主图当作普通带 ICC 的照片。默认查看它可使用配套 LUT，
避免在已有 Cineon 转换之后重复应用完整 DI 视图。视图包括高光映射，
因此观看图像不代表对主文件数据的改写。数据来源说明见
[Resources/DI/README.md](Spektrafilm/Resources/DI/README.md)。

## 验证与分发

可重复的测试命令、真实照片清单、外部素材处理和验收边界见
[VALIDATION.md](VALIDATION.md)。测试不能替代实际窗口的帧率与视觉验收。
历史架构／RFC 中的传统布局、Python service 和旧密度 DI 描述应按历史
记录阅读；这里与当前实现对应。

`Tools/package.sh` 保留 archive、Developer ID 签名、DMG、公证和验证流程。
不使用 Developer ID 的发布包通过 `tools/package-public-release.py` 构建，
明确标注临时签名和未公证状态，并排除私人素材；它不宣称通过 Gatekeeper 的
默认信任检查。下载与安装方式见[二进制发布说明](../../docs/BINARY-RELEASES.md)。

## 共享平台与胶片呈现

`StockCatalogCore.swift`、`ParamValue.swift` 和 `Geometry.swift` 由 iOS 工程
直接引用，不另行复制。`MobileDesktopContractTests` 核对移动端捕获的桌面
默认值；修改共享文件后检查两个工程生成器。iOS 的原生界面、操作状态、
内存限制与导出策略单独实现，详见 [iOS 指南](../../ios/README.md)。

片边／日期后背由 `FilmEdge.swift`、`ShootingData.swift`、
`Session+FilmPresentation.swift` 和引擎 overscan 共同处理；
`FilmCanvasInput.swift` 负责片门输入。镜头滤镜改变胶片感光，片边与
日期曝光不经过镜头滤镜。修改这些参数需要重显影，不复用旧负片。

`HalfFramePair.swift` 定义 `.spektrapair` 源照片引用文档；
`PairComposer.swift` 在线性空间组片，组合自身 sidecar 保存共享印相与
片边设置，保留源照片自己的拍摄状态。不要将用户配对文件或源照片加入 Git。

黑白胶片及 Multigrade 纸等级见配置来源说明；`PaperGrade.swift` 把等级
转换为滤色及曝光补偿，补偿只应用一次。所有平台使用同一个生产
`Silverphase.icon`，历史版本在 [图标设计目录](../../design/app-icon/README.md)。

全局结构见 [ARCHITECTURE](../../ARCHITECTURE.md)，本轮门禁见
[2026-10-28 验证记录](../../performance/VALIDATION-REPORT-2026-10-28.md)。
