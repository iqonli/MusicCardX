# mcx_background

单份C++17核心通过C ABI向Flutter提供四种背景。算法使用double，保留X的种子映射、五参数范围和660px网格。Dart入口位于应用lib/seed_backgrounds.dart，封面预处理位于lib/cover_preparation.dart。生产代码不导入归档Dart着色算法。

Android依赖NDK28.2.13676358、CMake3.22.1，作为本地ffi插件自动打包libmcx_background.so。

Windows/Linux可直接使用根CMakeLists.txt。Windows目标名固定为mcx_background.dll。MSVC采用/O2 /fp:strict，LLVM-MinGW/GCC采用-O3 -fno-fast-math -ffp-contract=off，MinGW静态链接C++运行库。已在Linux交叉编译Windows x64 DLL并验证导出，不验证Windows像素结果。

iOS/macOS使用对应目录的podspec，FFI通过进程查找链接符号。需要Xcode实际构建验证。

模块构建与完整Flutter应用的平台移植是两项工作；目前主应用仅含Android runner。

1.5.0内部版本35：仅流光切换为v4 V2丝带分支，其他背景仍保留原实现；详见应用docs/1.5.0-light-flow.md。
