# Silverphase 验证

当前验收围绕本地原生 C++／Metal 引擎和真实照片的完整工作流。冻结的
旧 Python fork 不再保留，不作为运行验收的前提；`engine/tests/parity_*.py`
仍是历史工具，不将未运行的 oracle parity 写为通过，也不拿新脚本
冒充独立物理参考。实际色彩科学能力仍受实测配置和输入解码边界限制。

## 可重复执行

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
