# 验证补齐记录 — 2026-10-01

本轮基于 `544e831`，只补测试、验证工具和当前工程文档。没有改写胶片／
相纸实测数据，也没有恢复已删除的 baseline 或冻结 Python 环境。
用户确认不再保留旧参考仓库，可从照片目录选择新素材；新素材不是旧
Nikon／A7 III 场景的替身。

## 已验证

最终完整套件：496 项，454 通过、0 失败、42 跳过。应用构建、项目索引
与打包资源预检通过，diff 格式检查通过。跳过组成：旧 1 MP smoke
素材 12 项、A7 III 素材 23 项、A7R V 固定素材 1 项、Nikon Z7 II
专用素材 3 项，以及未显式启用的性能测试 3 项。它们未被悄悄计作通过。

- 真实照片选定门禁加 50 张 RAW 批次：20 项通过，0 失败，0 跳过。
  50 张均完成冲印和全尺寸 JPEG 文件写入，全尺寸渲染计数为 50。
- 四种输入的印相曝光修改改变实际像素；关闭颗粒／眩光后，曝光复位
  恢复逐像素一致结果。两个 RAW 来自同一 Sony 相机，约 26 MP／60 MP。
- 真实 RAW 的全尺寸 TIFF／JPEG：尺寸、位深和 ICC 正确；Cineon DI
  主文件、配套观看 LUT 和普通 RGB DI 导出通过独立用例。
- 两个旧 CanvasViewTests 的失效假设已替换为当前产品契约：不再有旧
  hover 区域；浮动 inspector 开关改变 Fit 遮挡，同时保持 Metal
  画布尺寸。13 项 CanvasViewTests 全部通过。
- 原生控制 gate、GPU smoke、数学安全 guard 通过。guard 还证明了
  故意用 fast-math 构建的 Metal 库会被拒绝。
- 素材哈希错误会在预检失败；运行后重新校验了所有原照片哈希，未改变。
- 故障注入：临时源码副本中将印相曝光增益固定为 1，JPEG 实图的
  曝光像素断言失败；故障不在项目源码，恢复后四类真实照片用例全部通过。

批次内存日志有 50 个导出结束采样，约 4.81–10.53 GiB，最后为 8.35 GiB。
这是进程的 physical footprint，包含缓存和测试宿主；不是峰值内存，
没有内存上限断言，不能据此声称已证明无泄漏或低内存安全。

首轮完整集成运行发现新测试错误地等待可淘汰的 print 缓存，导致 60 MP
用例超时（453 通过、1 失败、42 跳过）。诊断重跑证实结果已上传到画布；
超时日志明确记录 busy=false、pending=false、无错误且 cached=false；
低内存余量下缓存可以拒绝保留。测试完成条件已改为已处理状态与画布
当前持有的纹理，不改变应用内存策略，也不放宽实际像素和复位断言。

## 可复现入口与证据

命令和素材角色见 [VALIDATION.md](../modern_UI/Spektrafilm/VALIDATION.md)。
新增入口 `Tools/validate.py` 核对清单、隔离源码／素材、运行 XCTest、
输出 `.xcresult` 与结构化摘要，并核对原文件未改。只提交元数据清单，
不提交私人照片。另两项旧布局失败在此前已复现，本轮没有将它们跳过。

本机结果保存在 `/tmp/silverphase-validation-photos-20261001/`，包含
`summary.json`、`batch.tsv` 和 `TestResults.xcresult`；路径是本机证据，
不是随仓库分发的素材。最终完整结果位于
`/tmp/silverphase-validation-full-final-20261001/`。曝光故障的红／绿验证
日志分别为 `/tmp/silverphase-real-photo-fault.log` 和
`/tmp/silverphase-real-photo-green.log`。输出可能包含私人文件名，
不上传整份日志。

## 文档与边界

中英文首页与当前工程指南已更新底部材料选择、原生引擎及 Cineon DI
交付语义，替换当前指南里的旧 Python 服务和密度 TIFF 描述。历史 RFC、
架构与 AGENTS 保留，不把旧记录改写成今天的结果。

冻结 Python oracle 已退役；保留历史 parity 工具，但本轮不声称执行了
独立物理 oracle parity。当前照片没有覆盖其他相机或 Nikon 镜头专用
校正。窗口帧率、实际手势与视觉验收由用户完成；签名／公证分发未验收。
