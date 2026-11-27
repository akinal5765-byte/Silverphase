# Silverphase 文档

**简体中文** · [English](README.md)

Silverphase 是 Hanze Qiu 的 SpektraLab 与 Andrea Volpato 的 spektrafilm 的独立衍生项目。现行功能以源码和平台指南为准。工艺顺序：**预处理 → 胶片 → 显影 → 彩色放大（印相）→ 扫描**。裁切与片边是独立工具。

## 下载与使用

| 想找什么 | 去哪里 |
|---|---|
| 产品介绍和基本构建 | [中文 README](../README.md) |
| macOS 下载、签名、App Store、TestFlight | [下载与发布渠道](BINARY-RELEASES.zh-CN.md) |
| 最新版本、构建号和验证 | [macOS 1.4.0（构建 7）](../modern_UI/Spektrafilm/releases/1.4.0.md) · [iOS／iPadOS 1.4.0（构建 12）](../ios/releases/1.4.0.md) |
| App Store 上传、送审和测试 | [分发记录](../ios/APP-STORE.zh-CN.md) |
| 升级、使用帮助和隐私 | [macOS 迁移](MACOS-IDENTITY-UPGRADE.md#macos-新版如何保留旧编辑) · [支持](SUPPORT.md) · [隐私政策](PRIVACY.md) |
| Lightroom Classic 外部编辑 | [图文教程](LIGHTROOM-CLASSIC.md) |
| 真实照片界面和成片案例 | [iPhone／iPad 截图](../screenshots/ios/2026-11-27/README.md) · [胶片与相纸案例](showcase/README.zh-CN.md) |
| 移动端使用、构建和设备限制 | [iOS 指南](../ios/README.zh-CN.md) · [设计规范](../ios/DESIGN.md) · [控件与限制](../ios/CONTROL-AUDIT.md) |

## 开发与验证

| 想找什么 | 去哪里 |
|---|---|
| 共享原生引擎和两端职责 | [架构](../ARCHITECTURE.zh-CN.md) |
| ABI、JSON、所有权、Cineon 与片边 | [API 说明](../API-SPEC-callable-render-service.zh-CN.md) |
| 宿主与引擎契约 | [契约](../CONTRACT-frontend-backend.zh-CN.md) |
| 桌面工程、布局、5219 和验证边界 | [macOS 指南](../modern_UI/Spektrafilm/README.md) · [历史界面规定与实现约束](../modern_UI/design/UI-SPEC.md) · [验证](../modern_UI/Spektrafilm/VALIDATION.md) |
| 材料来源、实验配置与私有覆盖层 | [材料来源](../license/DATA-SOURCES.md) · [本地材料](LOCAL-MATERIALS.zh-CN.md) · [随包通知](../modern_UI/Spektrafilm/Spektrafilm/Resources/Licenses/README.txt) |
| 图像与模型证据 | [图像范围](../license/ARTWORK.md) · [图像清单](../license/media-inventory.json) · [数据清单](../license/data-inventory.json) · [黑白](../engine/tools/profile_sources/blackwhite.md) · [片边](../engine/tools/profile_sources/film_edge.md) · [图标](../design/app-icon/README.md) |
| 贡献、写作和仓库维护 | [贡献指南](../CONTRIBUTING.zh-CN.md) · [写作规范](WRITING-GUIDE.md) · [维护规范](PROJECT-MAINTENANCE.md) · [开发与排查规则](../AGENTS.md) |
| 开源许可和发布检查 | [许可一览](../LICENSES.zh-CN.md) · [发布审计原件](OPEN-SOURCE-RELEASE.md) |

## 历史资料

| 想找什么 | 去哪里 |
|---|---|
| 过往发版与可下载的构建 | [GitHub Releases](https://github.com/akinal5765-byte/Silverphase/releases) · [macOS 源码记录](../modern_UI/Spektrafilm/releases/) · [iOS 源码记录](../ios/releases/) |
| 验证、性能与旧版界面 | [CineStill 800T](../performance/VALIDATION-CINESTILL-2026-11-02.md) · [实拍案例](../performance/VALIDATION-CASES-2026-10-31.md) · [本地和公开构建](../performance/VALIDATION-LOCAL-MATERIALS-2026-10-31.md) · [截图档案](../screenshots/README.md) |
| 早期实现、RFC 和实测记录 | [历史快照](history/) · [RFC](../rfc/) · [性能记录](../performance/) |

历史原件、RFC、原始许可和上游通知保留原文。过往数据不代表当前验收。不要为了匹配旧记录重新引入已退役的 Python 运行环境、基线或旧双栏界面；私人实拍原片仍放在仓库外。翻译范围与证据写法见[文档规范](WRITING-GUIDE.md)。
