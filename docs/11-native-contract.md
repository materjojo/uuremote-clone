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

## Windows capability cache and probe path (2026-11-20)

- **Windows capability cache and probe path have now been bounded.** The cache helper first obtains the current module filename with `GetModuleFileNameW`, removes path components, and derives a path using the visible `streamer` / `config` components. The final filenames are `encoder_codec_capability_cache.json` and `decoder_codec_capability_cache.json`; the exact deployment-relative directory mapping is not promoted beyond that static observation. The cache loader parses the file, rejects invalid JSON, and separately treats an empty encoder or decoder payload as a request to probe again. It also checks a version word: `FUN_180a79e30` accepts only `8`, then compares the stored GPU fingerprint byte-for-byte with a freshly computed value. A mismatch is logged as `GPU fingerprint changed: {} -> {}` and the cache is not accepted. Evidence bundle `218-windows-cache-probe-paths.full` (SHA-256 `f94a9979032d43d8f5cbf5746d31129ecc2def1606792fc0543484505eee8072`, full normalized responses at `/home/ubuntu/uuyc_clone/analysis/deep-native/windows-followup/results/218-cache-probe-paths.full.json`) contains the complete bodies for the following anchors: `FUN_180a77990`, `FUN_180a78420`, `FUN_180a78ab0`, `FUN_180a79e30`, `FUN_180a794e0`, `FUN_180a7a0c0`, `FUN_180a7c530`, `FUN_180a805c0`, `FUN_180a81030`, `FUN_180a81a90`, `FUN_180a81c30`, `FUN_180a86b70`, and `FUN_180a876a0`.
- **GPU fingerprint and serialization behavior are distinct from candidate ordering.** `FUN_180a78420` creates a DXGI factory, gathers adapter/property material, hashes the resulting byte string with the FNV-1a 64-bit recurrence, and formats the result as 16 hexadecimal characters. This is a cache identity value, not proof of which encoder was selected. `FUN_180a7a0c0` writes metadata beginning with the observed value `8`, then serializes eligible capability data through the cache-file writer. For the encoder vector (stride `0x28`), the visible predicate is tag `!= 5` and nonzero width/height-like fields (`+0x14 * +0x18 != 0`); for the decoder vector the visible predicate is tag `!= 0x25` with the same nonzero-product check. If the encoder probe contains only software fallback records, the function logs `encoder probe produced only software fallback (no hardware success), skip writing cache to allow retry on next start`; the decoder has the corresponding software-only skip message. These are cache-write predicates and must not be conflated with the earlier capability-iteration predicate or with selector runtime fallback.
- **Cache writes use a temporary file and replacement.** `FUN_180a794e0` builds a process-specific temporary name using the visible `L".{}.{}.tmp"` pattern, serializes through a `std::ostream`-shaped helper, checks flush/close status, and calls `MoveFileExW` with replacement/write-through flags. It logs open, write, flush, and replacement failures and reports successful replacement as `capability cache written successfully to {}`. `FUN_180a81c30` / `FUN_180a81a90` are checked, NUL-terminated UTF-16 buffer construction/append helpers, while `FUN_180a805c0` copies capability records into a separately allocated vector. The exact JSON property names and the full field-to-record mapping remain open because the current Ghidra bodies show template/stream operations and untyped intermediate storage rather than a trustworthy schema. `FUN_180a7c530` snapshots probe policy under the shared state lock, skips encoder probes disabled by configuration, runs the selected probe set, and returns capability vectors; its decompilation does not by itself establish detector process execution or hardware success.

## Windows selector retry and fallback tail (2026-11-20)

- **Per-frame retry policy is now branch-level evidence.** `FUN_180c219b0` obtains the selected candidate from the 16-byte record vector and calls its vtable slot `+0x30`. A zero result clears the consecutive error counter at `this+0x420` and returns success. A nonzero result increments that counter; if the status is not `-13` and the count is below `10`, the same error is returned immediately. Status `-13`, or the tenth accumulated failure, enters fallback: the counter is reset, the current record's enabled byte at `+4` is cleared, the initialized state at `this+0x424` is cleared, and the next enabled candidate is tried. With fewer than two enabled candidates remaining it logs `last valid encoder {} failed, all encoders exhausted` and returns `0xfffffff0` (`-16`); after the loop it logs `all encoder fallback attempts exhausted`. This is distinct from backend initialization status mapping and from the selector's initial candidate search. Evidence bundle `219-windows-selector-retry-tail.full` (SHA-256 `43a5a735a3beb0f02a07298df603658addcc0e2cde57f752928cea8f4a52986f`, full normalized responses at `/home/ubuntu/uuyc_clone/analysis/deep-native/windows-followup/results/219-selector-retry-tail.full.json`) retains the retry and related helper bodies.
- **Selection order and reinitialization are explicit.** `FUN_180c223a0` detects an adapter change, schedules encoder reinitialization through `FUN_180c23ea0`, releases initialized candidates through `FUN_180c218c0` (vtable `+0x28`), then tries same-adapter matching via `FUN_180c227f0` before cross-GPU matching via `FUN_180c22c50`. The same-adapter helper requires an enabled record whose object adapter identifier at `object+0x10` matches the frame adapter and invokes initialization through `FUN_180c21370` / vtable `+0x60`; a nonzero initialization result disables that record. The cross-GPU helper walks remaining enabled records, tries initialization, records success as a frame-level encoder change, and disables a record when initialization fails.
- **Codec fallback has a specific H.265 guard.** When the frame adapter supports same-adapter H.264 but not H.265, `FUN_180c22c50` logs `skip cross adapter H265 and request codec fallback` and does not continue cross-GPU H.265 selection. If both same-adapter and cross-GPU selection fail, `FUN_180c223a0` logs `unknown h264 software encode error` when the selector codec field at `this+8` is `4`; otherwise it logs a fallback to H.264. These branches establish control flow and logging, but do not prove that a software encoder was actually invoked or that a codec renegotiation completed.
- **The software candidate has a real constructor path, but dispatch remains open.** `FUN_180c20e10` is sourced from `video_encoder_software_fallback_wrapper.cpp`, consumes encoder objects, queries each object's vtable `+0x58` description, maps visible names to backend tags NVENC `0`, AMF `1`, and QSV `2` (unknown `5`), and materializes 16-byte candidate records with enabled flag/object fields. This proves software-fallback wrapper materialization and candidate-table participation; it does not identify the final OpenH264 frame method, prove that the software object is selected after hardware failure, or prove encoded-frame delivery. The exact indirect owner of the constructor table and the late software dispatch remain open.

## 后续原生证据边界（2026-11-20）

以下结论只针对保存的原始文件静态 Evidence，不代表 ARM64 原库已经在设备上运行，也不代表 Windows 硬件路径已经在当前机器上选中。

- **Android 信令输入的所有权边界已收窄。** `libstreamer.so`（ARM64，SHA-256 `8ee34e11b789463c7d30dca64614a262d928dc4e6b82debc8d8292d05ff2f836`）的 `FUN_00d3c8ec` 在入口把长度保存为 `w20`，随后以 32 位值检查 `<= 0x80000`。通过检查后，它把借用的 JNI 数据复制到自有存储，再交给 executor/task 路径；这支持在 JNI `JNI_ABORT` 释放数组后继续使用该副本。证据未证明 executor 已执行、信令已送达另一端，亦未证明其它发送入口具有相同所有权规则。Evidence `ev_0774ba71feb146885e70a37c8801f2c0cacdff5e441379be85962b0ddd34ae34` (`/home/ubuntu/uuyc_clone/analysis/deep-native/android-jni-followup/results/163-asm-send-signal-callback.evidence.json`), 重复核对的伪代码 Evidence `ev_2d21883984792f7e5cf6edf400139c41e1b5a3a472ae3ad6c81bdde1a1ce11cc` (`/home/ubuntu/uuyc_clone/analysis/deep-native/android-jni-followup/results/166-repeat-send-signal-callback.evidence.json`)。
- **状态边界已记录但语义仍未命名。** 在该信令路径上，正常清理/完成路径向 `FUN_00f6af08` 传入 `0`，未初始化路径传入 `1`，超长输入路径传入 `0xbdd`；`FUN_00f6af08` 的最终状态定义尚未恢复。`CheckAlive` 的初始化路径调用 `FUN_00d31a34`，把其 32 位结果保存后再交给同一 helper；未初始化路径直接传入 `1`。因此实现不得把这些 helper 输入直接公开成已确认的 API 错误码或“已送达”状态。SendSignalData assembly (`/home/ubuntu/uuyc_clone/analysis/deep-native/android-jni-followup/results/163-asm-send-signal-callback.txt`)、CheckAlive assembly Evidence `ev_29375988f04229a84703ee1194f89fd12ebc17fae932be304755a53f9f494beb` (`/home/ubuntu/uuyc_clone/analysis/deep-native/android-jni-followup/results/164-asm-checkalive-callback.evidence.json`)。
- **Android 房间返回值不能从 JNI 外观反推核心语义。** Java 声明仍保持 `long`；`LoginRoom` 和 `CreateRoom` wrapper 都在调用 PLT/adapter 后保存并恢复低 32 位 `w` 值，因此 JNI 可见的是零扩展的低 32 位结果。控制端/被控端 slot 2 的 room-config 指针传递已核对；被控端 slot 2 `FUN_00d36ebc` 的 Ghidra 声明为 `void`，当前仅能解释为异步房间操作候选，不能把它命名为已验证的 room ID 或 status 返回。`DestroyRoom` adapter 还明确把 room handle 的低 32 位传给 slot 3。核心方法表交换证据为 `ev_5bf49780a51aef4a18a273dc14d8fc89598e337f5ecb568b0342e05cca40ea5e` (`/home/ubuntu/uuyc_clone/analysis/deep-native/android-jni-followup/results/165-asm-exchange-controlled.evidence.json`) 和 `ev_06332774ccd46efafb8b7df261095956415cf3bc01f704148a6039c3e2f35a37` (`/home/ubuntu/uuyc_clone/analysis/deep-native/android-jni-followup/results/167-pseudo-exchange-controlled.json`)；精确 `CreateRoom` epilogue、核心 slot-2 ABI 和实际返回含义仍开放。
- **Windows 媒体证据尚未证明全局 backend priority。** 在同一 PE `streamer.dll`（SHA-256 `ac351cf4e1d489e0b6e1a3df5cdf8aed96348876f7e2c7fcf7162fe59e1bb1c4`）中，`FUN_180c2d080` 是包含 NVENC 初始化、NVENC 编码输入路径和 software fallback 的 NVENC 编码路径；它按 codec/format 条件懒加载 `nvEncodeAPI64.dll`，而 `FUN_180c2f2d0`/`FUN_180c2f730` 负责 NVENC factory。AMF 解码父路径 `FUN_180cd4070` 和 oneVPL 解码父路径 `FUN_180cb62e0` 分别执行自身的 AMF/Intel DXGI adapter 检查并写入同类结果记录。现有证据没有显示这三个父路径由一个已恢复的全局候选数组按固定顺序串联，也没有恢复 NVDEC/OpenH264 的确切表槽或最终选择/重试顺序；不能据此宣称 AMF、oneVPL、NVENC 或 NVDEC 的优先级。NVENC selector Evidence `ev_01232e129bd17fbe9d5e6d427e75bf421f71badc0c466bcc6957916f89887cfe` (`/home/ubuntu/uuyc_clone/analysis/deep-native/windows-followup/results/210-pseudo-selector-entry.evidence.json`), selector assembly Evidence `ev_ae5588bc1fa8e7f209d7026c88a4018879779ec2ccc18f70801113324ff815f1` (`/home/ubuntu/uuyc_clone/analysis/deep-native/windows-followup/results/211-asm-selector-entry.evidence.json`), NVENC loader Evidence `ev_90c1bc1c69f2eb85b5b7334f374396de602059151903b12b9bb88655d42d2822` (`/home/ubuntu/uuyc_clone/analysis/deep-native/windows-followup/results/212-pseudo-nvenc-init.evidence.json`), AMF probe Evidence `ev_19f7762033aca158586847a89d5dcd9adde60c226c02214204c757ac2683a541` (`/home/ubuntu/uuyc_clone/analysis/deep-native/windows-followup/results/213-pseudo-amf-probe.evidence.json`)。
- **本轮 Evidence 的共同限制。** Android 记录的 subject 都是原始 ARM64 ELF，Windows 记录的 subject 都是同一原始 PE；provider 为 Ghidra 12.1.4，Evidence confidence 为 `observed`，但 provider 明确声明伪代码不是源代码，assembly 是 Ghidra Listing，且部分 no-return/fallthrough 由 FunctionManager 假设排除。上述材料只冻结地址、指令、调用和数据所有权边界；真实 JNI ABI、房间响应、executor delivery、设备硬件能力、全局 codec selector、缓存生成和端到端媒体结果仍须分别验证。
