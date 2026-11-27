# 许可与署名

[English](LICENSES.md) · **简体中文**

Silverphase 是 **Hanze Qiu** 的 [SpektraLab](https://github.com/JamesQiu2005/SpektraLab) 的独立衍生项目，以 **Andrea Volpato** 的 [spektrafilm](https://github.com/andreavolpato/spektrafilm) 为基础。Silverphase 的改动由 **akinal5765-byte** 维护。请保留原有版权声明和 Git 历史。上游作者与项目均未为 Silverphase 背书。

本文梳理仓库所适用的现有条款，不替代任何许可证，也不对仓库内的所有图片作一揽子授权。

| 材料 | 条款与依据 |
|---|---|
| 应用代码、共用的 C++/Metal 引擎、开发工具和 Silverphase 的代码改动 | GPL-3.0-or-later。全文见 [COPYING](COPYING)，与 [license/LICENSE](license/LICENSE) 相同。请保留各文件中的声明。 |
| Andrea Volpato 的原始胶片与相纸配置及其直接衍生物，包括预先生成的印相预览 LUT | CC BY-SA 4.0。上游前言原样保存在 [license/SPEKTRAFILM_LICENSE.txt](license/SPEKTRAFILM_LICENSE.txt)。署名与改动见[随应用分发的变更记录](modern_UI/Spektrafilm/Spektrafilm/Resources/Licenses/Profiles-and-LUTs-CHANGELOG.txt)。 |
| 经 Negs 改编的 Fotufilm 实验胶片配置与相关数据 | CC BY-SA 4.0。见[随应用分发的 Fotufilm 声明](engine/resources_product/FOTUFILM_LICENSE.txt)和[数据来源](license/DATA-SOURCES.md#experimental-fotufilm-profiles)。 |
| Hanze Qiu 独立构建的产品黑白配置与反差等级、滤色数据包 | 本项目采用的上游版本在 [README 许可表](https://github.com/JamesQiu2005/SpektraLab/blob/01d32a2b767fbdb447bbc3ab156dfa1f2388580c/README.md#credits-and-licence)中将胶片与相纸配置列为 CC BY-SA 4.0。请原样保留 Hanze Qiu 的 [NOTICE](engine/resources_product/NOTICE.md)及 [UPSTREAM.json](engine/resources_product/UPSTREAM.json) 中的准确提交和哈希。这些配置独立创作，并非 Andrea Volpato 的实测数组。拟合得到的等级与滤色数据包随配置按相同上游 CC BY-SA 条款分发，且保留衍生记录。 |
| 随项目引入的 Apple metal-cpp | Apache-2.0；全文及版权声明见 [engine/third_party/metal-cpp](engine/third_party/metal-cpp/LICENSE.txt)。 |
| 衍生自 Colour 的色彩科学数据 | BSD-3-Clause 声明保存在 [license/Colour-BSD-3-Clause.txt](license/Colour-BSD-3-Clause.txt)及两个应用程序包内。部分历史生成输入尚未确证，见[数据来源](license/DATA-SOURCES.md)和[数组清单](license/data-inventory.json)。 |
| Silverphase 有权处分的 AI 封面图和新创作的图标 | 在贡献者拥有版权的范围内采用 CC BY-SA 4.0。署名、确切范围和第三方排除项见[图像素材声明](license/ARTWORK.md)；法律全文见 [CC BY-SA 4.0](license/CC-BY-SA-4.0.txt)。 |
| 继承的其他引擎数据，包括 Hanatos 光谱和滤镜曲线 | 遵循 spektrafilm 仓库公开的 GPL 条款，保留上游署名。[数据来源](license/DATA-SOURCES.md)记录精确输入对照和尚缺的独立贡献者声明；本文不主张任何新的单独授权。 |
| Layerlight 推广图标 | 独立专有应用的素材，应所有者请求在 README 与 iOS 的设置／关于页面用于识别和推广。不在 Silverphase 的 GPL 与 CC BY-SA 授权范围内，见[关联应用素材](screenshots/related-apps/README.md)。 |
| 摄影作品、继承的截图与第三方设计 | 无新增的一揽子授权。历史界面截图是从上游继承的参考素材，并非当前产品截图。见[发布审查](docs/OPEN-SOURCE-RELEASE.md)。 |

维护者于 2026-10-31 确认，胶片封面由 AI 根据提示词生成，并要求保留包装风格的图像。现有生成记录存放在 `modern_UI/design/film-artwork/`。该来源说明不授予第三方包装的相关权利。

配置名称用于识别材料；品牌名称和徽标归各权利人所有。本文不表示已取得商标授权，也不表示制造商背书。复现零售包装的生成图像仍须单独审查权利。

## 源代码与二进制分发

**本应用**的源码仓库是 [akinal5765-byte/Silverphase](https://github.com/akinal5765-byte/Silverphase)，不是任一上游仓库。以 GPL 第 6 条允许的方式，对应到二进制的准确修订版本分发源代码，包括修改及构建脚本。仅提供通用仓库网址，不构成书面要约，也不能证明特定二进制的完整对应源码已提供。

通过 `modern_UI/Spektrafilm/Tools/bundle-licenses.sh` 重新生成随应用分发的声明。两个平台的应用都会打包该目录。请保持「关于」中的署名可见，保留许可证全文，并在数据旁记录配置与 LUT 的修改。不要为了写入本地修改而改动上游许可证或 NOTICE。

以 [GNU GPL 全文](https://www.gnu.org/licenses/gpl-3.0.html)及 [CC BY-SA 法律文本](https://creativecommons.org/licenses/by-sa/4.0/legalcode.en)为准。有关来源的限制见发布审查。Silverphase 对继承的数据遵循上游分发条款并保留声明；本文不设立额外的许可流程。
