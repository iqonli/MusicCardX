# MusicCardX1.4.3发布准备

版本名1.4.3。当前正式安装包为已验证的1.4.3+19，ARM64与x86_64沿用iqonli-1签名。

本次整理源码中的版权与README：
- 根目录LICENSE为项目主许可证唯一维护位置，通过pubspec.yaml作为应用资源注册。
- 删除PhotoView和audio_metadata_reader在assets中的重复许可证及手工注册，保留各包原始LICENSE，由Flutter自动汇总。
- ezCD与AutoCoverDownTool属于工作室内部参考，MIT正文合并为IQ-Online-Studio-MIT.txt，署名及引用来源统一列在NOTICE，不改变外部作者声明。
- reference移入工程根目录，删去重复许可证，参考来源保持可追踪。
- README保留MusicCard全部原说明、原作者语气和历史Bug记录，同时增加X的功能、入口、平台差异和编译说明。原版截图明确链接到原版，不冒充X截图。

验证：本次检查资源路径、许可证引用、README全文保留和源码包文件列表。由于当前构建环境已被工作区维护清理，本次版权资源注册修改未重新编译或运行Flutter测试；已有APK不随本次文档整理重建，仍包含上一版完整许可证。此前108项测试与签名核验仅对应原1.4.3+19，不作为当前整理后源码的新测试结果。

发布状态：GitHub仓库公开可读且为空；GitHub连接器方法不可用，gh未登录，浏览器因环境只读目录无法启动，尚未上传提交或创建Release。待恢复GitHub写入授权后执行发布包中的publish.sh，不重复索取签名私钥。
