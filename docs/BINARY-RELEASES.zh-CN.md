# 二进制发布

**简体中文** · [English](BINARY-RELEASES.md)

[GitHub Releases](https://github.com/akinal5765-byte/Silverphase/releases) 提供发布说明和 macOS 安装包。
iPhone 与 iPad 用户可从 [App Store](https://apps.apple.com/app/id6829987567) 安装 Silverphase，通过 [TestFlight](https://testflight.apple.com/join/uwY3ZYJp) 体验测试版。
发布说明记录对应的源码标签或提交、系统要求、签名状态和验证范围。发布版本不一定包括所有规划中的功能。

各平台的版本号和构建号独立维护。GitHub Releases 记录源码里程碑和 macOS 安装包；App Store 与 TestFlight 分别显示其渠道中可安装的 iOS 版本。GitHub 上历史 iOS 安装包均未签名。

目前的 macOS 安装包是 1.4.0（构建 7）。iOS／iPadOS [1.4.0（构建 12）](../ios/releases/1.4.0.md) 的状态见[上传与审核记录](../ios/APP-STORE.md#140-12--2026-11-27)。App Store 与 TestFlight 的可用状态互不等同。

## macOS

桌面安装包使用独立的 `macos-v<version>` 发布标签。桌面端的更新检查也识别附有 macOS DMG 的旧版无前缀标签。

- 仅支持 Apple 芯片（arm64），要求 macOS 15 或更高版本。不支持 Intel Mac。
- 打开 `Silverphase-<version>-macOS-arm64.dmg`，将 Silverphase 拖入「应用程序」。
- 仓库打包脚本生成的公开构建使用 ad-hoc 签名，供 Apple 芯片 Mac 执行；**没有 Developer ID 签名，也未经 Apple 公证**。这不代表 Apple 已批准软件。
- 如果系统阻止打开软件，请到「系统设置 → 隐私与安全性」查看提示。核对来源和校验和后，再选择「仍要打开」。无需全局关闭 Gatekeeper。参见 Apple 的[打开 App 指南](https://support.apple.com/102445)；本机安全策略可能限制这些操作。

从 [GitHub Release](https://github.com/akinal5765-byte/Silverphase/releases/tag/macos-v1.4.0) 下载 **macOS 1.4.0（构建 7）**。另见[版本说明](../modern_UI/Spektrafilm/releases/1.4.0.md)与[上一版 1.3.1 安装包](https://github.com/akinal5765-byte/Silverphase/releases/tag/macos-v1.3.1)。

1.4.0 使用 Silverphase 自己的应用标识符，桌面版数据与 SpektraLab 分开存放。1.3.1 或更早版本的编辑与偏好不会自动迁移。替换旧 App 前，请按 [macOS 升级指南](MACOS-IDENTITY-UPGRADE.md)备份，并按需复制编辑记录和导出配方。已发布的 1.3.1 安装包不变。

macOS 1.2.0（构建 4）加入了 Lightroom Classic 单张照片外部编辑。
把 Silverphase 安装到「应用程序」，再在 Lightroom 的其他外部编辑器设置中选中它；不需要单独安装 `.lrplugin`。参见[图解指南](LIGHTROOM-CLASSIC.md)与[源码版本说明](../modern_UI/Spektrafilm/releases/1.2.0.md)。

## iPhone 与 iPad

正式版从 [App Store](https://apps.apple.com/app/id6829987567) 安装。上一版 iOS 1.3.1（构建 11）的源码里程碑见 [GitHub Release](https://github.com/akinal5765-byte/Silverphase/releases/tag/v1.3.1) 及[源码说明](../ios/releases/1.3.1.md)。

测试版通过 [TestFlight](https://testflight.apple.com/join/uwY3ZYJp) 安装。
在 iPhone 或 iPad 上打开邀请链接；如有提示，先安装 Apple 的 TestFlight App，然后接受邀请并安装 Silverphase。能安装哪个测试版，以 TestFlight 显示为准，可能与仓库源码版本不同。
每个测试构建的可用期最长为 90 天；参见 [Apple 的 TestFlight 概览](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)。

### 历史未签名 IPA

参见 [iOS 1.2.5 发布公告](https://github.com/akinal5765-byte/Silverphase/releases/tag/v1.2.5)和[源码说明](../ios/releases/1.2.5.md)。以下只适用于 GitHub Releases 上的历史未签名 IPA。

- 要求 iOS／iPadOS 18 或更高版本，arm64。
- 源码提供仅竖屏的常规 iPhone 布局，含悬浮控件及纵向胶片／相纸列表；见[手机截图](../screenshots/ios/2026-11-02/README.md)。Duo 和 iPad 有各自的导航布局。模拟器截图不能证明真机上的导出和内存表现已经验证。
- `Silverphase-<version>-iOS-unsigned.ipa` 是**未签名的真机构建**，不是模拟器 App、App Store 下载，也不是已经配置好设备安装权限的安装包。
- 用户需自行完成签名、配置与安装。本项目不提供共享签名服务或面向特定设备的描述文件。
- App 请求 `com.apple.developer.kernel.increased-memory-limit` 权限，记录在 `Silverphase-iOS-RequiredEntitlements.plist` 中。签名工具或账号需要正确处理这项能力，并非所有侧载方式都能授予。可用内存及全分辨率导出能力取决于设备和签名配置。
- IPA 不含开发者证书、私钥、描述文件、私人测试照片或私有实验素材。

标准签名与配置流程见 Apple 的[向已注册设备分发文档](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices)。
其他安装工具有自己的要求，本项目不推荐或保证任何特定工具。

## 校验和与对应源码

将 `SHA256SUMS.txt` 下载到发布文件所在目录，再运行：

```sh
shasum -a 256 -c SHA256SUMS.txt
```

各版本都可通过 GitHub 的 **Source code (zip/tar.gz)** 按对应标签下载源码。其中包含构建脚本、引擎源码和已跟踪的公开资源；二进制包内另附许可文件。可下载的二进制资产随附构建记录，标明原始提交和打包数据。

## 复现发布构建

使用文档指定的 Xcode／Metal 工具链，从无未提交修改的检出目录开始：

```sh
export DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer
python3 tools/package-public-release.py --platform macos \
  --tag macos-v<version> --output output/releases/macos-v<version>
python3 tools/package-public-release.py --platform ios \
  --tag v<version> --output output/releases/v<version>
```

脚本强制使用 Release 配置和 `SILVERPHASE_LOCAL_MATERIALS=0`，核对实际的平台、架构和最低系统要求，检查素材数量、包内无私有素材，以及随附声明与源码一致。脚本记录对应的源码提交，验证 macOS 的 ad-hoc 签名和 DMG 完整性，并在生成 IPA 前去除 iOS 签名。发布时只上传经选定的资产、安装说明、权限请求、构建记录和校验和，不要上传构建工作目录或日志。

如提供所需凭据，桌面端的 `Tools/package.sh` 还支持单独的 Developer ID 归档、导出与公证流程。
iOS 的分发流程及上传验证见 [App Store 记录](../ios/APP-STORE.md)。
