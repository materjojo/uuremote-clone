# 本轮续做检查表

基线提交：76a53616831cb19e3a66c44f3387840b58afcefc。沿用 materjojo/uuremote-clone 仓库。用户已明确授权转为公开仓库，以使用标准托管 runner 的免费计算。所有编译仍只在 GitHub Actions。

| 用户要求 | 当前证据/实现 | 验收状态 |
|---|---|---|
| 三个给定安装包深入分析 | 已保存原包与提取树；继续核对实际 JNI / C ABI | 部分完成 |
| 官方采集、硬编硬解、加速、通信路径 | 两端原版库工厂/版本及 Swift/C# 绑定已在 runner 验证；Windows 增加通过真实 DLL 字节对照的生命周期/能力和房间绑定，并通过双原库进程的实际 binary 与 HWND 窗口采集/编码/解码/渲染；Android 增加受测生命周期封装；普通 UI 原库主流程、其余平台媒体及真实硬件仍未接通验收 | 未完成 |
| 原版协议 | Windows descriptor 能证明 schema；原库 room-state、TLS/Socket.IO、真实 control/能力/SDP/ICE 路由和 Windows 二进制/窗口媒体已有隔离运行证据，使用显式测试 CA 插桩；生产授权、完整协议与跨平台仍需逐条跟踪 | 部分完成 |
| 三端所有非云设备功能 | 独立配对、同意、RTP 视频和控制已有实现及回环证据，不依赖网易登录；音频、文件、终端和完整输入仍未接通 | 未完成 |
| 各端 UI 与对应原版一致 | Android、Windows 已复用指定原包非云图片并取得真实克隆首页截图；其余布局仍为重建，缺同条件原版运行对照 | 未完成 |
| 去除云设备 | 当前应用未提供云设备入口；原版库保留通用代码，不代表已做代码级剥离 | 部分完成 |
| 一个仓库（用户更新为公开） | 原仓库已按用户明确授权转为 public，不另建仓库 | 已完成 |
| 只在 Actions 编译、提供三端产物 | macOS、Windows、Android 已编译/打包并产出下载；原库身份、绑定和独立路径媒体测试有各自运行记录，按变更选择平台 | 此构建要求已完成，端到端验收另计 |
| 仅在原包可证明相同处共享 | protobuf schema 可共享；平台 callback 长度不同，不能盲用 Windows 布局 | 部分完成 |

## 本轮已观察到的缺陷

- Windows `ExchangeControlledInterface` 是 ordinal 2，`ExchangeControllerInterface` 是 ordinal 3（完整 PE exports Evidence 见 `analysis/official/windows-exports.json`）。
- macOS callback 长度是 controller=17、controlled=15；Windows 为 18、16。Mac factory 指令读取到偏移 0x80 / 0x70；原主程序 ObjC 类型编码相符。
- 两平台函数表为普通 C 函数表；没有隐含 this。控制端版本查询 slot 17，被控端 slot 18。旧 Swift bridge 把槽地址当函数地址，并将 Array 对象表示作为 callback 数组传入。
- Android JNI native 方法为实例方法。控制端 `Connect` 接收 `(long, ByteBuffer, String, String)`，四个发送方法接收 direct ByteBuffer；被控端发送接收 byte[]。
- Android `GetConnectionStats` 返回 int，不是 String / 输出 byte[]；`CheckAlive` 无参返回 int，不是 boolean。
- JNI 读取配置 getter，不能用仅有 public fields 的 Java model 替代；还需继承的原始回调与辅助 Surface/MediaProjection/VirtualDisplay 类。
- Android connectRemote 先对 null session 建立方法引用；退出尝试将 decorView 重新作为 contentView；剪贴板监听未释放。
- macOS 缺信令服务器会进入 connected；默认把推断的 KCP/FEC 帧套在 control channel 上。两者都不能视为原版协议。

## 本轮修正

- 原版桌面库与三端配置按 SHA-256 保留；C ABI、Swift 和 C# 改为只开放已核对的工厂/版本检查，不再沿用危险的旧表调用。
- Android 恢复 22 个原版 glue 类及 getter/回调/辅助类，并增加 DEX → 编译 class 原型对照；修复 null session 引用、视图恢复和剪贴板监听释放。
- 新增 `OfficialControllerSession`，管理原版引擎所有权、LoginRoom/Connect、音视频轨道、各通道原始字节及完整清理；替身后端测试验证失败回收、重复关闭、重复连接与时区参数。当前 UI 仍使用实验性 `StreamerSession`，此封装尚缺认证/房间层和真机执行。
- 首次实际编译暴露并修正 `javap` 解析器把 descriptor 的括号当方法声明、C# SafeHandle 内 `Close` 名称遮蔽两处问题；不把检查器失败误报为原包 JNI 不匹配。
- C++ / Swift 字段表统一为完整 179 条消息；补齐 `ScreenResolution` 和嵌套 map entry。Release 测试启用断言，并修正原先没有把生成的 parity 装入恢复数组的测试数据错误。
- macOS 缺少信令端点时明确失败；实验 KCP/FEC 包装默认关闭，断开时清理 timer/transport。
- 清理 Windows 与 Android 三套语言资源中各 244 条云设备/云硬盘关联文案；移除应用里“硬编已启用”“弱网已启用”等没有运行证据的提示。完整协议和原版媒体库中的历史代码仍保留，未声称库级剥离完成。

## 本轮 CI 实际结果

[Actions 44643846778](https://github.com/materjojo/uuremote-clone/actions/runs/44643846778)，提交 `0733e90b2f50ffb855a44654eb761cef83cc5f36`：6 个 job 全部在 runner 启动前拒绝，steps 均为空，没有编译、测试日志或新的应用产物。GitHub 的原文是：

> The job was not started because recent account payments have failed or your spending limit needs to be increased. Please check the 'Billing & plans' section in your settings

完整 run/check annotations 保存于 [0733e90-blocked.json](../analysis/ci/0733e90-blocked.json)。仓库也没有已注册的 self-hosted runner。此后用户明确授权将现有仓库转为 public，已通过 API 确认 private=false；改用公开仓库的标准托管 runner，并管理按平台触发的构建。仍未在本地绕过“只在 Actions 编译”的限制。

公开后的 [Actions 44648328290](https://github.com/materjojo/uuremote-clone/actions/runs/44648328290)（`2f65722`）已经实际运行：Linux Release 测试、macOS 应用/Swift 3 项测试、macOS C ABI 及 Windows C ABI 通过；Windows 托管绑定编译和 Android 检查脚本暴露上述缺陷。该轮产出 macOS ARM64 ZIP 与 native 报告。

修正后的 [Actions 44649504313](https://github.com/materjojo/uuremote-clone/actions/runs/44649504313)（`2903d80`）全部应运行 job 通过：plan、Windows、Android；Linux 与 macOS 因输入未变跳过。Windows 两角色 C ABI 和 C# 绑定均取得 `V4.14.2`，并产出自包含 ZIP。Android 执行 `testDebugUnitTest`、通过 22 类的 237 个方法 descriptor / 24 个常量检查及 APK 内原版文件身份检查，产出 ARM64 debug APK。两端桌面 ZIP 都通过原库/config 完整哈希检查，macOS 同时检查执行权限。见 [机器记录](../analysis/ci/public-build-results.json)、[macOS 原生报告](../analysis/ci/2f65722-macos-native.json)、[Windows 原生报告](../analysis/ci/2903d80-windows-native.json)。本地未编译或启动这些应用。

## Windows 原库生命周期与能力的进一步结果

- `bee0d8f` / [44881938396](https://github.com/materjojo/uuremote-clone/actions/runs/44881938396)：补入相邻原版 `StreamerCodecDetector.exe`，发布包身份检查和 14 次 detector batch 通过，但 112 条 RESULT 的 width/height/flag 均为 0。软件/微软虚拟 adapter 结果不能验收物理 GPU。
- 初次 Initialize 把第三个 UTF-16 参数错当路径，两角色以 `0xC0000374` 退出。继续静态追踪确认该项是日志文件 suffix，修正后 `d11ee29` / [44885010956](https://github.com/materjojo/uuremote-clone/actions/runs/44885010956) 两角色 Initialize/Finalize=0。失败报告保留，未声称已经独立证明堆损坏根因。
- `7db8179` / [44885744775](https://github.com/materjojo/uuremote-clone/actions/runs/44885744775)：原库 slot 15 capability 查询及重复字节相符通过，返回 H264/H265 JSON，H265 宽高均为 0。原库实际生成 SLOG 二进制日志，现保留原始 base64/SHA-256，不把文本搜索无错误解释为配置消费成功。
- `e9692dd` / [44886678910](https://github.com/materjojo/uuremote-clone/actions/runs/44886678910)：Windows 生产 C# 绑定在角色隔离进程中通过初始化、能力查询、进程独占、阻止其它工厂、重复关闭、关闭后拒绝及再次初始化；返回字节与同 runner Python 原生调用完全相同。[实际报告](../analysis/ci/e9692dd-windows-managed-engine.json)。本轮只选择 Windows，其余平台跳过。绑定仍未接入普通 UI 会话，也未执行实际采集、编码/解码帧、回调投递或互控。

- `576b43b` / [44891638984](https://github.com/materjojo/uuremote-clone/actions/runs/44891638984)：Windows 原库两角色 room entry 返回 handle 1，投递 room-state、连接指定 loopback。普通路径拒绝临时自签名 CA，`SSL_CERT_FILE` 也未改变结果；继续核对内嵌根证书加载后，仅在隔离 Actions 子进程中显式调用原库 parse/add/release helper 添加测试证书。插桩路径完成 TLS 1.3、WebSocket/Socket.IO，发出 `room_info`，被控端还发出有 `GRD1` 附件的 `guard` 事件；Destroy/Finalize=0。[完整报告](../analysis/ci/576b43b-windows-rooms.json) 保留 baseline 拒绝和插桩边界。这不等于默认原库接受测试 CA、业务入房、媒体或普通 UI 集成；生产 C# 未加入该插桩。

- `2fb1d6a` / [44894436889](https://github.com/materjojo/uuremote-clone/actions/runs/44894436889)：生产 C# 房间入口、关闭和排队回调已在两角色通过真实原库检查，包含 GC、handle 1 显式关闭、handle 2 再次登录、Dispose 自动关闭与关闭后拒绝。[生产报告](../analysis/ci/2fb1d6a-windows-managed-rooms.json)。独立 room_info 的[有效](../analysis/ci/2fb1d6a-windows-roominfo.json)/[空对象](../analysis/ci/2fb1d6a-windows-roominfo-empty.json)对照分别收到原库 9004/2007；room-state 与 connection-code 是不同域。TLS fixture 仍使用明确的子进程 CA 插桩，生产绑定不含插桩。只构建 Windows，其余跳过；完整对端与媒体仍未接通。

- `58bdfee` / [44897758496](https://github.com/materjojo/uuremote-clone/actions/runs/44897758496)：controller 的生产 `RequestControl` 在两个真实原库本地房间发送了字段与输入完全匹配的 control 请求，二进制 app data 包括 NUL/0xff/0xfe；父端保存实际 message/envelope，强制 GC、输入预先拒绝和 controlled 角色隔离均通过。[完整报告](../analysis/ci/58bdfee-windows-managed-rooms-control.json)。slot 4 是 controller 特定 ABI，controlled 同槽是 capture 功能。该 fixture 不提供 control ACK、同意或真实 peer，9005/原库生成的 capability JSON 仍不是控制/媒体成功。

- `9e93448` / [44899602774](https://github.com/materjojo/uuremote-clone/actions/runs/44899602774)：controlled slot 10 OnNewControl 的生产队列已通过真实原库运行，包含 GC、回调返回前有界复制、22 字节 binary app data、control ID、原库生成的 1127 字节协商 JSON、一次性 drain 和关闭后拒绝。[报告](../analysis/ci/9e93448-windows-managed-controlled.json)。父端注入的是合成 be-controlled，未调用 capture，9007/9008 和 JSON result=0 不能当作真实 peer 或媒体成功。

- `e8503b7` / [44900334672](https://github.com/materjojo/uuremote-clone/actions/runs/44900334672)：两个独立原库进程通过独立记录器路由真实 control、controlled 能力回复、offer/answer 和双方 host candidate，[报告](../analysis/ci/e8503b7-windows-native-pair.json)已冻结；没有 STUN/TURN、网易业务请求、capture 或媒体，信令完成不能替代真实数据接收。测试身份/自动允许和显式 CA 插桩仍非生产服务。
- `0fb368f` / [44903013760](https://github.com/materjojo/uuremote-clone/actions/runs/44903013760)：新 binary 检查失败且[完整报告](../analysis/ci/0fb368f-windows-native-binary-failure.json)保留。实际调用链表明初版错用了 FileData 槽 13/11；现改为原库明确的 BinaryData 槽 12/10，接收断言不变。此失败不能写作 binary/GPU 成功。

- `5c810f8` / [44903995375](https://github.com/materjojo/uuremote-clone/actions/runs/44903995375)：修正 BinaryData 槽后，两个原库进程的[双向随机数据报告](../analysis/ci/5c810f8-windows-native-binary.json)通过。双方实际回调各收到对方 275 字节输入，父端逐字节复核；发送后源数组修改、GC、关闭后拒绝和清理通过。只涉及同 runner 私网 host candidate 和独立本地信令；没有媒体、输入、物理跨端或公网打洞证据。

- `96cd54e` / [44911242801](https://github.com/materjojo/uuremote-clone/actions/runs/44911242801)：原库[窗口采集与渲染报告](../analysis/ci/96cd54e-windows-native-media.json)通过。被控实际 HWND 两次改变四色图案，控制端原 renderer 从灰底变为相应图案，四张 320×240 BMP、FrameChange、显式停止/GC/窗口清理和全部旧回归均通过；[真实截图](../analysis/ci/96cd54e-window-media/evidence.json)与来源哈希保留。普通 UI、H265、实际硬件加速、跨设备与公网打洞仍未由此验收。

## 边界

Ghidra 对 macOS 13MB dylib 的默认自动分析在 330 秒触发 provider_timeout，未产生完整伪代码。保留此覆盖缺口；使用有文件哈希和地址的 ARM64 静态反汇编核对工厂/版本函数，不把它称作完整反编译。当前 Linux 主机不能运行 macOS/Windows UI，原包没有提供登录凭据、真实会话流量和物理采集设备，CI 冒烟测试也不能证明端到端或逐像素一致。

## 独立路径的最新结果

独立路径已经有可复核的 runner 级媒体和界面证据，但仍与原版官方会话分开计数：

- macOS build run `44670463306` 在提交 `eacc0e8` 通过 10 项 Swift 测试；候选策略、实际原生 WebRTC 视频/控制和原版库 wrapper 测试均通过。此前的 SCTP 首包竞争已通过在回调入口先安装 data-channel delegate 修正。新增 8 秒等待测试覆盖两种 overlay 地址、去重、连接后抑制迟到候选，以及关闭时中断候选批次。
- Windows build run `44670463306` 通过真实 ICE/DTLS、双向 SCTP、合成 H.264 编码/RTP/解码、三平台配对码回环与 8 秒 overlay/连接/关闭检查。发布包已通过自动启动真实 WPF `MainWindow` 并生成截图；具体源构建与截图运行绑定在机器记录中。该截图证明启动和渲染路径，不证明原版几何或像素一致。
- Android run `44670528149` 在 Android 11 x86_64 模拟器通过 5 项测试：真实空首页、macOS/Windows/Android 配对码回环、内嵌 SDP 候选策略、8 秒 overlay/连接/关闭检查、合成视频和控制。它没有执行发行 APK 的 ARM64 原版媒体 `.so`。
- 机器可核对的 artifact ID、截图 SHA-256 和覆盖限制在 [latest-independent-results.json](../analysis/ci/latest-independent-results.json)。[独立设备与连接说明](13-independent-peers.md) 记录服务部署、配对、权限、候选披露、Tailscale 和当前未接入业务。

这些结果仍不覆盖物理混合平台互控、不同 NAT 的公网打洞、硬件编解码选择、音频、文件传输、终端、原版服务房间或逐页面 UI 对照。
