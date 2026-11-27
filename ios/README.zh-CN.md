# Silverphase iOS／iPadOS 指南

[简体中文](README.zh-CN.md) · [English](README.md)

> 当前使用、构建和诊断的中文指南。较早的逐项验证明细保留在英文原文中。

Silverphase 提供本地图库、内置胶片相机、原生工艺导航，以及批量编辑和导出。应用与 macOS 版共用 C++／Metal 引擎、胶片与相纸目录和许可资料，并不意味着两端功能完全相同。原始 FTP 实验应用不是本版的运行依赖。

## 图库与看图

在图库网格点按照片，先进入看图页。左右滑动或点缩略图切换；可评分、标旗、换胶片、查看照片信息或导出。长按查看原片，点「编辑」进入单张编辑器。普通 iPhone 和 iPad 的操作分布在顶部与底部；Duo 折叠、展开横屏时使用系统侧栏，展开竖屏时使用上下工具栏。

「更多 → 格式」只列出图库中已有的原文件格式；DNG、ARW 等 RAW 扩展名分别列出。支持搜索、评分与旗标筛选、全选当前结果、批量改旗标／评分、复制粘贴编辑组和按明确选集导出。横向划过网格选择范围，从已选项起划则取消；纵向滑动仍滚动。返回时保留筛选、滚动和选择状态。批量编辑须通过确认面板应用到整批，普通滑杆仍只改当前预览照片；改动导出配方也不会改变已固定的目标选集。

应用在 `Application Support/Silverphase/library.json` 中原子保存带版本的清单；原片按唯一的相对文件名存放。损坏或未知版本的记录不会静默删除。移除照片时先保存新清单，再删除应用管理的文件，不改系统「照片」或导入源。成片缩略图按配方、构图和相关设置缓存，尚未生成则显示原片缩略图，不显示旧版本成片。原文件名、格式和 EXIF 可在照片信息中查看；设置显示图库照片数量及原文件占用。暂不支持图库相册、云同步或跨设备转移。

## 设备布局

普通 iPhone 使用竖屏编辑布局：七项工艺导航、限高浮动面板、纵向胶片／相纸列表以及独立于画布的状态栏。顶部为返回、导出和菜单；撤销与重做在菜单中。Duo 折叠与横屏使用系统侧栏，展开竖屏使用浮动面板。iPad 使用顶部工艺栏、右侧参数面板与底部浏览器。对照 [iPhone／iPad 的真实照片界面截图](../screenshots/ios/2026-11-27/README.md) 和 [界面规范](DESIGN.md)。模拟器截图不能证明真机触控、内存、相机权限或导出性能。

### 已知限制：设备认证前的实体 Camera Control

在 iPhone 17 Pro 和 Duo，认证前按实体 Camera Control，锁屏拍摄扩展可能有取景而无法按快门，或短暂停住。Duo 日志显示系统相机锁屏预热抢占了相机访问；17 Pro 的原因未确认。测试设备认证后按键可用，控制中心的 Silverphase 相机控件会先请求认证，再开启主应用相机。

这是 1.2.0 已知且未修复的限制，1.2.1 记录仍未实机验收。系统要求锁屏扩展启动时即提供实时取景，而且不能在扩展启动前要求认证；若让主应用提前接管，就无法保留 Camera Control 入口。应用内拍摄及其后续显影、预览和保存不受影响。

### 已知问题：Duo 的 1× RAW 偶发近黑

2026-11-13 观察到部分 1× Bayer RAW 和对应 HEIC 成片近黑，后续拍摄恢复正常。两份受影响 DNG 的 16 个图块中各有 8 个字节相同，并跨文件重复；两份邻近的正常样本各有 16 个不同图块，四份文件均记录 0 EV 补偿。异常已存在于显影和导出前的原始 DNG，原因未明。复现时保留 DNG 与匹配的 HEIC，记下时间与相机设置，并收集对应时段的系统相机日志；不要把私人图片或日志提交到仓库。

## 安装与构建

iPhone 和 iPad（iOS／iPadOS 18 或更高）可通过 [App Store](https://apps.apple.com/app/id6829987567) 获取，测试版见 [TestFlight](https://testflight.apple.com/join/uwY3ZYJp)。可安装版本以对应渠道为准，源码标签不代表商店已上架。应用、控制中心相机入口和锁屏相机扩展在源码中均为 **1.4.0（12）**。参见 [商店分发记录](APP-STORE.zh-CN.md)、[1.4.0 说明](releases/1.4.0.md) 和 [下载与校验](../docs/BINARY-RELEASES.md)。

历史未签名 IPA 见 [GitHub Releases](https://github.com/akinal5765-byte/Silverphase/releases)，用户自行签名、配置和安装。公开包不打入个人材料或本地实验资源；真机签名须支持 Increased Memory Limit。

使用安装了 Metal Toolchain 的 Xcode 27.1。若当前开发目录指向 Command Line Tools，只需为命令设置 `DEVELOPER_DIR`，不必改全局 Xcode 选择。

```sh
python3 ios/Silverphase/Tools/gen-project.py
DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer \
  xcodebuild -project ios/Silverphase/Silverphase.xcodeproj \
  -scheme Silverphase -configuration Debug -sdk iphonesimulator \
  -derivedDataPath /tmp/silverphase-ios-derived CODE_SIGNING_ALLOWED=NO build
```

真机构建改用 `-sdk iphoneos`，并在 Xcode 选择开发团队和签名身份。新 bundle ID 为 `com.silverphase.editor`，不会覆盖早期 FTP 演示应用；构建脚本不会配置或安装真机。为 `CODE_SIGNING_ALLOWED=NO` 产物补签时，先签内部 Mach-O 动态库（包括 `Silverphase.debug.dylib`、`__preview.dylib`），再按描述文件和权限签应用包。安装前用 `codesign --verify --deep --strict` 校验；安装成功不代表能通过 DYLD 加载，需验证启动后进程仍存活。

构建阶段编译当前引擎，内核用安全／精确 float32 数学另行编译；打包常量、基础和产品材料、目录、封面与许可证。缓存考虑源文件、头文件、SDK／编译器身份和脚本内容。移动端资源放在 `AppResources/`；根路径的 `Resources/` 会让 Foundation 误识别为旧式 macOS bundle 并丢失 bundle ID。桌面目录和 JSON 类型由源文件共享，不复制。共享源码拆分后重新生成：

```sh
python3 modern_UI/Spektrafilm/Tools/gen-project.py
python3 ios/Silverphase/Tools/gen-project.py --check
```

## 编辑、构图和导出

五段工艺为 **预处理 → 胶片 → 显影 → 彩色放大 → 扫描**；「构图」与「片边」是两项独立工具。紧凑导航将彩色放大简称「印相」。单张编辑不显示批次照片条，多选编辑只显示选中的一组。支持每张照片独立编辑、撤销／重做和状态持久化；偏好与命名导出配方独立保存。

可从系统「照片」或文件导入 RAW、JPEG、HEIC／HEIF、PNG、TIFF，校验内容，保留色彩配置，优先取 RAW。授予读取「照片」权限时，应用检查所选资源的原始和备选版本；部分或无访问权限时仍可使用选择器交付的表示。若明确选中 RAW 但未取得 RAW 文件，则拒绝以非 RAW 替代。RAW 白平衡和仅 RAW 支持的镜头校正不在已渲染图像上出现。EXIF 缺失字段不会虚构。

构图共用桌面 `Geometry.swift`：八个触摸手柄，自由／锁定比例，移动、重画、±45° 校直、90° 转向及翻转；预览和导出使用相同像素映射。带片边时可在未装框图像上定位构图，然后保留真实片边。双照片半格配对仍是桌面端功能。

「预处理」处理入片影调、曝光、细节与颜色；支持的 RAW 可按照片匹配内嵌相机预览亮度，保护高光并记录起始曝光。「胶片」设置测光和手动胶片曝光。「导出」可设最终像素尺寸；已有自定义模拟尺寸的照片可从「胶片 → 工艺操作 → 恢复原始模拟尺寸」恢复源采样。JPEG、PNG 和 TIFF 将图库星级写为 `xmp:Rating`。

预览先提供适屏底图，合并交互更新并渐进补充视口细节，最高可达原生像素。双击或菜单切换适屏／1:1。没有固定预览分辨率选择器；输出尺寸与预览独立。设置保留低电量优先、裁切重算效果尺度、DI 蓝色补偿及释放缓存。

支持 JPEG、PNG、16 位 TIFF 和 Cineon DI，含批次范围、命名配方、色彩空间、元数据／位置策略、TIFF 预览、文件夹同名处理及只添加的「照片」保存。导出受进程内存保护。文件名由原名、胶片、相纸、日期、序号勾选，以下划线按显示顺序连接，至少保留一项；首张真实目标用于预览。旧自定义规则在修改勾选前保留。各工艺默认值、范围、已验证及未移植能力见 [功能审计](CONTROL-AUDIT.md)。

## 相机与锁屏扩展

- 锁屏扩展通过 `CameraCaptureIntent.appContext` 继承胶片、测光和柔光镜；无胶片菜单，扩展中更改的测光和滤镜仅用于本次会话。原片在系统会话暂存，逐张附胶片 ID 和配方；导入时解析所需相纸或直扫，旧 sidecar 保留原有行为，未知胶片会明确报错而保留原片。锁屏扩展不能直接写入「照片」；解锁后由主应用导入、显影并按相机保存策略处理。
- 普通 iPhone、iPad 与锁屏扩展使用设备相对的相机布局：控件随重力同位旋转，界面方向不决定成片方向。Duo 应用内相机跟随其原生窗口，内屏右侧复用快门与镜头控件，取景尽量保持原片比例；折叠和外屏后摄自拍以居中裁切填满取景，仅影响显示。AVFoundation 分别提供取景和拍摄角度；按快门冻结姿态与显示方向对应关系，切换角度时丢弃上一个处理帧。不额外转动或镜像保存的照片。[Apple 的 Duo 相机指导](https://developer.apple.com/videos/play/tech-talks/111465/)。
- Duo 腰平取景时，下屏保留取景器、顶栏和靠右的拍摄组，上屏用纵向胶片卡堆选片；展开横屏则左边是较大的 16:9 胶片堆，右边是取景和拍摄组。横屏右侧若有轻微上下留白，最多以 4% 居中填充，显影动画沿用同一画框。近似取景随滑动更新，松手确认；系统取景和原生实验模式不随滑。外屏后摄自拍交接独立，没有腰平外屏印相附件。
- 普通 iPhone 与安全扩展在按快门时固定物理姿态；iOS 27 及以上由 AVFoundation 根据明确姿态计算传感器角度，旧系统沿用旋转协调器。导入不另做临时像素旋转。退出相机后恢复图库和编辑器方向策略。

## 实时胶片取景、位置与状态

设置「相机 → 实时胶片取景」和相机菜单共用三种模式：「流畅近似预览」（推荐、默认）、「系统取景（关闭效果）」和「原生引擎预览（实验）」。旧实验原生选择仅在升级时一次性迁移到近似，旧明确关闭继续关闭。锁屏仍使用系统取景；最终照片一律用原生配方显影。

近似模式按胶片缓存 49³ 场景线性 ProPhoto → Display P3 查表，使用对数整形保留 0…16 线性输入；不做空间扩散、扫描锐化、随机颗粒、眩光或物理光晕。其高光不在胶片响应前截断为 1。曝光和近似柔光在查表前应用。正常调度上限 960px／30Hz，省电或高热状态 640px／20Hz。最多保留两张查表纹理（LRU）；拍摄时释放较大引擎工作区而保留小纹理，离开、进后台或关闭取景则释放全部预览资源。

实验原生模式复用引擎会话、材料设置及 GPU 缓冲；`spk_replace_device_frame` 清除旧图片派生状态，尺寸换挡或配方改变则重开。输入为已由系统处理的 8 位 BGRA SDR，不等同 RAW；取景将 `halation_headroom_ev` 设为 0，避免推高已经显映射的高光，物理光晕仍在。取景通过 `spk_render_viewfinder` 请求 640px／30Hz，省电 480px／15Hz，测光输入最高 1600px。二者都只保留最新帧和一个在途渲染。数字变焦保持预览；更换物理镜头或人像模式时冻结当前处理画面，待新配置与处理帧匹配后淡出，不能由过期帧解冻。关闭或未准备时回落到系统取景，处理失败不阻断快门。模式不是成片打样，调度上限不是设备帧率或热负载验收。

取景状态独立显示在相机工具栏下方。「设置 → 相机 → 记录拍摄位置」默认开启，系统仍须授予「使用 App 期间」权限。只在主应用相机活跃时获取位置；离开、退后台或关设置时停止并清除。拍摄时使用 60 秒内的有效位置，不等待定位，尊重系统提供的近似位置。支持坐标、UTC 时间、有效海拔写入原片元数据；导出根据保留元数据与去除位置的设置决定。保存至「照片」时的资源位置来自已输出文件。关闭不会修改既有照片，锁屏扩展不请求或借用位置，不做后台追踪。

## 验证与设备内存

Debug 模拟器构建可用仓库运行器；它会删除上次报告、等待本次诊断并检查 `passed`：

```sh
DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer \
  ios/Silverphase/Tools/check-simulator.sh SIMULATOR_UDID /absolute/path/Silverphase.app --camera-look-regression
```

| Debug 入口 | 能验证什么 |
|---|---|
| `--locked-camera-regression` | 姿态及相机策略、90 种配方往返、旧 sidecar 与未知胶片、四种合成 TIFF／EXIF 表示的真实原生显影；不验证锁屏宿主、实体相机或传感器朝向。 |
| `--camera-exposure-regression`、`--camera-location-regression` | 合成输入的 EV 不变性、定位时效／授权关闭、GPS 元数据往返与移除；不是相机标定、真机权限、GPS 或大图导出验收。 |
| `--camera-look-regression` | 替换帧的事务与寿命、文件／逐帧对照、预览降档、方向、迁移和取消；记录计时但不作真机帧率验收。 |
| `--flat-import-regression` | 合成照片提供器的 JPEG／HEIC／PNG、ICC 与尺寸检查，拒绝无效文件以及 RAW 被 JPEG 替代。内存不足时 `exportsValidated` 会明确标出尚未验证。附加 `--flat-import-large` 可启用 4032×3024；`--clear-flat-import-regression` 删除导出的诊断报告。 |
| `--smoke-test`、`--cinestill-regression` | GPU 与布局、配方、输出及 DI／LUT 打包的合成检查，以及 CineStill 800T 的聚焦回归。 |
| `--library-regression`、`--library-ui-regression` | 隔离的图库模型和 UI 测试；`--reset-library-fixture` 仅清本测试图库。 |
| `--clipboard-regression` | 合成状态中的编辑项剪贴板，写 `Documents/clipboard-report.json`；重点 UI 用例为 `PhotoImportTests.testSelectiveCopyAndMultiPhotoPaste`。 |

完整报告名、`--device-audit` 的 `--audit-color`／`--audit-mp=24`／`--audit-jpeg`／`--audit-export`／`--clear-device-audit` 流程、锁屏打包实测范围与历次内存／条带验收数据见 英文原文的 [Validation](README.md#validation)、[Device memory capability](README.md#device-memory-capability) 和 [2026-10-28 集成报告](../performance/VALIDATION-REPORT-2026-10-28.md)。历史数值不能推广到当前设备、源文件和配方。

`Silverphase.entitlements` 请求生产用 Increased Memory Limit（不是 Debug 专用权限）；自动签名需要有效 App ID 和描述文件。JPEG 大图按 256 行分带，释放引擎源图、负片和资源池后再把独立纹理拷给主应用图像。预览默认值不变；不可把以前的设备内存观测当作所有 RAM 都属于当前进程的保证。

导入与导出共用进度界面：只在长任务期间锁交互；普通参数预览继续可用。导入横跨提供器读取、协调与复制以及首张预览（若需要），失败和空结果解除锁定，回前台可继续准备；导出随渲染、颜色转换、写入及「照片」完成事件推进。Debug 实际 RAW 曝光报告只写最新 `Documents/camera-exposure-report.json`：同一线性 ProPhoto 边界的 RAW 与近快门视频数值分位数、EV、ISO、快门时间及帧龄，无图像像素和 GPS，不改源文件或配方，不延迟抓拍。Release 不收集该报告。

## 编辑项剪贴板

复制参数时选工艺组，裁切默认不勾；启用后只复制数值比例，按目标方向调整，不复制构图中心、校直、转向或翻转。取消复制保留旧剪贴板。选集粘贴不另弹范围页，可整批撤销／重做，选集与工程原片元数据、镜头校准及 As Shot 解码仍保留。相片编辑持久化，剪贴板与撤销历史不持久化。

架构与历史范围请参阅 [共享引擎架构](../ARCHITECTURE.md)、[文档索引](../docs/README.md)。此中文页解释当前使用和验证范围；[英文原文](README.md)保留完整的诊断命令参数、样本条件与时间记录。
