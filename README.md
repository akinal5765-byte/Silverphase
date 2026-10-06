# Silverphase

[简体中文](README.md) · [English](README.en.md)

**Silverphase 是一款面向 macOS 的胶片与相纸工艺模拟器。** 它把照片送入相机输入、胶片、显影、印相与扫描这条流程，让你通过摄影语言决定画面，而不是面对一整排科研模型参数。它不是 Lightroom 或 Capture One 的替代品；通用调色、资产管理和复杂局部修图应留给更擅长这些工作的软件。

Silverphase 是 [SpektraLab](https://github.com/JamesQiu2005/SpektraLab) 的独立衍生项目，保留了原项目的 Git 历史和原生 macOS／C++／Metal 基础。胶片与相纸模型、实测配置来自 Andrea Volpato 的 [spektrafilm](https://github.com/andreavolpato/spektrafilm)。Silverphase 的产品方向和界面与两者独立；这两个上游项目均未参与或背书 Silverphase。

> 当前仓库是开发中的源码，不代表已经发布经过签名与公证的 macOS 安装包。仓库内部分目录、Xcode target 和命令仍叫 `Spektrafilm`，这是内部工程名称；应用显示名为 `Silverphase`。

## 从照片到成片

1. 打开照片或文件夹，在预览与胶片条中选择画面。
2. 在底部胶片条选择胶片和相纸。正片没有相纸印相阶段；也可以选择“不使用相纸”查看冲洗后的胶片。
3. 在右侧按工艺顺序调整相机输入、胶片、显影、印相及裁切。右侧是工艺参数面板，不是额外的通用调色层。
4. 在导出页选择成片，或导出可继续调色的胶片中间文件。

主要控制包括：

- **相机输入：** 测光方式、胶片曝光、白平衡，以及可用时的镜头校正。这里的曝光作用于胶片输入，不是导出后的补救滑杆。
- **胶片：** 胶片型号与物理画幅、颗粒、胶片晕光、乳剂散射和独立效果强度。画幅尺寸参与颗粒与空间效应的尺度换算，不只是照片元数据。晕光菜单提供“跟随配置／强／中／弱／关闭”，强度滑杆在启用时为 1–4×。这里调的是模拟出的晕光，不是在宣称某卷真实胶片的防晕层规格。
- **显影：** 相对胶片配置默认值的显影反差和色彩分离，以及场景宽容度测量与显式场景置放。
- **印相：** 相纸型号、印相曝光、黄／品红滤光、预闪及独立的印相／扫描眩光。印相眩光不同于胶片晕光。
- **画面检查：** 预览、直方图、裁切及导出前的软打样。局部蒙版的交互方案尚未定稿，当前构建没有开放该功能。

具体范围与默认值以应用内控件及代码为准；README 不把内部物理模型的所有可调字段都冒充为已经开放的 UI。

另提供八个**实验负片配置**：PRO160NS、Pro Image 100、SUPERIA REALA 100、NATURA 1600、Agfa Portrait XPS 160、Agfa Optima II 200、Kodak Elite Color 200 和 Fujifilm PRO 160C。当前采用可靠胶片模型为基础，让各自厂商的相对感度与反差曲线参与受限调整，优先保证颜色可用；不是仅凭不完整数据重建染料，也不是经过实拍标定的胶片复刻。详见[配置来源与限制](engine/tools/profile_sources/experimental_negatives.md)。

另有六款**实验黑白负片**：HP5 Plus 400、Tri-X 400、Delta 100、FP4 Plus 125、XP2 Super 400 和 Fomapan 100 Classic，位于「实验」分类。它们用不同的光谱响应与灰阶曲线成像，而非成片后去色；默认配对合成的「中性黑白印相（实验）」。XP2 为 C-41 染料成像黑白近似，其余采用中性银影近似；颗粒、高光肩部和感度标定不代表精确复刻。详见[黑白配置来源与限制](engine/tools/profile_sources/blackwhite.md)。

## 两种导出路径

**Finished Film Render（完成的胶片成片）**：让 Silverphase 完成胶片与相纸流程，输出可直接使用的 JPEG、8-bit PNG 或 16-bit TIFF。导出配方可选择目标色彩空间等设置；导出页的软打样用于查看所选目标的结果。适合把胶片工艺作为最终成片。

**Gradeable Film Intermediate（可调色胶片中间文件）**：导出页称为 `DI package`。它包含一个**未附 ICC 标签的 16-bit Cineon 对数 TIFF，使用 ProPhoto RGB 原色**，以及两个固定的 **DI 视图 `.cube` LUT**（转 ProPhoto RGB、转 Rec.709）。TIFF 的第二页是便于查看的视图预览。中间文件保留胶片反差，不经过相纸印相或后期输出调色；这些 LUT 用于观看中间文件，**不是所选相纸的印相 LUT**。单独按普通 RGB 打开主图可能显示不正常，应使用配套视图。应用里把 DI 导出为普通 JPEG/TIFF 时，导出的是带目标色彩配置的显示视图。

两个视图 LUT 每个导出目录共享一份。`_DI.tif` 主图保持未标记的 Cineon 数据，不应给它直接指定普通显示 ICC；具体交付文件和颜色语义见 [工程说明](modern_UI/Spektrafilm/README.md)。

两条路径服务不同交付目的；请勿把 DI 文件夹中的 TIFF 当作普通 TIFF 成片交付。导出格式与具体选项以当前导出页为准。

## 技术结构

- `modern_UI/Spektrafilm/Spektrafilm/`：SwiftUI 界面、会话、预览与导出。
- `engine/`：C++20 渲染引擎、Metal kernels、胶片／相纸配置及测试工具。
- `modern_UI/Spektrafilm/Tools/`：Xcode 工程生成、资源与许可文件检查。
- `modern_UI/design/UI-SPEC.md`：界面规范；`ARCHITECTURE.md` 和 `rfc/`：架构与历史设计记录。旧文档可能仍描述已移除的通用调色层，遇到不一致时以当前代码为准。

引擎被编入 macOS 应用，运行时不需要 Python 服务、子进程或虚拟环境。应用通过 C 接口调用 C++／Metal 引擎；Metal 负责渲染，macOS 的图像与色彩管理组件负责文件解码及导出。构建用到的 Python 脚本仅是开发工具，不是应用运行时依赖。

## 本地构建

需要 Apple Silicon Mac、macOS 15 或更新版本，以及带 Metal 工具链的 Xcode。当前工程面向 Xcode 26.6；Xcode 工程文件已提交，日常构建不必重新生成。

从仓库根目录执行：

```bash
engine/build.sh bundle
xcodebuild -project modern_UI/Spektrafilm/Spektrafilm.xcodeproj \
  -scheme Spektrafilm -configuration Debug \
  -derivedDataPath build/DerivedData build
```

应用位于 `build/DerivedData/Build/Products/Debug/Silverphase.app`。修改引擎资源或 Metal shader 后，应先重新运行 `engine/build.sh bundle`；Xcode 的预构建检查会拒绝缺失资源，但不会替你生成它们。当前构建默认是开发用临时签名，不等于可分发版本。

运行测试：

```bash
xcodebuild -project modern_UI/Spektrafilm/Spektrafilm.xcodeproj \
  -scheme SpektrafilmTests -configuration Debug \
  -derivedDataPath build/DerivedData test
```

真实照片验证使用外部素材清单和临时副本，不将私人照片放入仓库。可重复执行的命令、覆盖范围及跳过项见 [验证说明](modern_UI/Spektrafilm/VALIDATION.md)。旧 Python-reference parity 脚本仅保留作历史验证工具，当前验收不依赖已不保留的冻结参考环境。构建细节见 [工程说明](modern_UI/Spektrafilm/README.md) 与 [开发备注](AGENTS.md)。

## 来源、许可与独立性

Silverphase 保留 SpektraLab 的项目历史，并在此基础上继续开发。SpektraLab 的原生 macOS 应用及 C++／Metal 移植由 Hanze Qiu 创建；spektrafilm 的物理模型和实测配置由 Andrea Volpato 创建。感谢两位作者公开这些工作。名称与界面上的变化不抹去来源，也不表示上游作者认可本项目的设计选择。

应用与 C++ 引擎按 **GPL-3.0-or-later** 授权；胶片／相纸配置及其衍生的印相预览 LUT 按 **CC BY-SA 4.0** 授权；使用的 Apple metal-cpp 按 **Apache 2.0** 授权。完整许可文本、配置与 LUT 的变更说明见 [许可目录](modern_UI/Spektrafilm/Spektrafilm/Resources/Licenses/)。分发二进制时，应一并遵守对应源码、署名与许可文本义务。

Silverphase 与 SpektraLab、spektrafilm 均为独立项目；“基于”不等于官方续作或合作。
