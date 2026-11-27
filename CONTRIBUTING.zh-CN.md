# 参与 Silverphase

**简体中文** · [English](CONTRIBUTING.md)

修改文档前请查看[文档规范](docs/WRITING-GUIDE.md)，确认事实来源、中英文同步和验证写法。

Silverphase 是 Hanze Qiu 的 SpektraLab 与 Andrea Volpato 的 spektrafilm 的独立衍生项目。请先阅读 [README](README.md)、[文档索引](docs/README.zh-CN.md)和[开发约定](AGENTS.md)。

请在 [Silverphase](https://github.com/akinal5765-byte/Silverphase) 提交 Issue 或 Pull Request。说明用户遇到的问题、改动后的行为和验证结果，包括失败与跳过的测试。每个改动尽量小而清晰。请将贡献提交到 Silverphase；`upstream` 远端指向原始 SpektraLab 项目，在这里仅用于读取。

## 贡献内容的许可

只提交你有权提交的素材。代码贡献使用 GPL-3.0-or-later；基于 CC BY-SA 配置或 LUT 的衍生内容仍使用 CC BY-SA 4.0。保留现有声明和署名，并记录引入的代码或数据的来源、版本、许可、修改内容及可复现的处理步骤。提交 PR 不会转让版权，也不授予商标权。组件边界见 [LICENSES.md](LICENSES.md)。

请勿提交私人照片、与原片分开的编辑记录、凭据、签名描述文件、专有参考数据集，或未经授权再分发的包装素材。报告问题时优先使用合成渐变或色块；如验证需要外部样本，说明所需条件即可，不要上传私有样本本身。

## 实现与验证

使用 SwiftUI、Observation、actor，以及共享的 C++20／Metal 引擎。Apple 芯片设备的最低支持系统为 macOS 15 与 iOS 18。各平台构建命令见对应指南；请用 `DEVELOPER_DIR` 选择 Xcode，不要改动全局设置。

参数定义位于 `engine/src/core/params.cpp`；公开 ABI 位于 `engine/include/spektrafilm/spk_engine.h`。调整接口边界时，需要同步 Swift 映射、两个平台端和原生测试。请遵循当前的 [API](API-SPEC-callable-render-service.md)及[接口契约](CONTRACT-frontend-backend.md)。历史服务文档描述的 Python 协议不是受支持的运行时接口。

执行与改动直接相关的检查。新增或删除源文件后，请重新生成对应工程，并对两端工程生成器都运行 `--check`。集成时运行完整桌面测试；改动渲染时，执行 AGENTS.md 所列引擎检查。明确报告跳过的用例；能成功构建并不代表手势、真机导出或视觉表现已经验证。

公开发布前，运行 `python3 tools/check-open-source.py`，验证许可文件副本、源码链接、存储数据的哈希与视觉资产清单。
使用 Gitleaks 8.30.1 在本地扫描主分支历史及待发布源码：

```sh
python3 tools/check-release-secrets.py --gitleaks /path/to/gitleaks --output /tmp/new-release-audit
```

报告会脱敏并存放在 Git 之外；被忽略的私有目录不会为此次扫描加入暂存区。`.gitleaks.toml` 中唯一按具体偏好值匹配的例外已确认不是机密；请勿豁免整个文件或整条规则。

发布前请遵循[开源发布检查表](docs/OPEN-SOURCE-RELEASE.md)。
