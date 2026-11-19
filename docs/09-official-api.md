# 官方 streamer 库 API 逆向（Windows streamer.dll / macOS libstreamer.dylib）

## 1. 接口工厂模式（两平台同构）

两个官方库都只暴露"接口工厂"，不暴露具体功能函数：

| 平台 | 入口 | 证据 |
|---|---|---|
| Windows | `ExchangeControllerInterface`（ordinal 2）、`ExchangeControlledInterface`（ordinal 3？） | GameViewer.exe 导入表 + Ghidra 入口枚举（共 114 个入口，其余为 Intel IGCL ctl*） |
| macOS | `_ExchangeControllerInterface`、`_ExchangeControlledInterface`、`_OBJC_CLASS_$_MetalView`、`_OBJC_METACLASS_$_MetalView`（dylib 仅这 4 个导出） | LC_SYMTAB 解析 + UURemote 未定义符号 |

## 2. 工厂签名与行为（Ghidra 反编译）

```c
void** ExchangeControlledInterface(void* callbacks);   // callbacks: 16 个函数指针的结构体
void** ExchangeControllerInterface(void* callbacks);   // callbacks: 18 个函数指针的结构体
```

行为：把 callbacks 拷入全局表（被控端 0x18143f160 起 16 槽；控制端 0x18143f1e0 起 18 槽），
返回**静态 vtable**：被控端 `0x1812e5dd0`（23 槽）、控制端 `0x1812e5e90`（21 槽）。

## 3. 回调结构体（来自 UURemote 的 ObjC 类型编码）

```
ControllerCallback: OnReceiveMediaTrack, OnRemoveMediaTrack, OnFrameChange,
  OnReceiveControlData, OnReceiveTextData, OnReceiveFileData, OnReceiveBinaryData,
  OnRoomState, OnSignalPush, OnQosStats, OnNatInfo, OnPeerConnectionState,
  OnConnectionStateCode, OnEventReport, OnDualNegotiateCapability, OnReceiveDataChannel,
  OnSignalData  （17 个；Windows 用 18 槽，最后一个是 OnSignalData/终止符）
ControlledCallback: OnReceiveControlData, OnReceiveTextData, OnReceiveFileData,
  OnReceiveBinaryData, OnRoomState, OnSignalPush, OnQosStats, OnCursorChange,
  OnCaptureFailed, OnMuMuData, OnNewControl, OnPeerConnectionState,
  OnConnectionStateCode, OnEventReport, OnReceiveDataChannel （15 个）
```

## 4. vtable 槽位（Ghidra 实测地址）

被控端 23 槽：`180a2d880…180a2e1e0`（对应 AndroidStreamerControlled 的
CreateRoom/StartVideoCapture/…/SendSignalData 等 18 个方法 + 构造/析构/私有槽）。
控制端 21 槽：`180a2ce20…180a2d770`（对应 AndroidStreamerController 的
LoginRoom/Connect/StartVideoRender/…/SwitchIceNetwork 等）。
逐槽方法名映射的原始反编译见 `analysis/official/ghidra_vtable.txt`。

## 5. 其他发现

- streamer.dll 内嵌 **Intel IGCL**（114 个 ctl* 导出：GPU 温度/风扇/超频/显示配置）——用于云设备的 GPU 信息上报。
- macOS UURemote 以 `@rpath/libstreamer.dylib` 显式链接；dylib 除 2 个工厂 + MetalView 外零导出。
- 版本字符串 `V4.14.2`（streamer 核心版本，与 app 4.48.1 不同）。

## 6. 直调路径结论

- **Android**：官方 `libstreamer-jni.so` 直接导出 48 个 `Java_com_remote_streamer_*`，复制 .so + 同名 Java 类即可直调（零逆向成本）。
- **Windows**：`DllImport("streamer.dll", EntryPoint = "#2")` 调工厂 + 自定义回调结构体 + vtable 指针调用，可实现"直接用官方 DLL"（需运行时放官方 streamer.dll）。
- **macOS**：把官方 dylib 放进 bundle，`dlopen`/链接后调 `ExchangeControllerInterface`，Swift 侧实现回调结构体；渲染可直接用导出的 `MetalView` ObjC 类。

## 7. Android model 字段核对结论

libstreamer-jni.so / libstreamer.so 对字段名做了字符串保护（明文中仅 chromaSampling/width/height 可见），
无法从 .so 静态交叉核对。但 JNI 契约的权威来源就是官方 Java 类本身（jadx 反编译
com/remote/streamer/model/*）：AndroidStreamerControlled/Controller 的 native 方法签名
（CreateRoom(StreamerRoomConfig)→long 等）与 model 字段（VideoCaptureConfig 15 字段，
含 screenSourceType/videoTrackIndex）均直接取自官方反编译产物——契约一致性由定义保证。
运行时验证需真机：加载官方 .so 后调用 Initialize/CreateRoom 即可确认（UnsatisfiedLinkError
即为签名不符）。
