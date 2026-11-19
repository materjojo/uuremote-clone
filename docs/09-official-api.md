# 官方 streamer API 记录更正

当前已核对的契约、输入哈希、原始地址、验证程序和覆盖边界集中在 [11-native-contract.md](11-native-contract.md)。历史反编译仍保存在 [analysis/official/](../analysis/official/)。

早期本页存在以下错误，不能继续作为实现依据：

- Windows 控制端导出实际为 ordinal **3**，被控端为 **2**。现在按导出名称解析。
- Windows callback 数量为 18 / 16；macOS 为 17 / 15。多出的 Windows 槽没有证据表明是终止符，不能将两者混用。
- 返回对象是普通 C 函数指针表；入口没有隐含 this。版本入口在控制端 slot 17、被控端 slot 18。
- Android native 方法是实例方法。配置 getter、继承回调及 Surface / MediaProjection 辅助类也是契约的一部分；仅复制同名字段不足以证明兼容。
- `UnsatisfiedLinkError` 只是可能的链接错误。配置和回调 descriptor 错误也可能在执行时表现为 `NoSuchMethodError`、JNI 异常或 native 崩溃，不能用“没有链接错误”作为端到端通过。
- 三端媒体库存在相似能力和命名，但同版本号或相似 JNI 方法不证明会话参数、信令、回调顺序或硬件路径可跨平台共用。

目前只开放经过静态核对的工厂/版本检查接口，完整原版媒体会话尚未接入应用主流程。
