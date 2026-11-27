# iOS／iPadOS App Store 分发

[简体中文](APP-STORE.zh-CN.md) · [English](APP-STORE.md)

> 本页维护当前分发流程和各版本状态；较早的提交与排查日志保留在英文原文。

Silverphase 已在 [App Store](https://apps.apple.com/app/id6829987567) 提供（包括中国大陆），测试渠道为 [TestFlight](https://testflight.apple.com/join/uwY3ZYJp)。当前可安装版本以商店页面为准；GitHub 标签对应源码节点，并不等于商店上架。2026-11-20 的查验记录：美国、日本和香港当时显示 **1.2.5**，中国大陆尚未查到；开发者于 2026-11-25 确认中国大陆已上架。

## 1.4.0（12）· 2026-11-27

Xcode 于当日确认上传。签名归档使用公开材料，对应源码提交 [`7ef8fd4`](https://github.com/akinal5765-byte/Silverphase/commit/7ef8fd45cd1188cfe6cb7761a7e17a234e2500cf)。主应用、控制中心相机入口和锁屏相机扩展均为 1.4.0（12），最低 iOS／iPadOS 18。

构建 12 已关联到 App Store 版本；已填写简体中文和英文版本说明，并单独提供 TestFlight 测试说明。TestFlight 显示可测试，开发者确认同日提交 App Store 审核。本条不代表通过审核或公开上架。参阅 [双语版本说明](releases/1.4.0.md)。

## 1.3.1（11）· 2026-11-25

Xcode 确认送达 App Store Connect，当时显示正在处理。归档和 dSYM 保留在本地。签名主应用及两个相机扩展通过版本和签名校验，主应用保留 Increased Memory Limit 权限。公开材料构建对应 `c65902c`。[源码标签](https://github.com/akinal5765-byte/Silverphase/tree/v1.3.1) · [版本说明](releases/1.3.1.md)。

## 1.3.0（10）· 2026-11-20

App Store Connect 记录 **6829987567**，SKU `silverphase-ios`、bundle ID `com.silverphase.editor`，最低 iOS／iPadOS 18。用合并提交 `187a0df` 和公开材料归档。签名包及其三个组件通过签名、版本、最低系统与资源校验；主应用保留内存权限并带隐私清单，归档和 dSYM 保存在本地。Xcode 确认上传；Apple 处理和 App Review 为两个独立阶段。[精确源码及版本说明](https://github.com/akinal5765-byte/Silverphase/releases/tag/v1.3.0)。

## 1.2.1（7）候选构建 · 2026-11-09

[发版准备记录](releases/1.2.1.md) 列明改动、验证和仍待完成的签名／真机／商店步骤。应用、控件及锁屏扩展版本一致。定位默认开启但仍须获「使用 App 期间」权限；隐私与支持文案说明本地 GPS 元数据及导出时去除位置。上传前据此复核商店隐私问卷。该条源码准备记录不表示已上传、提审、合并或上线。

## 2026-11-03 历史准备记录（摘要）

首发当时按全球免费分发准备，主语言为简体中文。1.1.1（3）已上传并处理完毕，保存出口合规答复后 TestFlight 当时显示 “Ready to Submit”；此阶段尚未提审或正式发布。已填写中文商店文案、隐私信息并验证支持链接。签名归档及导出通过，源码为 `b19d870`；该阶段未重复真机验收，自动截图测试未启动，无法作为界面验收。

当时没有确认中国大陆 ICP 备案适用性，未使用 Layerlight 的备案号，也未替开发者接受协议。应用不要求登录，照片处理在设备端完成；系统「照片」或「文件」可能访问用户选定的云端内容。Layerlight 只是设置与关于中的可选同开发者应用推荐，无跟踪参数和广告 SDK，不是 Silverphase 的使用前提。完整过程和当时拟给 Apple 的准确说明留在 [英文原始记录](APP-STORE.md#historical-store-preparation--2026-11-03)。

## 分发维护

- 核实 GPL-3.0-or-later 与拟采用的 Apple 分发条款是否兼容，必要时取得权利方许可。目前仓库中未发现 App Store 例外，免费定价不改变许可义务。保留署名和精确对应源码，参见 [许可说明](../LICENSES.md)。
- 使用既有商店记录 **6829987567**、主应用标识符 `com.silverphase.editor` 以及扩展标识符 `com.silverphase.editor.camera-control` 和 `com.silverphase.editor.locked-camera`。已有构建上传后换主标识符需要不同商店记录，不是现有应用更新。参见 [Apple 的 bundle ID 文档](https://developer.apple.com/documentation/xcode/changing-the-bundle-identifier)。
- 在 Xcode 选正确签名团队，分发配置保留 `com.apple.developer.kernel.increased-memory-limit`。在 App Store Connect 校验可用门店、定价和待办协议。
- 提供含维护者联系方式的 [隐私政策](../docs/PRIVACY.md) 和 [支持页](../docs/SUPPORT.md)，并在应用内提供可访问的隐私政策入口。
- 准备 iPhone 和 iPad 截图、说明、关键词、类别、年龄分级问卷、审核联系人及指导、出口合规答复。商店图片只用公开或明确授权的照片。

## 隐私清单核对

生成工程将 `Silverphase/PrivacyInfo.xcprivacy` 作为资源拷贝到应用包根目录。当前声明：

| 类别 | 声明理由 | 用途 |
|---|---|---|
| 用户默认设置 | CA92.1 | 应用私有偏好及导出配方／预设 |
| 系统启动时间 | 35F9.1 | 预览重试和导出计时 |
| 文件时间戳 API | C617.1 | 应用容器的文件元数据，以及引擎常量读取的 `fstat` |

清单声明无跟踪、无收集的数据；检查过的原生源代码不含分析／上传客户端。引入服务或 SDK 后应重新评估。隐私政策仍需如实说明本地照片元数据、编辑与诊断，不把系统管理的备份、用户选定的云端目标或「照片」／iCloud 行为写成禁用。商店隐私问卷是独立步骤。

Apple 资料：[须声明理由的 API](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype) · [应用隐私要求](https://developer.apple.com/help/app-store-connect/reference/app-information/app-privacy/) · [截图规格](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)。

## 归档校验

生成并校验工程，使用共享 `Silverphase` scheme 的 Release 归档（带 dSYM）。公开构建关闭本地材料：

```sh
python3 ios/Silverphase/Tools/gen-project.py --check
python3 ios/Silverphase/Tools/check-release-identity.py
DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer \
SILVERPHASE_LOCAL_MATERIALS=0 \
xcodebuild -project ios/Silverphase/Silverphase.xcodeproj \
  -scheme Silverphase -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/silverphase-appstore-derived \
  -archivePath /tmp/silverphase-appstore-preflight.xcarchive \
  CODE_SIGNING_ALLOWED=NO archive
python3 ios/Silverphase/Tools/check-release-identity.py /tmp/silverphase-appstore-preflight.xcarchive
```

以上是未签名预检，不是可上传的分发归档。正式分发使用匹配的团队与配置文件；在 Xcode Organizer 验证签名归档，重跑标识检查，并核对签名权限及隐私报告。确认不含 `LocalMaterials/` 和 `*_experimental.json`，基础／产品资源与许可通知齐全。

提交前在真机 iPhone 和 iPad 测试签名 Release：冷启动、照片／文件导入（含拒绝权限）、编辑与重启恢复、导出到「文件」和「照片」、内存压力。参阅 [iOS 指南](README.zh-CN.md)。编译和归档不能替代画面、手势、全尺寸导出、真机或 App Review 验收。历史 Xcode 构建警告及检查细项保留在 [英文归档验证记录](APP-STORE.md#archive-verification)。
