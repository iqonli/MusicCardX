# 配置覆盖清单（1.4.2）

当前配置导出和本地配置库均保存完整文档设置。读取时使用CardDocument.fromJson和normalizeConfiguration统一校验。应用状态自动保存同样包含这些设置。

| 设置区域 | JSON字段/结构 | 恢复行为 |
|---|---|---|
| 输出 | exportScale、imageFormat、jpegQuality | 保留倍率、生成卡片的PNG/JPG和质量；封面保存不使用这些压缩参数 |
| 保存 | imageFolder、imageFilename | 明确提供时恢复；旧配置缺少目录时保留当前目录 |
| 显示 | previewPinned、monet、displayFontName、textAlignMode | 切换时同步实际图钉、配色和字体状态 |
| 背景 | backgroundStyle、blurStrength、solidHex、blurBackgroundCropPosition、seed | 保留背景模式、取样位置及种子 |
| 封面 | coverShape、coverShapeParameters、coverCornerRadius、coverExponent、irregularCoverMode、coverShadowOpacity、coverShadowDepth | 保留各类型圆角参数及阴影 |
| 颜色 | customEnvironmentColorsEnabled、customEnvironmentColors、paletteAlgorithm、autoColorMode、textAutoColorThreshold、rainbowMode、rainbowCustomHex、rainbowCustomSelection、rainbowSampleMaxSide | 保留算法、自定义五色、彩虹模式、自动黑白模式 |
| 文字 | style中的八个元素、textOpenCCMode | 每个元素的内容表达式、字体、字重、字号、斜体、颜色、间距、透明和模糊参数 |
| 歌词 | lyrics、lyricsOpenCCMode | 歌词内容、容器、排版、字重、间距、分隔线和渐变参数 |
| 在线封面 | coverSearchMinScore、coverSearchPreviewSize、coverSearchDownloadSize、coverSearch_163、coverSearch_apple、coverSearch_appleweb、coverSearchRegion | 预览尺寸150、下载尺寸1000为默认；0为最大，支持0—10000 |
| 在线歌曲信息 | songSearch_163、songSearch_apple、songSearch_appleweb、songSearch_qq、songSearchRegion | 搜索源独立保存；Apple地区CN／US，导入校验并转为小写 |
| 字体管理偏好 | fontPreferences.mode、tree、sample、previewSize | 导出时读取真实管理器设置，应用时恢复并刷新共享库 |

## 不嵌入配置的资源和临时状态

- 本地字体文件、已导入字体索引及共享库本身仍由字体管理器维护，不随JSON复制。系统目录授权也不能靠JSON跨设备转移。
- coverPath是当前封面本地路径，不是内嵌图片。完整JSON可保存和读取该路径，跨设备应重新选择封面。
- 本地配置库选择时沿用当前歌曲信息和封面；这是保留正在编辑内容的原有行为。其他设置按配置应用。
- 在线搜索的临时查询文字、候选、下载进度、当前缩放位置不作为设置导出。搜索框初次打开取当前歌曲信息。
- 字体预览页临时试选字重不持久化；已配置的卡片文字、歌词字重按style/lyrics保存。

## 校验与兼容

未知字段、无效颜色、错误类型、非有限数、错误枚举会被移除；恢复缺失默认值。在线尺寸取整数并限制0—10000，Apple地区规范为两位小写字母。fontPreferences对来源模式和字号校验。各圆角类型独立参数通过专门结构读取，不会被空Map模板丢弃。歌曲信息继续使用已有的严格标准化规则。

97项测试中的配置测试覆盖完整默认结构往返、代表设置修改后往返、旧配置缺省、错误类型/范围/枚举、动态圆角参数、字体偏好采集与恢复及图钉状态。测试日志以validation/1.4.0中最终结果为准。
