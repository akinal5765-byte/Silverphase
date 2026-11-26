# iOS field tethering · iOS 外拍联机

This Debug prototype is for getting camera photos into an iPhone or iPad and
developing a preview with a film selected before shooting. It does not write a
recipe back to the camera, modify the original, or auto-save a finished photo
to the system library.

## USB: direct stills from compatible cameras

1. On iOS/iPadOS, open the Silverphase library menu → **Tethered Shooting** and
   choose the film. Connect a compatible camera over USB data cable in a
   photo-transfer (PTP) mode that allows taking photos while connected.
2. Tap **Start USB Receive** and grant external camera access. Wait for the
   ready state before shooting on the camera. Earlier card contents are
   enumerated without import. New image files reported by the camera are
   fetched one at a time, copied unchanged into the app library, and the
   latest develops a preview. The camera/card copy is never deleted.
3. Keep Silverphase in the foreground. Stop closes discovery and the camera
   session; try the vendor handoff below if your camera exposes stored images
   but does not report new shots. USB behavior depends on the camera and
   firmware, its mode, cable and power. External preview, focus, and remote
   shutter are not included. The Apple iOS SDK does not expose the framework's
   desktop `requestTakePicture` or `requestEnableTethering` APIs.

## Wi-Fi: vendor transfer, then apply the same film

On a compatible camera use its vendor utility, for example [Sony Creators’
App](https://helpguide.sony.net/di-app/ca/v1/en/contents/CA_introduction.html)
or [Nikon SnapBridge](https://nikonimglib.com/snbr/onlinehelp/en/downloading_selected_pictures_11.html).
Select original file size/RAW if available and save or export to iOS Photos
or Files. In **Tethered Shooting**, choose those photos from Photos or Files.
They get the selected film and the newest is previewed. This is a two-app
handoff, not automatic background ingest or direct Wi-Fi pairing.

## 真机验收

- iPhone 和一台支持边拍边报新文件的 USB 相机：检查打开页面前的卡内照片不会导入；按快门后收到 JPEG / HEIF 及兼容 RAW。检查两次连拍、重连、权限拒绝、中途拔线、切后台和停止，不删卡内原片。
- 在支持的相机厂商应用内经 Wi‑Fi 传原片，再从「照片」或「文件」选入。检查套用胶片、预览、在编辑器打开和后续导出。厂商应用若只给缩小版，不应标为 RAW 原片。
- 以上是验收要求，不是现有机型兼容声明。无线直连、相机遥控、实时取景以及 macOS 均不在本 PR。
- Debug 可用 `--tethered-import-regression` 运行独立合成图检查；输出 `Documents/tethered-import-report.json`，验证原始字节、编辑配方和显影预览，不覆盖 USB 或无线实机协议。

[Apple ImageCaptureCore](https://developer.apple.com/documentation/imagecapturecore) ·
[Apple 的有线照片导入说明](https://support.apple.com/guide/iphone/iph480caa1f3/ios)
