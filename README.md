# UURemoteClone — 4.48.1 安装包研究与复刻工程

同一个私有仓库维护 macOS、Windows、Android。当前是**研究中的实现，尚未达到三端功能与 UI 和原版完全一致**。不能用 Actions 编译成功替代互操作、采集、编解码或 UI 的验收。

原始样本：macOS 4.48.1 build 633、Windows 4.48.1.5606、Android 4.48.1 versionCode 448001。原包已提取并进行静态分析；二进制和配置身份保存在 [native/official/manifest.json](native/official/manifest.json)。应用不提供云设备入口；完整协议 schema 和原版通用媒体库仍保留历史云设备字段/代码，尚未完成库内部的剥离。

## 已有可核对的交付

- [proto/gv_pb/](proto/gv_pb/)：Windows 内嵌 descriptor 恢复的 14 个 proto、178 个顶层消息及 1 个嵌套消息。C++ 和 Swift 字段表从同一份恢复记录生成，现均覆盖 179 条。
- [native/official/](native/official/)：从给定安装包保留的原版桌面 streamer 库、各端独立配置、共享 C ABI 检查层。该层目前只开放经过核对的工厂和版本查询，**不是完整媒体会话实现**。
- [Android JNI glue](platforms/android/app/src/main/java/com/remote/streamer/)：恢复的实例 native 方法、配置 getter、回调分发、Surface / MediaProjection / VirtualDisplay 辅助类；静态契约由原 APK 的 DEX 原型对照检查。
- 三端应用已有独立 UI 和实验性媒体/控制代码。登录、真实房间、官方媒体核心接入、音频、文件/终端业务、UI 对齐等尚未全链路完成。详见 [本轮验收表](docs/10-continuation-audit.md)。

## 构建与下载

**本地不编译应用；构建只在 GitHub Actions 执行。** 推送或在 [Actions](https://github.com/materjojo/uuremote-clone/actions/workflows/build.yml) 手动运行 `build` 后，下载相应运行的 artifacts：

| 产物 | 内容 |
|---|---|
| UURemoteClone-macos | 保留执行权限的 `.app` ZIP，含原版 dylib 与配置 |
| UURemoteClone-windows-x64 | 自包含 WPF 应用 ZIP，含 `gvpb.dll`、原版 `streamer.dll` 与配置 |
| UURemoteClone-android-arm64-debug | ARM64 调试 APK，含原版三个 `.so`、配置与共享协议核心 |
| Native-ABI-* | 对安装包内真实媒体库执行工厂/版本查询的结果及 SHA-256 |

macOS 包为当前 runner 的架构，未声明 universal 或 notarized；Android 为调试签名，Windows 尚未做安装器/发行签名。上述产物不能视作已通过端到端验收的正式版本。

## 验证范围

Actions 执行共享 C++ Release 测试（断言明确启用）、桌面真实库的 C ABI 冒烟测试、Swift / C# 调用检查、Android 编译后 JNI 原型比较和 APK 内原版文件哈希比较。Android 真机 native 执行、官方服务会话、三端互控、硬编硬解路径以及逐页面/逐像素 UI 尚未完成验证。

本轮 [Actions 44643846778](https://github.com/materjojo/uuremote-clone/actions/runs/44643846778) 的全部 6 个任务因账号付款/支出上限，在 runner 启动前被拒绝；没有产生编译、测试结果或新应用产物。需恢复账号的 Actions 额度/付款后重跑，不能据此判断代码已编译通过。

本地允许进行只读分析、源码/生成文件检查；`scripts/verify_official_runtime.py` 不带 `--bridge` 时仅核对保留文件身份，不编译或执行原版库。`scripts/gen_protocol_schema.py --check` 仅检查生成的源码。

## 逆向记录

- [架构](docs/01-architecture.md)、[早期协议分析](docs/02-protocol.md)、[媒体](docs/03-media.md)、[UI 线索](docs/04-ui.md)
- [当前验收清单](docs/10-continuation-audit.md)、[已核对的 native 契约与更正](docs/11-native-contract.md)
- [REA Evidence](analysis/official/)、[Android 恢复来源与改动清单](analysis/official/android/recovery-manifest.json)

早期文档中的“与原版一致”“全部实现”等结论若与当前验收清单冲突，以带证据和覆盖边界的后者为准。尤其不能把自写 H.265 DataChannel、KCP/FEC 默认参数或占位页面算作原版实现。
