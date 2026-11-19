# 本轮续做检查表

基线提交：76a53616831cb19e3a66c44f3387840b58afcefc。沿用 materjojo/uuremote-clone 私有仓库。所有编译只在 GitHub Actions。

| 用户要求 | 当前证据/实现 | 验收状态 |
|---|---|---|
| 三个给定安装包深入分析 | 已保存原包与提取树；继续核对实际 JNI / C ABI | 部分完成 |
| 官方采集、硬编硬解、加速、通信路径 | 原版 streamer 三端不同 ABI；旧桥接错误且未接主流程 | 未完成 |
| 原版协议 | Windows descriptor 能证明 schema；信令与业务调用仍需逐条跟踪 | 部分完成 |
| 三端所有非云设备功能 | 登录、服务端房间、媒体、文件、终端等尚未全链路接通 | 未完成 |
| 各端 UI 与对应原版一致 | 原版 Android 为 Compose、Windows 为 Qt、macOS 为 Swift；当前 UI 是占位重建 | 未完成 |
| 去除云设备 | 当前应用未提供云设备入口；原版库保留通用代码，不代表已做代码级剥离 | 部分完成 |
| 一个私有仓库 | 已有且已确认 isPrivate=true | 已完成 |
| 只在 Actions 编译、提供三端产物 | 已配置三端打包/上传、Release 断言、桌面库实际加载和 Android descriptor/包装检查；结果待对应 Actions 运行 | 已配置，待 CI |
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
- C++ / Swift 字段表统一为完整 179 条消息；补齐 `ScreenResolution` 和嵌套 map entry。Release 测试启用断言，并修正原先没有把生成的 parity 装入恢复数组的测试数据错误。
- macOS 缺少信令端点时明确失败；实验 KCP/FEC 包装默认关闭，断开时清理 timer/transport。
- 清理 Windows 与 Android 三套语言资源中各 244 条云设备/云硬盘关联文案；移除应用里“硬编已启用”“弱网已启用”等没有运行证据的提示。完整协议和原版媒体库中的历史代码仍保留，未声称库级剥离完成。

## 边界

Ghidra 对 macOS 13MB dylib 的默认自动分析在 330 秒触发 provider_timeout，未产生完整伪代码。保留此覆盖缺口；使用有文件哈希和地址的 ARM64 静态反汇编核对工厂/版本函数，不把它称作完整反编译。当前 Linux 主机不能运行 macOS/Windows UI，原包没有提供登录凭据、真实会话流量和物理采集设备，CI 冒烟测试也不能证明端到端或逐像素一致。
