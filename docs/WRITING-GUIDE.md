# Silverphase 文档规范 / Documentation guide

**简体中文** · [English](#english)

## 1. 先确定读者与事实归属

- **README** 帮读者认识产品、选平台、下载和找到下一页。不要把设备排查日志或完整变更列表堆进去。
- **支持／平台指南** 说明当前操作，按「前提 → 步骤 → 结果 → 排查」组织。先写用户能做什么，再写限制。
- **架构、API、契约** 分别维护模块职责、调用约定和不可破坏的约束。各有一处权威来源；其他页面引用，不复制一份近似版本。
- **发版记录** 依次写「版本／平台／构建和渠道 → 用户可见改动 → 验证和限制」。正式发布、App Store 提审、TestFlight 可测和源码提交是不同状态；只写可核对的状态与日期。两端独立发版，不混用构建号。
- **历史、RFC、实测记录、原始许可和上游说明** 保留原文和原日期。历史材料不能当当前功能或验收证据，也不整批重译。若需要解释，写有指向原件的短说明。

## 2. 中英文怎么维护

| 文档 | 规则 |
|---|---|
| 主页、下载、安装、支持、安全与隐私、现行平台指南、版本说明 | 同一次改动更新两种语言。 |
| 架构、API、宿主契约、其他技术长文 | 有译文就加双向入口；原文仍是技术事实来源。新改动同时更新译文；若只提供导读，要明确标注并链接原文。 |
| 历史、上游和原始许可证 | 不强制翻译。保留原始措辞；说明性译文不改变权利或技术要求。 |

短文可同页分中英文两节；长文使用对向文件链接，例如 `README.md` / `README.en.md` 或 `README.md` / `README.zh-CN.md`，不要只凭文件名猜原文语言。保留已被外部引用的路径和标题锚点。中英文采用相同的章节顺序、表头语义、范围、数字、命令、链接目的和截图说明。本地化按母语表达，不逐句翻；胶片名、API 字段、型号和命令保持原样。

## 3. 写法与提交前检查

- 先写结论，用明确的动作和菜单名称。一段只讲一件事。避免空泛词，例如「全面提升」「完美支持」，也别把技术列表当用户收益。
- 验证分开写：**构建通过／模拟器通过／真机已验证／待验证**。涉及速度、内存或画质时注明设备、素材和条件，不把一次样例当通用保证。
- 截图注明版本、设备／模拟器和素材来源。读者能看清真实 UI 即可，不伪装成真机，不提交私人原片。
- 开发者和 AI 在修改前先查文档索引和权威来源；同一处改动只写一次事实。提交前检查两语入口、版本表、命令、链接与锚点，不将无关排版改动混进功能提交。

```sh
git diff --check
python3 tools/check-doc-language-parity.py
```

## English

[简体中文](#silverphase-文档规范--documentation-guide) · **English**

### 1. Start with the reader and the authoritative source

- **README** explains the product, platform choices, downloads, and where to go next. Keep device logs and exhaustive change lists elsewhere.
- **Support and platform guides** describe the current workflow: prerequisites, steps, result, and troubleshooting. Lead with what readers can do, then give limits.
- **Architecture, API, and contract** own module boundaries, calls, and invariants respectively. Link to the one authoritative explanation instead of maintaining near-duplicates.
- **Release notes** follow version/platform/build/channel, user-visible changes, then verification and limits. Source commits, store review, TestFlight availability, and public release are distinct. Record only the verified state and date. Keep Mac and mobile build numbers separate.
- **History, RFCs, measurements, original licences, and upstream notices** retain their original language and date. They do not prove current behavior or acceptance. Link to originals from explanatory notes rather than rewriting the archive.

### 2. Maintain the two languages

| Documents | Rule |
|---|---|
| Home, downloads, installation, support, privacy and safety, current platform guides, release notes | Update both languages in the same change. |
| Architecture, API, host contracts, and longer technical references | Link both editions when available. The original remains authoritative; update its companion when facts change. Label summaries and link to the full source. |
| Archives, upstream text, and original licences | Translation is optional. Preserve the original wording; commentary does not grant rights or change technical requirements. |

Short pages can include both languages; longer pages use reciprocal links, such as `README.md` / `README.en.md` or `README.md` / `README.zh-CN.md`. The base filename does not imply a language. Preserve public paths and anchors. Match section order, table meaning, scope, numbers, commands, link destinations, and screenshot captions. Write idiomatic copy without translating stock names, model numbers, API fields, or commands.

### 3. Before committing

- Lead with the conclusion, concrete actions, and menu names. Keep one idea per paragraph. Avoid vague promises or presenting a list of implementation details as a user benefit.
- Distinguish **built, checked in simulator, verified on hardware, and not yet verified**. For speed, memory, or image quality, specify the device, inputs, and conditions.
- Record screenshot versions, devices or simulators, and photo provenance. Do not misrepresent test captures as real hardware or commit private originals.
- Humans and AI should locate the authoritative document first. Maintain each fact once. Check links, anchors, commands, language navigation, and version-table parity. Keep unrelated formatting out of feature commits.

```sh
git diff --check
python3 tools/check-doc-language-parity.py
```
