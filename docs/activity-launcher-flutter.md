# ActivityLauncher在MusicCardX中的复现可行性

调研日期：2026-11-02
参考仓库：https://github.com/ActivityLauncher/ActivityLauncher
旧地址butzist/ActivityLauncher已经迁移至上述组织。
检查提交：0337690f804e469ef0a8f9aea5af70d16bced539

## 判断

可以用Flutter重做等价的界面和管理逻辑，Android功能通过平台通道调用。无法仅凭纯Dart跨平台代码完整替代Android系统API，也无法突破原项目本身受系统权限约束的启动边界。此版本仅实现手填Intent和标准文本入口选择，不提供应用或Activity枚举列表。

## 源码依据

- data/packages/SystemPackageRepositoryImpl.kt使用PackageManager.getInstalledPackages、getPackageInfo、GET_ACTIVITIES及禁用/Direct Boot组件标志获取列表。这部分需要Android适配层；异步查询、搜索、分组、收藏和显示均可由Dart实现。
- core/util/ActivityIntent.kt通过ComponentName和Bundle构造Intent，默认组合NEW_TASK与CLEAR_TASK。X不照搬CLEAR_TASK，避免普通AI调用意外清空目标任务。
- AndroidManifest.xml声明QUERY_ALL_PACKAGES、快捷方式和插件签名权限。应用可见性只影响查询，不能代替组件启动权限。
- PLUGIN_ARCHITECTURE.md以Intent URI交换启动配置，默认调用context.startActivity，也支持外部启动和快捷方式插件。
- Shizuku能力由独立ActivityLauncherShizukuPlugin提供。若未来支持，应另做显式授权与原生适配；并非打开应用列表权限后就有Shizuku权限。

## 复现范围

| 功能 | Flutter/Dart部分 | Android部分 |
| --- | --- | --- |
| 应用和Activity列表 | 搜索、排序、分组、缓存和界面 | PackageManager、图标和元数据读取 |
| Intent编辑 | 表单、类型校验、配置保存与导入导出 | Intent、Bundle、Uri编码和实际启动 |
| 快捷方式 | 编辑名称、图标和目标 | ShortcutManager、固定快捷方式回调 |
| 插件 | 配置与状态展示 | 外部Activity协议、签名验证 |
| Shizuku/root启动 | 授权状态与用户交互 | Shizuku Binder或root通道 |
| 系统限制 | 解释失败原因 | exported、权限、禁用状态、厂商限制 |

核心功能没有必须换其他项目的理由。ActivityLauncher覆盖面与本需求较匹配；更重的应用管理器会引入本版不需要的包管理功能。本调研没有完成全部同类项目的横向性能测试，因此不将它称为唯一或性能最优方案。

## 许可证

当前主仓库LICENSE为ISC，版权行为Copyright (c) 2015-2019, Adam M. Szalkowski。若复制代码，保留其版权和许可正文。Shizuku插件单独遵循其自身许可证，不能用主仓库许可证代替。本版调用功能独立编写，未复制ActivityLauncher源码，因此不把调研参考误列为已引入依赖。

## 权限与验证边界

PROCESS_TEXT入口可按Intent查询，不必扫描全部Activity。QUERY_ALL_PACKAGES属于Manifest声明，通常没有运行时授权弹窗；MIUI等厂商可能另设应用列表开关，公开API不能在所有设备上准确读取。普通前台启动不需要无障碍、悬浮窗、自启动、后台弹出界面权限。本版不为了隐藏“获取权限”按钮而诱导用户打开这些无关权限。

仍需真机验证ChatGPT、DeepSeek的入口名称、文本接收行为和MIUI权限开关；源码编译和单元测试不能替代这些验证。
