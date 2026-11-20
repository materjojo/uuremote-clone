# 原版媒体库契约：当前已核对的范围

本页更正早期 `09-official-api.md` 中未经核实的 ordinal、隐含 this、跨端回调布局和“复制 Java 类即可使用”等结论。事实来源和运行验证分开记录，不把静态观察写成端到端成功。

## 输入与静态证据

- 保留文件和 SHA-256：[manifest](../native/official/manifest.json)。三端的原版配置各自保留，不混用默认参数。桌面库为适应当前上传通道，采用 gzip 后的 512 KiB 分片存储；[恢复脚本](../scripts/restore_official_runtime.py) 先核对每片 SHA-256，再解压核对完整原库 SHA-256。CI 在加载/打包前恢复，输出字节仍与安装包完全相同。
- Windows PE 导出：[windows-exports.json](../analysis/official/windows-exports.json)；既有反编译：[ghidra_streamer.txt](../analysis/official/ghidra_streamer.txt)、[ghidra_vtable.txt](../analysis/official/ghidra_vtable.txt)。
- macOS ARM64 / x86_64：[macos-streamer-static.json](../analysis/official/macos-streamer-static.json)，记录 slice 哈希、VA、文件偏移、指令字节、原始函数表。由 [inspect_macos_streamer.py](../scripts/inspect_macos_streamer.py) 生成，属于指定范围反汇编，**不是整个库的反编译**。
- Android：[REA 原型/反编译记录](../analysis/official/android/)、[Evidence bundle](../analysis/official/continuation-evidence.json) 和 [recovery-manifest](../analysis/official/android/recovery-manifest.json)。恢复脚本记录来源类文件及改写前后 SHA-256。

## 桌面工厂与函数表

| 项目 | Windows | macOS |
|---|---|---|
| 控制端导出 | ExchangeControllerInterface，ordinal 3 | ExchangeControllerInterface（Mach-O 符号前导 `_` 不传给 dlsym） |
| 被控端导出 | ExchangeControlledInterface，ordinal 2 | ExchangeControlledInterface |
| 控制端 callback 指针数 | 18 | 17 |
| 被控端 callback 指针数 | 16 | 15 |
| 控制端函数表槽数 / version 槽 | 21 / 17 | 21 / 17 |
| 被控端函数表槽数 / version 槽 | 23 / 18 | 23 / 18 |

工厂接收连续的指针数组，复制回调到库内全局表，返回静态 C 函数指针表。调用函数表中的入口时没有隐含 `this`。不能把槽的地址当作函数入口，也不能把 Swift Array 对象表示直接当成连续数组。

当前开放的版本入口原型是 `int (*)(const char **bytes, uint32_t *size)`。输出指向库拥有的内存，调用方只复制，不释放。静态代码返回的字符串是 `V4.14.2`（媒体核心版本，非应用 4.48.1）。桌面测试需实际加载原库再核对返回值。

[共享检查层](../native/official/official_streamer_abi.cpp) 只做加载、角色选择、空 callback 工厂和版本查询。按**各平台实际长度**分配回调元素；不把额外的 Windows 槽解释成“终止符”，也不据此共享回调成员定义。它不初始化媒体引擎、不创建房间、不进行采集或网络连接。工厂改写全局回调，因此当前检查接口不能与活动媒体会话并行使用。

尚未恢复的会话/轨道/采集/渲染/ICE 参数和对象生命周期仍不对外猜测性开放。现有应用的实验性 WebRTC/编码路径不因此成为官方核心路径。

## Android JNI

- 方法是**实例 native 方法**，不能换成 `static native`。
- 控制端 `Connect(long, ByteBuffer, String, String): int`；控制端四类发送采用 direct `ByteBuffer`，被控端采用 `byte[]`。
- `GetConnectionStats(long): int`；`CheckAlive(): int`。不得改为输出 String、无意义的 byte[] 或 boolean。
- JNI 依赖配置的 getter、继承回调、同名 Surface / MediaProjection / VirtualDisplay 辅助类。仅恢复字段名不足以证明兼容。
- 恢复了 22 个类，去除依赖 Kotlin 编译器的合成构造器/DefaultImpls；delegate 默认实现保留方法 descriptor，空检查改用 Java API。Java 无法覆盖 `Object.finalize(): void` 为 `int`，因此只把非 native 包装方法 `finalize(): int` 改名为 `shutdown(): int`；`Finalize(): int` native 名字不变。
- [verify_android_abi.py](../scripts/verify_android_abi.py) 用 `javap -s -p -constants` 对照冻结的原 DEX 记录，现覆盖恢复清单内全部 22 个类的原有方法（包含 helper 构造器）、实例/static 和 native 修饰，以及 DEX 明确编码的整型常量。仅排除已记录的 Kotlin mask 构造器、静态初始化代码，并显式检查 finalize → shutdown 的包装改名。`--check-evidence` 检查 22 个类均有原包证据且恢复源码哈希一致。它不能验证实现语义、class-loader、设备 API 或硬件路径。
- APK 检查逐一对比保留的三个 `.so` 和 config；打包明确不 strip 这三份原版库，防止 CI 悄悄改变二进制身份。

[OfficialControllerSession](../platforms/android/app/src/main/java/com/example/uuremote/official/OfficialControllerSession.java) 现在包装原版控制端初始化、房间/连接提交、音视频轨道、各通道原始字节和清理。它限制同一进程一个 engine owner，使用系统时区，不额外封装控制消息，不以 Connect 提交成功表示连接完成；Finalize 失败时禁止再次抢占未知的全局 native 状态。Android 构建会先执行 JVM 生命周期/转发测试，后端为替身，不加载 ARM64 库。当前演示 UI 仍用实验性 StreamerSession；此层还缺认证/房间层接入，以及 ARM64 真机/模拟器的 native 初始化与会话验证，没有把“Java 测试通过”写成 JNI 运行成功。

## Android 原版会话与控制消息的进一步核对

以下均是指定 APK 方法的静态观察，尚未执行真实会话；不能把 Android 的服务端接口自动套给另外两端。

- `ControllerService.createConnection` 把 `Bb.W0` 编码成 protobuf，再调用 `connect(handle, bytes, appControlId, timezone)`。[REA ev_f0a9cead1bd2925600246124968d61d6071a1d4e617a41a632c2390fbe452c8d](../analysis/official/android/controller-create-connection.json)。第四项取 `Le.B.a().f9378a.getId()`；追踪 `Le.B.a()` 可见它来自 `ZoneId.systemDefault()`，**不是设备 ID**。[REA ev_14f4ec2f5ec06d9510ce33fc516558e40f10b1ac48e2b62e45fb62e920e38aee](../analysis/official/android/timezone-default.json)。
- `Bb.W0.toString` 明确把该类标为 `ConnectOptions` 并保留 14 个字段名；`Bb.T0.g` 是字段 1..14 的编码入口。逐项核对与 Windows descriptor 中的 `ConnectOptions` 相符，包括设备 ID=9、client_type=8、current_server_time=14。见 [字段名 Evidence](../analysis/official/android/connect-options-names.json)、[编码 Evidence](../analysis/official/android/connect-options-encode.json)。这支持共用这一消息的 wire 定义，不能外推所有会话状态或媒体对象布局相同。
- `Bb.J3.g` 编码 `Bb.K3` 的 seq=1、timestamp=2 和 payload 3..28；input_event=20。这与 Windows `Message` descriptor 的 tag 对应。[REA ev_e276d615a7d9416c49bebece132cbdb0ab68f50c6dc880e443784b67c7ea19e3](../analysis/official/android/message-encode.json)。这里未逐项恢复所有嵌套消息的语义和 Android 类型布局。
- `ControllerService.sendText` 会构造 `{"action":"text_input","content":...}`，按 UTF-8 传入 **sendControlData**。[REA ev_f04ab977044e66d0dd7bdcfbdd5ce29952949a7ad28968f5a658bb8c55ec6ec5](../analysis/official/android/controller-send-text.json)。因此控制通道既有 protobuf，也有 JSON 消息；不能把所有文本输入都重新封装为猜测的 protobuf 或 KCP/FEC 帧。

## Android HTTP 认证前提的进一步定位

已保存原 APK 的 [请求协程](../analysis/official/android/http-request-coroutine.json)、[公共头](../analysis/official/android/http-common-headers.json)、[头排序器](../analysis/official/android/http-header-comparator.json) 和 [签名结果编码](../analysis/official/android/http-signature-hex.json)。四项均为完整 Java 反编译输出，没有运行网络请求：

- 公共请求头包括 X-Param-CHN / OPR / PKGN / PLAT / REL / VC / ABI、client-id / device-id / user-id、OAID / TS / CNT / LANG；版本号为 Android 的 448001。空值在请求协程中被过滤，部分请求增加 X-Param-Nonce。
- 请求协程对头名按 Locale.ROOT 转小写后排序，只把 x-param- 前缀项拼成 `key=value`、用 `&` 连接；再与方法、请求路径/查询字串和原 body 串拼接，交给 `com.remote.nrdsign.a.a`，其结果经 `rf.m.e()` 的逐 nibble 字符编码放进 X-Param-SIGN。
- Authorization 的 Bearer token 在计算上述签名后附加。这说明 Android 接口不能只靠静态端点和一个 Bearer 头就算已接通。签名调用内部、服务端响应检查、真实登录与房间获取尚未恢复/验证；也未把这些 Android 头参数直接套给 macOS/Windows。

## 协议表更正

原始 Windows descriptors 包含 178 个顶层消息，另有 `MumuSetting.MapKeyValueEntry`，合计 179。旧 C++ 表遗漏了 `ScreenResolution` 和该嵌套消息（177）；旧 Swift 表仅有 160 条。两张表现从 [同一份冻结记录](../analysis/official/gv-pb-descriptors.json) 生成，并检查可复现性。保留完整 wire schema 不等于应用提供历史云设备业务。

## Actions 验证与覆盖边界

工作流构建三端、运行启用断言的 C++ Release 测试，在 macOS / Windows runner 加载原版库查询两种角色版本，并分别经过 Swift 和 C# 绑定。报告含平台、架构、原库和 bridge 的哈希；APK 增加编译原型和包装身份检查；桌面 ZIP 也核对原版库/config 的完整 SHA-256，并检查 macOS 执行权限。具体结果以对应 Actions 运行及 artifacts 为准，源代码中的测试本身不构成已通过的结果。

历史私有仓库首轮 `0733e90` 对应 [Actions 44643846778](https://github.com/materjojo/uuremote-clone/actions/runs/44643846778) 因账号付款/支出上限，全部 job 在 runner 启动前被拒绝。[原始状态记录](../analysis/ci/0733e90-blocked.json)。

公开后已实际通过：`2f65722` 的 macOS Swift 3 项测试、C ABI 两角色与打包，`2903d80` 的 Windows C ABI / C# 两角色与打包，以及 Android JVM 测试、237 个方法 descriptor / 24 个常量与 APK 身份检查。桌面四次角色探测均返回 V4.14.2，native status=0。原生报告见 [macOS](../analysis/ci/2f65722-macos-native.json) / [Windows](../analysis/ci/2903d80-windows-native.json)，job/step/artifact 与验证日志摘要见 [public-build-results.json](../analysis/ci/public-build-results.json)。后一次推送没有改动 macOS 或共享实现，因此只构建 Windows/Android，没有额外重建已通过的平台。

工厂/版本入口通过也不能证明登录、真实信令、媒体轨道、音视频、输入注入、文件传输、终端或 UI 一致。物理采集、硬件编码器与解码器、三端互控和无云业务仍需单独验收。
