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

## Wi-Fi: direct passive FTP · Sony ARW only

1. Connect the phone/tablet and camera to the same trusted Wi-Fi network with
   a private IPv4 address and without client isolation. In the Debug build,
   open **Tethered Shooting**, choose a film, tap **Start FTP Receive**, and
   allow Local Network access. Leave this screen open and unlocked.
2. Configure the camera to use plain **FTP**, passive mode, the on-screen IP
   address, port **2121**, username **silverphase**, and the current session
   password. Use the root directory and enable automatic original RAW transfer
   while shooting. The password changes each time the receiver is started.
   FTP is not encrypted. Do not use a public network or forward the port.
3. The receiver stages complete Sony **.ARW** originals (up to 256 MiB),
   checks declared RAW extents and ignores byte-identical retransmissions.
   It adds the original with its selected film and previews the latest photo.
   A camera's FTP success acknowledges the staged file, not a completed
   Silverphase preview. Failed imports remain in the inbox and are retried
   on the next FTP session; successfully imported files retain a duplicate
   receipt for seven days. USB and FTP receive cannot be active together.
4. Leaving this screen or putting Silverphase in the background stops the
   listener. It does not guarantee background transfer or locked-screen
   catch-up. SFTP, FTPS, camera hotspot modes, other RAW formats, remote
   shutter and live view are not included.

[Example camera setup: Sony α7R V FTP help](https://helpguide.sony.net/di/ftp_2230/v1/en/contents/image_transfer.html)

## Wi-Fi fallback: vendor transfer, then apply the same film

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
- 用支持自动 FTP 传输的 Sony 相机，在同一个可信 Wi-Fi 上使用被动 FTP 发送 ARW。检查系统首次授权、连拍、不完整传输不入库、重复传输、后台和主动停止、重启后的待处理原片；确认成片用的是收到时的胶片配方。此列表不是机型兼容声明。
- 本机协议验收：在 Mac 运行 `python3 ios/Silverphase/Tools/Tests/check-ftp-receiver.py`，监听仅限本机回环地址，以合成 TIFF 验证协议和原片字节存取，不代替 Sony ARW 实机显影。相机遥控、实时取景以及 macOS 联机均不在本 PR。
- Debug 可用 `--tethered-import-regression` 运行独立合成图检查；输出 `Documents/tethered-import-report.json`，验证原始字节、编辑配方和显影预览，不覆盖 USB 或无线实机协议。

[Apple ImageCaptureCore](https://developer.apple.com/documentation/imagecapturecore) ·
[Apple 的有线照片导入说明](https://support.apple.com/guide/iphone/iph480caa1f3/ios)
