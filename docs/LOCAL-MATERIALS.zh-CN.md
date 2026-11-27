# 仅限本机的实验素材

**简体中文** · [English](LOCAL-MATERIALS.md)

维护者在自己的检出目录中进行常规构建时，会从忽略的 `private-fixtures/local-experimental-materials/` 归档暂存素材。归档目录选用十二款私有胶片；已被替换的 Tri-X、HP5 和相纸别名仍指向现有产品素材。配置、滤镜条目和封面只复制到生成的引擎资源及 `LocalMaterials/` 中，不改变公开目录与基础／产品数据。macOS 和 iOS 构建均走这条路径。

「实验」分类包含经 Negs 移植的公开 Fotufilm 系列；在维护者开启本地覆盖的构建中，也会列出私有胶片。暂存开关只控制私有覆盖，不影响公开系列。

只检出公开源码而没有本地归档时，普通构建会包含仓库已跟踪的目录。从维护者的检出目录打包分发时，请在准备资源和执行 Xcode 构建两个阶段明确禁用私有覆盖：

```sh
export SILVERPHASE_LOCAL_MATERIALS=0
engine/build.sh bundle
# Run the platform's normal xcodebuild command in this same environment.
```

关闭时，暂存工具会清理先前生成的本地配置、目录和封面，即使复用同一构建目录也是如此。此后如要进行个人构建，可取消该环境变量，或设回 `1`。切勿强制加入私有素材、生成的 `LocalMaterials/`、私人照片或个人编辑记录。发布源码归档不包含被忽略的本地素材归档。
