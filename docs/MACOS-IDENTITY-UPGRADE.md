# Keep your edits when switching to the new macOS identity

[简体中文](#macos-新版如何保留旧编辑)

The macOS 1.4.0 release uses the identifier `com.silverphase.editor`. Published
1.3.1 (build 6) and earlier builds using `com.hanze.filmify` are unchanged.
iPhone and iPad already use `com.silverphase.editor`, as do their camera
extensions under separate suffixes. Their Store identity and data are unchanged.
See [iOS distribution](../ios/APP-STORE.md#distribution-maintenance) for the
release identity check. Silverphase for Mac has no installed command or MCP server.

The older desktop build used a data folder that SpektraLab can also use. The
new build does not automatically adopt the contents, change the old folder, or
copy preferences from the shared identifier.

1. Before replacing the old app, back up `~/Library/Application Support/SpektraLab`.
   To find a particular photo's edit in the old app, open the photo and choose
   **Frame → Reveal Settings in Finder**. Quit both apps before copying.
2. In Finder use **Go → Go to Folder** (⇧⌘G) to open
   `~/Library/Application Support/`. In **Silverphase**, create the **Sidecars**
   folder if needed. Copy only the edit files you recognize from
   **SpektraLab/Sidecars** to **Silverphase/Sidecars**. Ratings and flags use
   the same file names under the **Sidecars/LibraryMarks** subfolder; copy
   those to the matching subfolder. Keep file names and leave the source
   files in place. If Finder asks to
   replace an existing file, skip it. Do not copy the whole old folder if you
   use both apps. Reopen the same source photo to check the edit.
3. If you recognize `export-recipes.json` as your previous Silverphase recipes,
   copy it from **SpektraLab** to **Silverphase** *before* opening Export in the
   new version. If a file is already there, don't replace it unless it only
   contains the new default recipes. Keep a separate backup of that file
   before replacing it. Open Export and select your preferred recipe.

Portable `.spektra.json` files beside a photo are still accepted. They are
copied into Silverphase on open, not moved or overwritten, and reset changes
only Silverphase's copy. You don't need to move the original photos or
`.spektrapair` files. UI preferences and update reminders start fresh. Old
logs and render caches are left alone; the new build creates its own. macOS
may ask again for permission to access Desktop, Documents or Downloads.
If Finder or Lightroom Classic opens the old app, re-select the new
Silverphase.app in **Open With** or Lightroom's external editor settings.

## macOS 新版如何保留旧编辑

macOS 1.4.0 使用独立的标识符 `com.silverphase.editor`。已发布的
1.3.1（构建 6）及仍用旧标识符 `com.hanze.filmify` 的版本不会因此改变。
iPhone 和 iPad 的商店版已经使用 `com.silverphase.editor`，相机扩展使用同一前缀。
这次不会变更移动端标识或迁移数据，见 [iOS 发布检查](../ios/APP-STORE.md#distribution-maintenance)。Silverphase
桌面版没有安装独立命令行工具或 MCP 服务。

旧版桌面数据目录可能与 SpektraLab 共用。新版不会自动接管该目录，
不会修改旧目录，也不会复制共用标识符下的偏好设置。

1. 替换旧应用前，备份 `~/Library/Application Support/SpektraLab`。
   若要找出某张照片的编辑记录，可在旧版打开该照片，选择「图像 →
   在访达中显示设置文件」。复制前先退出两个应用。
2. 在 Finder 按 ⇧⌘G 打开 `~/Library/Application Support/`。如尚无
   **Silverphase/Sidecars**，先创建这两级文件夹。只把能确认属于自己旧版
   Silverphase 的编辑记录，从 **SpektraLab/Sidecars** 复制到
   **Silverphase/Sidecars**。评分和标记记录同名，存放在
   **Sidecars/LibraryMarks** 子目录中，请复制到新目录的同一位置。
   保留文件名和原文件；遇到同名文件就跳过。
   同时使用两个应用时，不要直接复制整个旧文件夹。重新打开原照片确认效果。
3. 如果确认旧目录中的 `export-recipes.json` 是自己的旧版 Silverphase
   导出配方，请在新版打开「导出」前，把文件从 **SpektraLab** 复制到
   **Silverphase**。如果目标已有同名文件，不要直接覆盖；仅在确认它只有新版
   的默认配方时，可另行备份后替换。打开「导出」，重新选中常用的配方。

照片旁边的旧 `.spektra.json` 文件仍可读取。新版会把记录复制到自己的目录，
不会移走或覆盖原文件；重置也只影响自己的副本。原始照片与
`.spektrapair` 无需移动。界面偏好和更新提醒会重新开始，旧日志与缓存不会
被动到。macOS 可能再次询问桌面、文稿或下载目录访问权限。若 Finder 或
Lightroom Classic 仍打开旧版，在「打开方式」或 Lightroom 的外部编辑器
设置中重新指定新版 Silverphase.app。

## Desktop release gate for maintainers

Before publishing this identity change, test a release candidate on an Apple
Silicon Mac with a separate local user or test volume:

- Confirm the candidate's built `CFBundleIdentifier` and code-signing
  identifier are `com.silverphase.editor`, and that the existing
  `com.silverphase.half-frame-pair` document type still opens from Finder.
- Upgrade from the actual 1.3.1 DMG with a saved edit, a half-frame pair, a
  rating and a custom recipe. The candidate should start with separate
  preferences and must not alter any old files. Copy the known files using
  the steps above; verify editing, reopening and TIFF export.
- With SpektraLab still installed in a separate application bundle, open the
  same photo in both apps and confirm neither app sees the other's new
  settings. Test an older portable sidecar and the Silverphase reset action.
- Verify the log directory, retention and caches use Silverphase's namespace;
  check Finder permissions and Lightroom Classic writeback again. Run the
  normal Release packaging, signing, Gatekeeper and update-check verification.
  The in-app updater should still point only at Silverphase's macOS releases.


## 维护者发版检查

在独立的本机用户或测试卷中，用 Apple Silicon Mac 验证发布候选版：

- 核对归档的 `CFBundleIdentifier` 和签名标识均为 `com.silverphase.editor`；Finder 仍可打开原有 `com.silverphase.half-frame-pair` 文件。
- 用真正的 1.3.1 DMG 建立含编辑、半格双联画、评分及自定义配方的图库，再升级。新版偏好应独立，不能改动任何旧文件。按上文复制已知文件，再验证编辑、重开和 TIFF 导出。
- 两款 App 并行安装时，在两边打开同一张照片，确认各自看不到另一款的新设置。另测旧的便携 sidecar 和 Silverphase 重置。
- 核对日志路径、保留策略及缓存使用 Silverphase 自己的命名空间。重试 Finder 权限和 Lightroom 写回；完成 Release 打包、签名、Gatekeeper 和更新检查，确保应用内更新只指向 Silverphase 的 macOS 发布。
