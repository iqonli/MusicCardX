# Linux构建环境恢复记录

2026-10-31验证可用：Flutter官方Git仓库stable分支（c197ca5199，Flutter3.47.9，Dart3.13.7）、Zulu21.0.9 JDK、Android SDK36 / build-tools36.0.0 / NDK28.2.13676358。使用CI=true和FLUTTER_SUPPRESS_ANALYTICS=true。

官方Flutter归档3.47.9地址及发行清单曾返回404，flutter-io镜像返回403，不重复这些失败路线。通过git clone --depth 1 --branch stable https://github.com/flutter/flutter.git恢复工具后运行flutter precache --android成功。它会先准备工具依赖，再下载引擎，其他Flutter命令等待启动锁属于正常现象。

JDK可用下载：https://cdn.azul.com/zulu/bin/zulu21.46.19-ca-jdk21.0.9-linux_x64.tar.gz

Android命令行工具：https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip

sdkmanager和Gradle需要显式配置当前HTTPS_PROXY中的主机、端口及/etc/ssl/certs/java/cacerts。不要打印代理认证信息。系统预装Java只有JRE，应使用完整JDK。Gradle在初始化脚本中将repo.maven.apache.org映射到https://maven-central.storage-download.googleapis.com/maven2，Google仓库保持原样。冷构建会下载Gradle及插件，通常数分钟。

仅运行一个构建进程，顺序构建android-arm64和android-x64，使用flutter build apk --release --split-per-abi --target-platform。每个架构结束后立即复制对应APK，避免后一次清理覆盖前一次输出。原iqonli-1私钥和密码使用单独的备份，源码包不包含。所有发行包核验SHA-256证书指纹4c281c59b8e1e8a9fb5b16020540128dcca608329255609ce9881fd9b75d12e1。

1.4.1原版构建号15；同版本原图保存修订构建号16。版本名均1.4.1。修订版验证98项测试，未做真机测试。
