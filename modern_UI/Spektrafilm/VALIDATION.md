# Silverphase 验证

**简体中文** · [English](VALIDATION.en.md)

当前验收围绕本地原生 C++／Metal 引擎和真实照片的完整工作流。冻结的
旧 Python fork 不再保留，不作为运行验收的前提；`engine/tests/parity_*.py`
仍是历史工具，不将未运行的 oracle parity 写为通过，也不拿新脚本
冒充独立物理参考。实际色彩科学能力仍受实测配置和输入解码边界限制。

## 可重复执行

### 5219 底片与光谱色样

分阶段检查参考了 [Negs 的 GPU 验证报告](https://github.com/noahhaasis/negs/blob/479a5674bb9d43af5c08fbd7307b367bec7bf10b/docs/gpu-vs-cpu-quality.md)。
下载 [BabelColor Avg30 实测光谱](https://babelcolor.com/index_htm_files/CC_Avg30_spectrum_CGATS.txt)。
验证程序检查原文件的 SHA-256，实测色样文件留在构建目录或外部素材目录。
构建驱动后，传入待验证的 macOS 应用自己的引擎资源目录：

```sh
engine/build.sh tests
python3 engine/tests/check_film_reference.py \
  '/path/to/Silverphase.app/Contents/Resources/Resources/engine' \
  '/path/to/CC_Avg30_spectrum_CGATS.txt' \
  --report /tmp/5219-stages.tsv
```

- 5219 使用 [Kodak 2015 年 ECN-2 技术资料第 4 页](https://www.kodak.com/content/products-brochures/Film/VISION3-500T-Color-Negative-Film-7219-TECHNICAL-DATA.pdf#page=4)
  的 14 个曝光点，按 [ISO 5/3 的 Status M 权重](https://cdn.standards.iteh.ai/samples/20101/642e3ed0adfe43be85e67b2c413cca56/ISO-5-3-1984.pdf)
  估算透射密度。仅用绿通道在零档对齐一次曝光。门限针对曲线形状。
- 24 个色样在胶片配置的参考光源下比较直接光谱积分和生产 RGB 入片路径。两条路径仅按同一块理想白各自归一化，以 EV 报告每个感光通道的误差。直接积分使用当前胶片的感光曲线。积分衡量光谱近似，实物色彩需要独立胶片测量。
- 阶段回归记录入片曝光、底片 CMY、Supra Endura 相纸 CMY 和输出 RGB。固定输入包含中性色、高饱和色、超白和近黑。颗粒与反光关闭以保证可重跑。阶段容限用于定位软件漂移。
- 颗粒单独用平场测量。在三个高密度点，以 48 µm 圆孔先平均透射率，再求蓝通道的密度波动。门限允许随机抽样波动，用于检查当前颗粒模型的统计量。原厂蓝通道颗粒度更高，本次基线保留这个已知差异。

### Fotufilm DIR 边缘增强复查

2026-11-25 使用原生 Metal 复查 29 款 Fotufilm 移植配置。第一轮将 9 款
彩色负片的空间邻接权重减半。第二轮纳入低曝光和第二种像素间距，从
29 款中筛出 17 款需要限制空间邻接的配置。原版 Fotufilm 的 Pro 160NS 有自己的 DIR
抑制矩阵、释放曲线和扩散尺度。经 Negs 转换后，Silverphase 的 Pro 160NS
采用 Spektrafilm 通用彩色负片 DIR 预设和扩散模型。显影抑制在相邻区域间
扩散，会在明暗交界处产生亮侧过冲和暗侧欠冲。这个效果在扫描锐化关闭时
仍出现。[Fotufilm 原始配置](https://github.com/DhaliwalX/fotufilm-engine/blob/96623ba0831a52dbddcda35727a206d4123a8b5f/Sources/FotufilmCore/Stocks/pro160ns.json) · [移植来源](../../license/DATA-SOURCES.md#experimental-fotufilm-profiles)

当前修正在显影阶段混合受扩散的抑制和同像素的局部抑制。
17 款使用各自的空间权重，范围为 0.08–0.70。两者合计权重为 1，
因此均匀曝光下的 DIR 颜色响应和密度曲线预校正仍适用。原有 DIR 滑杆
继续控制总体效应。修正前后对照中，17 款在两种像素间距的均匀 RGB
色块上最大相差 1 个 16 位码值。Pro 160NS、Phoenix 200 和 Infrared
Color 的整幅与分条输出逐像素一致。
[空间邻接实现](../../engine/src/pipeline/pipeline.cpp)

#### 测试条件

- 输入为 1024 × 256 的线性 RGB 中性阶跃，边缘位于第 512 列。取 `0.04 → 0.12`、`0.08 → 0.24`、`0.16 → 0.48` 三组相同曝光比的阶跃。像素间距为 8.838 µm（对应本次 120 案例）和 3.90625 µm（接近同分辨率 135）。以画幅长边和像素宽度设置引擎的物理像素间距。
- 使用 `full` 渲染。负片固定用 Portra Endura，正片直扫。关闭自动测光、颗粒、光晕、相纸眩光和扫描锐化。每个条件分别渲染 DIR 关闭与 `1.00×`，共 174 组开关对照。用修正前的引擎和同一份资源对中间阶跃再渲染 58 次。
- 对成片 16 位 RGB 码值以 `0.2126 / 0.7152 / 0.0722` 加权。平均第 32 至 223 行，以第 256 和第 768 列代表两侧平场，取第 494 至 529 列的最大过冲或欠冲，占两侧平场码值落差的百分比。这个百分比描述输出边缘的越界幅度。

#### 全目录结果

开启 DIR 后，24 款彩色配置仍可量出边缘过冲或欠冲。关闭后，29 款
在全部测试条件下的越界幅度均为零。5 款黑白配置由引擎跳过 DIR。
在当前默认值下，174 组测试全部低于 40% 的内部筛查线，最高是
Reala 500D 在较低曝光、近 135 像素间距下的 34.8%。其余 12 款在
中间曝光阶跃的两种间距下与修正前逐像素一致。

下表记录中间曝光阶跃（0.08 → 0.24）修正前后的越界幅度，并列出
当前六种条件中的最大值。单位为平场落差的百分比。

| 配置 | 120 间距修正前 | 120 间距当前 | 近 135 间距修正前 | 近 135 间距当前 | 当前六种条件最大值 |
|---|---:|---:|---:|---:|---:|
| Agfa Agfachrome 100 | 16.7 | 12.1 | 18.4 | 13.3 | 31.3 |
| Agfa Agfachrome 200 | 14.3 | 14.3 | 15.8 | 15.8 | 31.5 |
| Agfa Agfachrome 50 | 16.6 | 12.0 | 18.3 | 13.2 | 30.4 |
| CineStill 400D | 34.6 | 15.8 | 38.3 | 17.6 | 30.0 |
| CineStill 800T | 36.6 | 16.9 | 40.4 | 18.8 | 32.2 |
| Infrared Color (creative) | 24.3 | 6.9 | 27.1 | 7.6 | 29.9 |
| Fujifilm Neopan 100 Acros II | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| Fujifilm Astia 100F | 15.6 | 15.6 | 17.2 | 17.2 | 32.6 |
| Fujifilm Eterna 500 | 57.3 | 15.9 | 62.4 | 17.6 | 33.0 |
| Fujifilm Eterna Vivid 500 | 62.3 | 14.6 | 67.2 | 16.2 | 32.3 |
| Fujifilm F-64D | 60.8 | 15.0 | 66.1 | 16.6 | 33.2 |
| Fujifilm Pro 160NS | 57.5 | 17.4 | 62.8 | 19.3 | 33.4 |
| Fujifilm Superia Reala 100 | 69.2 | 11.9 | 74.0 | 13.2 | 31.2 |
| Fujifilm Reala 500D | 46.9 | 15.2 | 51.4 | 16.8 | 34.8 |
| Fujifilm Superia 200 | 77.6 | 13.0 | 81.3 | 14.4 | 28.8 |
| Fujifilm Velvia 50 | 10.3 | 10.3 | 11.4 | 11.4 | 23.0 |
| Harman Phoenix 200 | 31.4 | 3.5 | 33.4 | 3.8 | 21.4 |
| Ilford Delta 3200 Professional | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| Ilford FP4 Plus | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| Ilford HP5 Plus | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| Kodak Aerochrome III 1443 (infrared) | 15.8 | 7.8 | 17.5 | 8.4 | 28.7 |
| Kodak Aerocolor IV 2460 | 33.1 | 18.2 | 36.7 | 20.3 | 30.6 |
| Kodak Kodachrome 200 | 14.3 | 14.3 | 15.7 | 15.7 | 28.7 |
| Kodak Kodachrome 25 | 14.1 | 14.1 | 15.6 | 15.6 | 31.5 |
| Kodak Kodacolor 100 | 45.9 | 15.5 | 50.4 | 17.3 | 33.3 |
| Kodak T-MAX 100 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| Lomography Color Negative 100 | 42.9 | 15.3 | 47.2 | 17.0 | 33.0 |
| LomoChrome Metropolis | 9.0 | 9.0 | 9.9 | 9.9 | 16.3 |
| LomoChrome Turquoise | 10.8 | 10.8 | 12.0 | 12.0 | 21.0 |

#### 较低曝光的复测

以下为 120 间距、0.04 → 0.12 阶跃的越界幅度，单位为平场落差的百分比。
对照基线是第一轮的 9 款空间邻接限制。

| 配置 | 第一轮 | 当前 |
|---|---:|---:|
| Harman Phoenix 200 | 319.3 | 19.2 |
| Fujifilm Superia 200 | 120.2 | 25.7 |
| Fujifilm Superia Reala 100 | 97.8 | 28.0 |
| Infrared Color (creative) | 88.9 | 27.2 |
| Fujifilm Pro 160NS | 54.7 | 30.0 |

在同样两种间距的彩色渐变边界抽查中，34 个修正前后对照有 31 个的最大
通道越界幅度降低，3 个有所增加，最大增量为 451 个 16 位码值。这批彩色
测试的越界幅度均低于最大通道平场落差的 40%。局部彩色边缘随胶片和输入
而异，均匀色块的结果只适用于平场。

#### 回归与验证边界

构建原生动态库后，设置引擎资源目录并运行
[Fotufilm 边缘回归](../../engine/tests/fotufilm_dir_edges.py)。

```sh
export SPEKTRAFILM_ENGINE_RESOURCES="$PWD/modern_UI/Spektrafilm/Spektrafilm/Resources/engine"
python3 engine/tests/fotufilm_dir_edges.py
```

40% 是当前这组六种条件的工程筛查线。空间权重来自合成边缘对照，第一轮
还参考了用户对 Pro 160NS 人像的观感反馈。仍缺截图原始 ARW 的独立复测、
原版 Fotufilm 同条件成片和实际底片边缘密度剖面。原厂资料可以支持 DIR
边缘增强的机制，也可用于后续对照底片的 MTF。这里测量的是成片阶跃越界
幅度，不能用原厂底片 MTF 的百分比直接验证。
可另存一份诊断报告，先选双方都有的两款胶片。它保留相同的 40% 筛查门槛，
另外记录 RGB 三通道各自的过冲、欠冲，以及同一条件下 DIR 开关对五组均匀
中性曝光（相对 0.18 的 −2.5、−1、0、+1.5、+3 EV）中心像素的影响：

```sh
python3 engine/tests/fotufilm_dir_edges.py \
  --profile fujifilm_pro_160ns_fotufilm --profile fujifilm_velvia_50_fotufilm \
  --report /tmp/silverphase-dir-report.json
```

报告是成片 RGB 码值差，不是底片密度。某通道的两侧平场落差不足一个码值时，
其越界百分比为 `null`。上游 [Fotufilm #352](https://github.com/DhaliwalX/fotufilm-engine/pull/352)
的 schema v4 测试也使用这组均匀曝光，但检查其自己的合成配置和线性输出。
不能用上游容差来判定本报告，也不能把同名胶片当成同一配置。跨引擎比较应
先固定输入线性空间、实际画幅、胶片配置、停用的空间效果和同一个渲染阶段，
再比较各引擎内 DIR 开关前后的变化。报告不导入上游配置，也不改变渲染。

[富士 Pro 160NS 原厂资料，第 22 节](https://asset.fujifilm.com/www/jp/files/2024-04/6b75b1c1cb4253623fb2cd7a56ff7443/datasheet_pro160ns_01.pdf) · [富士研发报告，第 3.2.2 节](https://asset.fujifilm.com/www/jp/files/2019-10/a2b78141b856eedf5ba0bb0c403c69fc/rd_report_ff_rd051_all.pdf)

### 真实照片

在仓库根目录，先完成引擎资源构建，再执行标准库 Python 验证入口：

```sh
engine/build.sh bundle
python3 modern_UI/Spektrafilm/Tools/validate.py \
  --photos-root '/path/to/photos' \
  --scope photos \
  --output /tmp/silverphase-photos-validation
```

`photos` 运行真实照片、DI 导出与当前画布契约测试。这个门禁必须零失败、
零跳过；素材缺失或哈希不符在预检阶段失败，不会改用合成图冒充真实照片。
每次使用新的 `--output` 目录，避免覆盖既有 `.xcresult`。

完整集成边界：

```sh
python3 modern_UI/Spektrafilm/Tools/validate.py \
  --photos-root '/path/to/photos' \
  --scope full \
  --output /tmp/silverphase-full-validation
```

完整套件仍有旧固定素材专用用例和未启用的性能用例，可能跳过。入口会
在 `summary.json` 明确报告 `partial: inspect skipped tests`，退出成功
不代表所有素材相关用例都执行了。需同时阅读通过数、失败数和跳过数。

长批次可显式启用，例如 50 张互不相同的 RAW 导出 JPEG：

```sh
python3 modern_UI/Spektrafilm/Tools/validate.py \
  --photos-root '/path/to/photos' \
  --scope photos --batch-count 50 --batch-format jpeg \
  --output /tmp/silverphase-batch-validation
```

批次从给定目录递归枚举 RAW，按相对路径排序后取指定数量，复制到临时
目录并给副本加唯一序号。每张切图、冲印和全尺寸导出，检查文件写入，
并核对全尺寸渲染次数等于照片数。`batch.tsv` 记录逐张计时和导出后
内存采样；结束采样不是峰值，耗时也不是平台性能保证。TIFF 会占用更多
临时磁盘，请按预计全分辨率输出大小选择批次规模。

## 维护者固定案例集（2026-10-31）

[案例清单](SpektrafilmTests/Fixtures/release-case-manifest.json) 固定十张
Sony ILCE-7CM2 RAW：7008×4672 的 ImageIO 元数据，含横竖方向与不同 ISO。
本机副本位于 `private-fixtures/release-cases/`，整个目录被 Git 忽略。
Git 只保存相对文件名、SHA-256、尺寸、方向和场景说明；不保存 RAW、预览、
私人 sidecar 或导出文件。移动硬盘断开后可继续使用这套本地副本。

```sh
DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer \
python3 modern_UI/Spektrafilm/Tools/validate.py \
  --photos-root private-fixtures/release-cases \
  --scope cases --batch-format jpeg \
  --output /tmp/new-silverphase-case-run
```

`cases` 仅导出清单里的十张不同 RAW，不递归挑选目录中的其他照片。它执行
画布契约、真实 RAW 的 DI 流程，以及逐张全尺寸批次导出；检查实际照片数量、
导出尺寸、位深、ICC、图像可解码性和完整渲染次数。缺文件、哈希错误、失败
或跳过都会拒绝本次门禁。也可用 `--batch-format tiff` 跑同一固定集合。
验证使用临时副本，源码镜像明确排除 `private-fixtures/` 和 `output/`。

此模式与下方四角色 `photos` 门禁不同：十张都是真实 RAW，不冒充外部开发器
导出的 encoded-JPEG/TIFF，也不补足历史 Nikon、A7 III 等特定相机素材。
新门禁本轮 16 项通过、0 失败、0 跳过；十张均成功全尺寸 JPEG 导出。
结果不等于物理模型的独立准确性验证。详见
[本轮案例记录](../../performance/VALIDATION-CASES-2026-10-31.md)。
当前界面及 100% 颗粒／光晕开关截图见[案例页](../../screenshots/current/README.md)。

## 外部素材与隔离

[素材清单](SpektrafilmTests/Fixtures/validation-manifest.json)
只保存相对路径、相机、ImageIO 尺寸、格式信息及 SHA-256，不存照片。
现选定的四种输入为：

| 角色 | 输入 | 验证含义 |
|---|---|---|
| raw-standard | Sony ILCE-7RM5，6240×4160 的 ARW | 真实 RAW 解码、修改／复位、全尺寸成片导出 |
| raw-high-resolution | 同相机，9504×6336 的 ARW | 60 MP 输入与确定性修改／复位 |
| encoded-jpeg | 4096×3072、8-bit sRGB JPEG | 编码 RGB 输入，不能作为 RAW 参考 |
| encoded-tiff | 6336×9504、16-bit ProPhoto TIFF | 外部已处理的 RGB 输入，不能声称恢复原始场景 |

其他机器可以通过 `--manifest /path/to/manifest.json` 使用自己的照片清单。
清单必须包含四个不同角色，记录真实相对路径、SHA-256 和 ImageIO 宽高；
需明确确认输入格式和颜色语义，不将缺失的 RAW 替换成合成 TIFF。
照片与清单可放在仓库外部。换素材应记录新的覆盖范围，不沿用本次结果。

清单尺寸为 ImageIO 文件属性；EXIF 方向可能使解码后的宽高互换。
这两种 RAW 尺寸来自同一相机，不声称覆盖了多种传感器或厂商。

验证入口先核对原文件哈希，复制源码和素材到临时位置，以避开测试
宿主读取 Documents 的 macOS 隐私限制。每个测试再制作独立照片副本，
不复制已有 sidecar；导出和编辑只写副本的目录。运行结束重新核对原
照片哈希，然后清理临时源码与素材。日志、`.xcresult`、JSON 和批次
表格保存在输出目录；这些可能包含私人文件名，不应当作发布素材上传。

没有将这些照片重命名为历史的 Nikon Z7 II 或 A7 III 测试图。仍需要
那些特定输入的旧用例保留明确跳过，等待按当前产品契约迁移；其中
Nikon 镜头默认校正等专用场景，当前 Sony 照片不能替代。

## 门禁覆盖

- 真实像素：修改印相曝光确实改变结果，关闭颗粒／眩光后复位逐像素
  一致。这证明控制和状态传递，不等于独立验证胶片物理模型的准确度。
- 成片交付：全尺寸 TIFF／JPEG 可由 ImageIO 读取，尺寸匹配解码方向，
  位深正确，带目标 ICC。
- DI：真实 RAW 的 16-bit Cineon 主图不带显示 ICC，视图 LUT 同目录存在；
  普通 RGB 导出 DI 写入的是带 ICC 的显示视图。
- 现代画布：浮动 inspector 开关改变 Fit 的可见区域和位置，Metal
  画布维持尺寸；不存在已经移除的悬停胶囊区域。
- 显影：GPU 单元测试验证分层浮现、终点不改像素、取消和 Reduce Motion。
- 原生引擎：下面的 smoke、math guard 和扩展 gate。生成 `.cube`、内核、
  参数及引擎边界改变时应跑适用检查。

```sh
engine/build.sh all
engine/build/gpu_smoke engine/resources/spektrafilm.metallib
engine/tests/check_math_guard.sh
# 外部 Python 环境需要 numpy；仅用于开发测试，不是运行时依赖。
PYTHONPATH=engine/tests <python-with-numpy> engine/tests/upstream_controls.py
```

本次实际运行结果见 [验证记录](../../performance/VALIDATION-REPORT-2026-10-01.md)。

项目索引和打包资源检查由 `validate.py` 自动执行。原生检查不会被完整
XCTest 自动替代；真实窗口帧率、实际手势、视觉观感、其他相机以及签名／
公证分发也不在这些用例能证明的范围内。
