# Silverphase 支持 / Support

Silverphase 是适用于 iPhone 和 iPad 的免费胶片与印相模拟编辑器，要求 iOS / iPadOS 18 或更新版本。RAW 格式兼容性取决于系统的 Apple RAW 解码器。 [App Store](https://apps.apple.com/cn/app/id6829987567) · [TestFlight 测试版](https://testflight.apple.com/join/uwY3ZYJp)

## 联系维护者

通过 [GitHub Issues](https://github.com/akinal5765-byte/Silverphase/issues) 提交问题或功能建议。请附上设备型号、系统版本、Silverphase 版本、复现步骤，以及实际结果与预期结果。

Issues 是公开渠道。请勿上传私人原片、位置、证件、密码或完整诊断日志。截图请先遮挡私人信息；只有在拥有分享权限时才提供示例图片。提交问题需要 GitHub 账户，阅读现有问题无需账户。

## 常见问题

**照片与编辑会保存在哪里？** 导入原文件和编辑记录保存在应用内图库。重启后可继续编辑；移除图库中的照片不会删除导入前的来源文件或系统照片。卸载应用前请先导出需要保留的成片，并妥善保留原文件。

**导入 RAW 失败怎么办？** 确认系统能够识别该相机文件，并尝试从文件 App 选择完整原片。相册中的云端原片可能需要先下载。不同相机与 RAW 格式的支持情况因系统版本而异。

**为什么导出被内存保护中止？** 大尺寸照片及某些效果组合需要更多内存。可尝试降低导出像素数、缩小批次数量，并在设置中释放渲染缓存。导出能力取决于设备、照片和当前可用内存。

**锁屏相机没有响应怎么办？** 设备认证前按实体 Camera Control 时，取景可能短暂冻结或快门不可用。先解锁再按键，或使用控制中心的 Silverphase 相机控件。锁屏拍摄后，在解锁并打开 Silverphase 时检查原片是否已入库。

**为什么不能保存到照片？** 在系统设置中检查 Silverphase 的添加照片权限，也可改为导出到文件。导出的数字中间片文件不作为普通成片写入照片图库。

**为什么两次照片的观感不同？** RAW 解码、白平衡、输入色彩空间、曝光和配方都会影响结果。胶片颗粒及眩光也是成像效果的一部分。反馈颜色问题时，请说明输入格式与配方。

**Layerlight 是必需的吗？** 不是。它是同一开发者的另一款独立应用；Silverphase 的编辑与导出不依赖安装 Layerlight。

查看 [隐私政策](PRIVACY.md) 和 [源码及许可证](https://github.com/akinal5765-byte/Silverphase)。Silverphase 为基于 Hanze Qiu 的 SpektraLab 与 Andrea Volpato 的 spektrafilm 的独立衍生项目。

---

## English

Silverphase is a free film and print simulation editor for iPhone and iPad, requiring iOS / iPadOS 18 or later. RAW compatibility depends on Apple's system RAW decoder. [App Store](https://apps.apple.com/app/id6829987567) · [TestFlight beta](https://testflight.apple.com/join/uwY3ZYJp)

Contact the maintainer through [GitHub Issues](https://github.com/akinal5765-byte/Silverphase/issues). Include the device, OS and app versions, reproduction steps, expected behavior and actual behavior. Issues are public. Remove private information from screenshots and do not post private originals, location information, credentials, identity documents or complete diagnostic logs. A GitHub account is required to submit an issue, but not to read existing issues.

- Imported originals and edits remain in the app's local library. Removing an app-library item does not remove the original source in Photos or Files. Export needed work and retain your originals before uninstalling.
- For RAW import issues, check system support and try the complete original from Files. Cloud originals may need downloading first.
- For memory-related export failures, reduce output resolution or batch size and release rendering caches in Settings. Capacity depends on your device, image, recipe and available memory.
- If the lock-screen viewfinder freezes or the shutter is unavailable, unlock before pressing Camera Control or use the Silverphase camera control in Control Center. After a lock-screen capture, unlock and open Silverphase to check that the original reached the library.
- If saving to Photos fails, check add-only photo permission in system settings or export to Files. Digital intermediate files are not saved to Photos as ordinary images.
- RAW decoding, white balance, input color space, exposure and recipe affect the result. Include input format and recipe when reporting color problems.
- Layerlight is optional. Silverphase editing and export work independently of it.

See the [privacy policy](PRIVACY.md) and [source and licences](https://github.com/akinal5765-byte/Silverphase). Silverphase is an independent derivative of Hanze Qiu's SpektraLab and Andrea Volpato's spektrafilm.

## 取景与定位 / Viewfinder and location

近似取景用于构图。测光、柔光和系统视频处理均可能影响它与 RAW 成片的差异。设置可选择近似、系统或实验性原生预览；应用内相机还提供胶片曝光补偿、RAW 偏好和分辨率选择。拍摄定位需授权，可在设置中关闭。导出是否保留位置由导出设置决定。[iOS 1.2.5 说明](../ios/releases/1.2.5.md)

The approximate viewfinder aids composition. Metering, diffusion, and system video processing can affect how it differs from the developed RAW. Settings offer approximate, system, and experimental native previews. The in-app camera also offers film exposure compensation, RAW preference, and resolution choices. Capture location requires permission, can be disabled, and follows export metadata policy. [iOS 1.2.5 notes](../ios/releases/1.2.5.md)

## macOS：升级与导出 / Upgrading and exporting

- 从旧版升级到 1.4.0 前，先按[迁移指南](MACOS-IDENTITY-UPGRADE.md)备份旧编辑，不要把 SpektraLab 的整个数据目录复制过来。公开下载见[二进制发布](BINARY-RELEASES.md)。
- 普通画布与 sRGB 成片有差别时，在「导出」里选定色域，再打开「输出软打样」。sRGB 无法完整呈现某些高饱和色；需要比较文件与软打样时，使用同一个配方和能识别 ICC 的查看器。反馈时附上输出色域及格式即可，不必上传原片。
- Before upgrading to macOS Silverphase 1.4.0, follow the [upgrade guide](MACOS-IDENTITY-UPGRADE.md) to back up and selectively copy edits. See [Binary releases](BINARY-RELEASES.md) for the public download.
- For color differences between the canvas and an sRGB export, use Output Soft Proof with the same export recipe and compare the file in a color-managed viewer. Some saturated colors cannot fit in sRGB. Include the output color space and format in a report, without attaching private originals.

## 材料指纹 / Material fingerprint

如果同一张照片和配方更新前后的颜色不同，可在支持此功能的 iOS 版本里从「关于 Silverphase → 复制当前材料指纹」复制一串 SHA-256。在 macOS 手动保存的诊断包中，只需从 `summary.json` 复制 `current_material_pack_sha256`，不用分享整个诊断包。请同时记录 App 版本和构建号。

指纹是当前应用所带材料数据（胶片／相纸配置、合并后的印相滤色、相纸级别和预计算表）的校验值。不同值表示随包材料字节有差异，但不能断定这就是色差的原因；相同值也不能排除解码器或引擎代码变动。它不标记旧编辑，不会固定材料版本，也不会上传数据。

For a color change after updating, copy the current material fingerprint from iOS About Silverphase, or copy only `current_material_pack_sha256` from the `summary.json` inside a macOS diagnostics bundle you saved. Include the app version and build. This SHA-256 identifies the material data staged with the running app, not the engine code or the data used by an older edit. Different hashes identify different material bytes, not necessarily the cause of a visual change. No edit migration, version pinning, or upload occurs.
