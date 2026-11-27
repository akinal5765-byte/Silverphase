# Silverphase 项目维护规范 / Project maintenance

**简体中文** · [English](#english) · [文档写作规范](WRITING-GUIDE.md)

## 仓库分区

| 路径 | 保留什么 |
|---|---|
| `engine/` | 两端共享的引擎、必要的已烘焙资源、公有材料和来源记录。可再生成并不意味着可以删除已纳入构建的资源。 |
| `ios/Silverphase/`、`modern_UI/Spektrafilm/` | 原生宿主、项目生成脚本、公用测试和构建入口。修改项目文件时同时更新生成脚本并执行 `--check`。 |
| `docs/`、平台指南、根目录契约 | 当前用户文档、架构、接口和发布记录。事实只在归属页维护，其他页面链接。 |
| `docs/history/`、`ios/history/`、`rfc/`、`performance/`、旧版截图 | 有日期或版本的原始记录。保留引用和来源；过时内容作为历史，不在当前入口重复陈述。 |
| `license/`、随包通知 | 授权、署名、资源溯源和校验清单。公开图片要能追溯到许可范围，截图不自动授权原片。 |
| `build/`、`output/`、`DerivedData/`、本地素材目录 | 工作区产物或私人输入，不进入 Git。可再生成的缓存可以局部清理；发布归档、dSYM、原片和用户数据不能当缓存。 |

## 清理顺序

1. 在要维护的仓库或独立工作树确认分支和 `git status --short`；不要用清理动作覆盖别人的修改。
2. 先查文件的用途、引用、生成方式和发布状态。能明确再生成的调试缓存可清理；有素材、签名、发布或用户数据的路径单列确认。
3. 重复说明改为链接，旧材料留在档案。移动公开路径时要先核对 README、网站、源码注释、已有发布说明和外部链接。不能验证迁移影响时，保留路径并标明历史。
4. 每个提交只处理同一主题。文档清理不应偷偷混入行为、版本、签名或资源变化。发布以对应源码、签名和验证记录为准。
5. 提交前检查暂存文件和文档语言；涉及视觉资源时重查公开素材清单。只运行受改动影响的测试，并记录没有验证的部分。

```sh
git status --short
git diff --cached --name-status
git diff --check
python3 tools/check-doc-language-parity.py
python3 tools/inventory-release-media.py --check
```

不要对用户在用的仓库运行全量 `git clean -fdx`，也不要把 `*.xcarchive`、签名密钥、相机 RAW、私人 sidecar 或发行日志强制加入 Git。对可发布的产物保留可验证的来源，不用最大文件排行代替用途判断。

## English

[简体中文](#silverphase-项目维护规范--project-maintenance) · **English** · [Documentation guide](WRITING-GUIDE.md#english)

### Repository boundaries

| Path | Purpose |
|---|---|
| `engine/` | Shared engine, required baked resources, public materials, and provenance. A regenerable file may still be a required tracked build input. |
| `ios/Silverphase/`, `modern_UI/Spektrafilm/` | Native hosts, project generation, shared tests, and build entry points. Update the generator alongside generated project files and run its `--check`. |
| `docs/`, platform guides, root contracts | Current user instructions, architecture, interfaces, and distribution records. Each fact has one owner. |
| History, RFCs, measurements, and older screenshots | Dated evidence and rationale. Preserve references and provenance; distinguish archival accounts from current behavior. |
| `license/` and bundled notices | Attribution, terms, resource provenance, and checksums. Screenshot approval does not authorize raw-photo redistribution. |
| Build, output, DerivedData, and local input folders | Reproducible working output or private input, outside Git. Release archives, dSYMs, original photos, and user data are not disposable caches. |

### Cleanup checklist

1. Check the intended working tree, branch, and `git status --short`. Do not erase someone else's changes.
2. Establish purpose, references, reproducibility, and release status before removing anything. Separate signing, archives, source materials, and user data from disposable build output.
3. Link to the authoritative document instead of duplicating it. Keep archive material. Verify all inbound paths and anchors before moving public content; when unsure, keep the path and label the scope.
4. Keep commits focused. Documentation cleanup must not silently alter behavior, versions, signing, or build resources. Track releases against their matching source and validation evidence.
5. Review staged files and language parity. If images change, verify the media inventory. Test the affected surface and state what remains unverified.

Use the commands above. Do not run a blanket `git clean -fdx` in a working user checkout or force-add a release archive, signing key, camera RAW, private sidecar, or release log. A size ranking is not a deletion policy.
