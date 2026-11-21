# UURemoteClone — 4.48.1 安装包研究与复刻工程

同一个公开仓库维护 macOS、Windows、Android。当前是**研究中的实现，尚未达到三端功能与 UI 和原版完全一致**。不能用 Actions 编译成功替代互操作、采集、编解码或 UI 的验收。

原始样本：macOS 4.48.1 build 633、Windows 4.48.1.5606、Android 4.48.1 versionCode 448001。原包已提取并进行静态分析；二进制和配置身份保存在 [native/official/manifest.json](native/official/manifest.json)。应用不提供云设备入口；完整协议 schema 和原版通用媒体库仍保留历史云设备字段/代码，尚未完成库内部的剥离。

## 已有可核对的交付

- [proto/gv_pb/](proto/gv_pb/)：Windows 内嵌 descriptor 恢复的 14 个 proto、178 个顶层消息及 1 个嵌套消息。C++ 和 Swift 字段表从同一份恢复记录生成，现均覆盖 179 条。
- [native/official/](native/official/)：从给定安装包保留的原版桌面 streamer 库、各端独立配置、共享 C ABI 检查层。共享层开放经过核对的工厂和版本查询；Windows 独立 [引擎绑定](platforms/windows/OfficialWindowsEngine.cs) 已在 runner 通过 Initialize/Finalize、进程所有权、重复能力查询与直接 DLL 字节对照；新增房间绑定和排队回调已通过独立 room_info 测试，**仍不是完整媒体会话实现**。
- [Android JNI glue](platforms/android/app/src/main/java/com/remote/streamer/)：恢复的实例 native 方法、配置 getter、回调分发、Surface / MediaProjection / VirtualDisplay 辅助类；编译后的 237 个方法 descriptor、24 个常量已通过原 APK 对照。[官方控制端会话封装](platforms/android/app/src/main/java/com/example/uuremote/official/OfficialControllerSession.java) 增加引擎单一所有者、房间/轨道生命周期、原始字节转发和故障清理；JVM 测试使用替身后端，尚未接入普通应用流程，也未证明原版 Android native 会话运行成功。
- 三端普通应用支持自建服务配对、每次同意、屏幕共享和控制；设备列表从空状态开始。独立 WebRTC 的真实 ICE/DTLS、双向 SCTP 和合成 RTP 视频已在各端 runner/模拟器测试。普通流程不要求网易业务服务器，但原版媒体核心、音频、文件/终端业务和 UI 对齐仍未完成。独立服务部署、配对和连接次序见 [使用说明](docs/13-independent-peers.md)，证据边界见 [验收表](docs/10-continuation-audit.md)。

## 构建与下载

**本地不编译应用；构建只在 GitHub Actions 执行。** 推送或在 [Actions](https://github.com/materjojo/uuremote-clone/actions/workflows/build.yml) 手动运行 `build` 后，下载相应运行的 artifacts：

| 产物 | 内容 |
|---|---|
| UURemoteClone-macos | 保留执行权限的 `.app` ZIP，含原版 dylib 与配置 |
| UURemoteClone-windows-x64 | 自包含 WPF 应用 ZIP，含 `gvpb.dll`、原版 `streamer.dll`、`StreamerCodecDetector.exe` 与配置 |
| UURemoteClone-android-arm64-debug | ARM64 调试 APK，含原版三个 `.so`、配置与共享协议核心 |
| Native-ABI-* | 对安装包内真实媒体库执行工厂/版本查询的结果及 SHA-256；Windows 另含原版 detector、隔离 Initialize/Finalize/capability 及显式测试 CA 插桩的 loopback room transport 报告 |

本轮已通过的下载与验证：

| 平台 | 已构建提交 | 下载 |
|---|---|---|
| macOS ARM64 | `eacc0e8` | [应用 ZIP](https://github.com/materjojo/uuremote-clone/actions/runs/44670463306/artifacts/14600510228) |
| Windows x64 | `58bdfee` | [应用 ZIP](https://github.com/materjojo/uuremote-clone/actions/runs/44897758496/artifacts/14704038742) |
| Android ARM64 | `eacc0e8` | [调试 APK](https://github.com/materjojo/uuremote-clone/actions/runs/44670463306/artifacts/14600320303) |

产物保留 7 天，过期后手动选择对应平台重建。macOS 包为当前 runner 的架构，未声明 universal 或 notarized；Android 为调试签名，Windows 尚未做安装器/发行签名。上述产物不能视作已通过端到端验收的正式版本。

## 验证范围

已在 Actions 通过共享 C++ Release 测试（断言明确启用）、桌面真实库的 C ABI 冒烟测试、Swift / C# 调用检查、Android JVM 生命周期测试、编译后 JNI 原型比较和 APK/桌面 ZIP 内原版文件哈希比较。两端真实桌面库的控制端和被控端均返回 `V4.14.2`。初期原版 ABI 运行和产物记录见 [public-build-results.json](analysis/ci/public-build-results.json)。独立路径的新运行中 macOS 10 项 Swift 测试、Android 5 项模拟器测试以及 Windows H.264/控制和候选生命周期检查通过，包括实际 8 秒 overlay 宽限与关闭中断。Windows 发布包真实首页和 Android 空首页的 [截图](analysis/ci/screenshots/) 与 [机器记录](analysis/ci/latest-independent-results.json) 已保存。Windows 原版 C# 引擎生命周期及 capability 绑定的 [实际报告](analysis/ci/e9692dd-windows-managed-engine.json) 已保存；两角色关闭后重启和同 runner 直接 DLL 字节对照通过，H265 的报告宽高为 0，尚无实际媒体/GPU 成功证据。Windows 原库 [房间传输探测](analysis/ci/576b43b-windows-rooms.json) 已记录回调、TLS/Socket.IO 和 room_info/guard 请求，依赖隔离子进程的显式测试 CA 插桩，后续[生产房间绑定报告](analysis/ci/2fb1d6a-windows-managed-rooms.json)已通过独立合成 room_info 回复、登录回调、GC 与关闭检查，[有效/空回复对照](docs/11-native-contract.md)分别收到 9004/2007。后续 [C# control 请求报告](analysis/ci/58bdfee-windows-managed-rooms-control.json)通过两个本地房间的二进制输入与原库实际 wire 字节核对，但没有 control ACK/对端/媒体。测试 CA 插桩不包含在生产类中；尚未建立真实原库对端或接入普通 UI。Android 原版 native 真机执行、完整原版引擎会话、物理混合互控、硬编硬解路径以及逐页面/逐像素 UI 尚未完成验证。

之前的私有仓库运行 [Actions 44643846778](https://github.com/materjojo/uuremote-clone/actions/runs/44643846778) 因计费限制，在 runner 启动前被拒绝。现已按用户要求转为公开仓库，使用免费的标准托管 runner。工作流按变更路径选择平台，文档不触发编译，支持手动选择单个平台；构建结果仍以对应 Actions 运行和产物为准。详见 [CI 管理](docs/12-ci.md)。

本地允许进行只读分析、源码/生成文件检查；`scripts/verify_official_runtime.py` 不带 `--bridge` 时仅核对保留文件身份，不编译或执行原版库。`scripts/gen_protocol_schema.py --check` 仅检查生成的源码。上述独立路径的运行、截图哈希和边界记录见 [latest-independent-results.json](analysis/ci/latest-independent-results.json)。

## 逆向记录

- [架构](docs/01-architecture.md)、[早期协议分析](docs/02-protocol.md)、[媒体](docs/03-media.md)、[UI 线索](docs/04-ui.md)
- [当前验收清单](docs/10-continuation-audit.md)、[已核对的 native 契约与更正](docs/11-native-contract.md)
- [REA Evidence](analysis/official/)、[Android 恢复来源与改动清单](analysis/official/android/recovery-manifest.json)

早期文档中的“与原版一致”“全部实现”等结论若与当前验收清单冲突，以带证据和覆盖边界的后者为准。尤其不能把自写 H.265 DataChannel、KCP/FEC 默认参数或占位页面算作原版实现。
