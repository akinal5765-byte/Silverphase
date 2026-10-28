# 工作区集成与全局文档复核 — 2026-10-28

本轮整理已有未提交的产品改动：iOS/iPadOS 原生编辑器、共用模型／几何／
输出着色器／图标、产品黑白配置与纸等级、镜头滤镜、片边和日期后背、
桌面半格配对，以及分条执行与内存生命周期调整。未丢弃既有功能代码。
本轮新增的工作是全局文档、历史归档、缓存排除与来源记录修正。

## 本轮实际执行

本机 Apple M1 Pro；使用 Xcode 27.1 和其 Metal Toolchain，通过每条命令的
`DEVELOPER_DIR` 选择工具链，没有改全局 Xcode 选择。原生 Python 检查使用
外部带 NumPy 的解释器；它不是应用运行时依赖。日志和构建输出留在 `/tmp`，
没有放入仓库。本轮不报告新的性能基准，也没有把旧真机计时当作复测。

| 门禁 | 本轮结果 |
|---|---|
| `engine/build.sh all` | 通过：Metal 库、静态／动态库、三个原生驱动及桌面资源打包 |
| macOS `Spektrafilm` Debug build | 通过，生成 `Silverphase.app` |
| macOS `SpektrafilmTests` 完整 target | 541 项，494 通过、0 失败、47 跳过 |
| iOS `Silverphase` Debug / iphonesimulator build | 通过，关闭签名；不等同于真机运行 |
| 两个平台工程生成器 `--check` | 通过 |
| 桌面 bundle 资源预检 | 通过 |
| `gpu_smoke` | 通过：GPU、safe math、基础内核、结果纹理及 arena |
| `check_math_guard.sh` | 通过：故意构建的 fast-math 库被拒绝，正常库通过 |
| `product_blackwhite.py` | 通过：来源哈希、别名、八种胶片的中性印相／颗粒／EDR／灰阶／DI |
| `camera_filters.py` | 通过：八种滤镜、灰阶补偿、彩色响应、缓存失效及复位 |
| `paper_grades.py` | 通过：八种胶片上的七级反差、补偿及负片复用 |
| `overscan_checks.py` | 通过：片门、标识、日期、配对区域及尺度检查，0 失败 |
| `overscan_striped.py` | 27 组片边／日期／普通图分条结果与整帧逐像素相同 |
| `strip_executor.py` | 通过：分条计划、阶段类别、halo、渲染与 reprint 像素一致 |
| `band_purity.py` | 通过：可分条阶段不能到达全图读取 |
| `accumulator_alias.cpp` | 编译运行通过：FIR、混合 FIR/IIR、IIR 和无效通道的复用逐字节一致 |
| 文档本地链接与 `git diff --check` | 通过（历史快照保留原始相对引用，不将其作为当前指南） |

完整 XCTest 中新增的手机默认值契约、胶片呈现、参数、材料目录和剪贴板
用例均执行。没有为文档改动重复跑全套，也没有给低影响文档内容新增单元测试。
原生编译仍报告已有的 C-linkage helper 返回 `Json` 警告；本轮未更改它们。
构建脚本每次运行的 Xcode 提示不是测试失败。

## 47 个跳过项

| 原因 | 数量 |
|---|---:|
| 旧 1 MP smoke 素材不在 checkout | 12 |
| A7 III 专用 RAW 不在 checkout | 23 |
| A7R V 旧固定 RAW 不在 checkout | 1 |
| Nikon Z7 II 专用 RAW 不在 checkout | 3 |
| 未配置当前 manifest 的真实照片门禁 | 4 |
| 未提供明确授权的临时手机色彩校对 RAW | 1 |
| 未启用的批次／压力／导出性能测试 | 3 |

因此完整 target 成功表示当前可执行部分通过，不表示照片素材覆盖完整。
本轮没有执行 manifest-based 真实照片门禁，没有重建历史 baseline、冻结
Python oracle 或使用合成图冒充缺失 RAW。没有新的独立物理模型 oracle parity。

## 文档与工作区

- 根 README 中英文、ARCHITECTURE、AGENTS、API 和 CONTRACT 更新到当前
  双平台原生结构，明确 Cineon DI、缓存失效、资源覆盖及平台功能差异。
- 新增 `docs/README.md` 索引；原架构／API／CONTRACT 保存于 `docs/history/`。
  AGENTS 保留编号陷阱，并标明旧 Python／界面／测量记录的历史范围。
- macOS/iOS 工程说明及 iOS 控制审计更新；移除当前设置说明里过期的固定
  预览分辨率选择器描述，保留历史设备测量的原始配置。
- 图标设计迭代保留为设计历史，两平台只使用共用的生产 `.icon`。
- 排除 `com.apple.DeveloperTools/` 本机缓存；没有删除源码、私人素材或签名资料。
- `UPSTREAM.json` 保留 overscan 的原始上游哈希，补充本地适配说明和本地哈希，
  不再称已经适配的代码为“原样采用”；产品配置原始声明和作者署名保持。
  修正后重新同步资源并增量构建两个应用，核对两端包内来源清单与源码逐字节相同。

## 可追溯证据与边界

本机完整测试 bundle：`/tmp/silverphase-workspace-tests.xcresult`。
日志：`/tmp/silverphase-workspace-{engine,app,tests,ios,native}.log`；原生
accumulator 可执行文件为 `/tmp/silverphase-workspace-accumulator`。这些是
本机临时证据，不是发布附件或可携带的素材。最终资源同步及增量构建日志另见
`/tmp/silverphase-workspace-{bundle,app,ios}-final.log`。

当前门禁与复现方法见 [桌面验证指南](../modern_UI/Spektrafilm/VALIDATION.md)
和 [iOS 工程指南](../ios/README.md)。真机触摸／视觉观感、Photos 权限及写入、
设备签名／Increased Memory Limit 授权、对外分享、完整素材验证、签名公证
和发布均未在本轮复验。仅创建本地提交，不执行远端推送或发布。
