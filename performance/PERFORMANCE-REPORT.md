# Silverphase 性能工程报告（阶段记录）

日期：2026-09-26。完整逐阶段数字和复现条件见
[`PERFORMANCE-BASELINE.md`](PERFORMANCE-BASELINE.md)。本报告只把已经测到的
收益写成结论；尚未取得的 GUI 连续交互与批量数据保留为待验证项。

## Architecture

文件先由 ImageIO/Core Image 解码。RAW 的显示图与场景线性图由不同设置生成；
平面格式两者共用同一图。显示图生成原图对比纹理，线性图进入共享的 float32
RGBA Metal buffer，随后经 C ABI 交给内嵌 C++/Metal 引擎。引擎在不同分辨率
tier 上处理底片、冲印与扫描，并缓存底片和 setup 数据。画布在 Metal 中叠加
Layer 2、几何与输出变换；缩放和平移改变采样视口，不要求胶片管线重算。导出
使用全尺寸引擎输出，完成几何、Layer 2 和输出色彩变换后交给 ImageIO 写盘。

缓存分为当前解码/引擎会话、有限容量的纹理及缩略图、磁盘上的原图和冲印结果。
参数变更按 shoot、print、Layer 2 与 viewport 路由：print 可复用底片，Layer 2
在画布完成，viewport 只重绘。没有引入新的近似算法、半精度或胶片模型改动。

## Bottlenecks found and changes

| 路径 | 证据 | 改动 | 结果 |
|---|---|---|---|
| 61 MP LZW TIFF 冷打开 | Core Image 原图纹理 14.5 s；Time Profiler 中 12,221/15,257 个运行样本落在 ImageIO `LZWDecode` | 仅对大幅、不透明、8 位 RGB TIFF 先经 ImageIO 解码并落成独立位图 | 首张冲印完整打开 15.63 → 1.31 s，约 11.9× |
| 连续滑杆渲染 | 旧结果可能覆盖新状态；旧循环结束可能清除新循环句柄 | 调度器只交付最新参数结果，并按 generation 清理自己的句柄 | 定向并发测试先红后绿；真实可见帧延迟未测 |
| 真实 RAW 切图 | 26/60 MP Sony ARW 的 EXIF 同步读取占主线程 155/154 ms | EXIF 转到可取消的后台任务，按选图代数交付 | 60 MP 同步 `select` 降至 4 ms；冲印打开 3251→3255 ms，保持原有速度 |
| 导出时 UI 主线程 | 完成图写盘原先位于 `@MainActor`；独立测得 24 MP 16 位 TIFF 的 ImageIO finalize 为 516 ms | 完成图和 DI 的纹理读回、编码及 `.cube` 写入转到后台，持有 scratch 租约直至结束 | 阻塞段不再运行于 MainActor；吞吐尚未实测 |
| 性能定位 | 原有 open 日志有阶段时间，但无法在 Instruments 一条轨迹上看解码、调度和写盘 | 加入 Points of Interest 区间及参数变化、drawable 呈现标记，保留原有文本日志 | 24 MP 轨迹收到成对的解码、原图纹理、引擎输入事件；真实窗口 31.4 MP JPEG 轨迹收到成对的呈现事件 |

一个先试后撤的方案也记录在基线中：只加速原图对比纹理，虽然把该阶段从
14.55 s 降到 0.42 s，却使全尺寸 TIFF 被再次解码，首张**冲印**反而更晚。
该代码已撤回，避免把不可见阶段的漂亮数字当成用户收益。

## Benchmark and memory

合成灰阶 LZW TIFF 是单次冷打开，不是 RAW 的代表。24 MP 和 33.6 MP
打开约 0.9–1.0 s；60.2 MP 原先为 15.63 s。优化后 60.2 MP 是 1.31 s，
全尺寸渲染约 4.9–5.0 s，未表现出速度退化。24/33 MP 前后差异较小，不能
据此声称稳定收益。

60.2 MP 峰值 RSS 在优化后为 3.51 GB，落在旧路径 3.44–3.58 GB 的观测
区间。最终冲印截图中央 800×450 区域逐像素一致；小图定向测试还比较了
Display P3 标记 TIFF 的全部八种 EXIF 方向、原图纹理与引擎线性浮点输入。
这证明了受测入口，不等于覆盖所有相机、ICC、宽色域和高位深照片。

用户提供的照片中另取 26 MP 与 60.2 MP ARW、31.4 MP JPEG 做了冷打开。
冲印打开分别为 1.93、3.25、1.08 s；全尺寸渲染分别为 1.74、4.91、
2.25 s；峰值 RSS 分别约 2.41、3.68、3.07 GB。60.2 MP RAW 在 EXIF
改动后的另一次运行中，冲印打开为 3.26 s、全尺寸渲染为 4.76 s、峰值
RSS 为 3.51 GB。各是单次样本，不能据此宣称全尺寸渲染或内存改善。
真实 RAW 改动前后的最终冲印截图中央 800×450 区域逐像素一致。

单进程依次打开 20 个同一 26 MP RAW 的不同临时副本，并等待每张全尺寸
冲印落地，耗时中位数 4.20 s。`phys_footprint` 在第 9 张达到约 4.26 GB，
第 20 张为 4.27 GB，后 11 次只增长约 14.6 MB。这与有限缓存填满后进入
平台相符；该测试没有显示链路，也不能代表混合照片或 100 张长时间使用。

## Interaction latency and UI

已加入从 `parameter changed` 到 `CAMetalDrawable` 实际 present 所需的
Instruments 标记，且在真实窗口轨迹中核对了 drawable 呈现事件；尚未录得
连续滑杆操作的延迟分布。
调度器在 shoot 修改后等待 220 ms，在 print 修改后等待 40 ms，并保持单飞、
最新状态获胜。这个策略避免积压；它本身不能证明连续拖动达到 60 fps 或
首帧 50 ms。60.2 MP TIFF 的 EXIF 只用 2 ms，但真实 Sony ARW 是 154 ms，
因此已将读取移出主线程。真实窗口的 zoom、pan、
面板展开和切图帧间隔仍需录制。

## Export

图像写盘已离开 UI actor，文件格式、EXIF、色彩配置和 DI TIFF 预览页规则
保持一致。导出目前随引擎单会话逐张处理。一张 26 MP 真实 RAW 的 16 位
Display P3 TIFF 测试中，引擎会话准备 2.60 s，导出调用 3.61 s，输出约
205 MB，结束时 `phys_footprint` 约 3.51 GB。这是单次样本，不是峰值
内存或吞吐分布。10 张与 50 张真实照片的 GPU/CPU 利用率、吞吐和内存
平台期尚未测量，因此没有更改并发数。

## Verification and remaining bottlenecks

应用 Debug 构建成功，产物在
`build/DerivedData/Build/Products/Debug/Silverphase.app`。TIFF 色彩/方向测试、
调度器过期结果测试、后台写入测试、EXIF 过期结果测试、20 张 RAW
全尺寸切换基准、单张真实 RAW TIFF 导出基准与现有
EXIF/TIFF/DI 写入测试通过。一个既有源码检查测试因测试进程无权读取
`Filmstrip.swift` 而失败；部分依赖仓库原片的现有测试跳过。用户提供的
真实 RAW 已用于本轮测量，但文档所指的 Python 参考仓库未找到，因此不能
把引擎 parity 记为通过；本轮也未改引擎运算或烘焙资源。

下一轮的优先测量是：真实 RAW 不同开发设置、滑杆事件到 drawable
present、混合照片切换的命中率和更长时间的 RSS 平台、单张及批量导出吞吐、实际窗口
缩放与拖动帧间隔。拿到这些数据后再决定是否需要更小的交互 tier、缓存预算
调整、预加载或内核融合；目前缺少支持这些复杂改动的证据。
