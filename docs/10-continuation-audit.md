# 本轮续做检查表

基线提交：76a53616831cb19e3a66c44f3387840b58afcefc。沿用 materjojo/uuremote-clone 仓库。用户已明确授权转为公开仓库，以使用标准托管 runner 的免费计算。所有编译仍只在 GitHub Actions。

| 用户要求 | 当前证据/实现 | 验收状态 |
|---|---|---|
| 三个给定安装包深入分析 | 已保存原包与提取树；继续核对实际 JNI / C ABI | 部分完成 |
| 官方采集、硬编硬解、加速、通信路径 | 两端原版库工厂/版本及 Swift/C# 绑定已在 runner 验证；Android 增加受测生命周期封装；主流程、采集/编解码仍未接通验收 | 未完成 |
| 原版协议 | Windows descriptor 能证明 schema；信令与业务调用仍需逐条跟踪 | 部分完成 |
| 三端所有非云设备功能 | 登录、服务端房间、媒体、文件、终端等尚未全链路接通 | 未完成 |
| 各端 UI 与对应原版一致 | 原版 Android 为 Compose、Windows 为 Qt、macOS 为 Swift；当前 UI 是占位重建 | 未完成 |
| 去除云设备 | 当前应用未提供云设备入口；原版库保留通用代码，不代表已做代码级剥离 | 部分完成 |
| 一个仓库（用户更新为公开） | 原仓库已按用户明确授权转为 public，不另建仓库 | 已完成 |
| 只在 Actions 编译、提供三端产物 | 公开后 macOS、Windows、Android 均编译/打包并产出下载；桌面原库/绑定、Android descriptor/包装/JVM 检查已通过；增量修复只运行 Windows/Android | 此构建要求已完成，端到端验收另计 |
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

## 边界

Ghidra 对 macOS 13MB dylib 的默认自动分析在 330 秒触发 provider_timeout，未产生完整伪代码。保留此覆盖缺口；使用有文件哈希和地址的 ARM64 静态反汇编核对工厂/版本函数，不把它称作完整反编译。当前 Linux 主机不能运行 macOS/Windows UI，原包没有提供登录凭据、真实会话流量和物理采集设备，CI 冒烟测试也不能证明端到端或逐像素一致。
