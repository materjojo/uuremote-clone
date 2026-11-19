# UURemoteClone

对 **网易UU远程 macOS 4.48.1 (build 633)** 的协议级复刻实现。私有工程，仅用于研究与互操作。

- 逆向报告：[docs/01-architecture.md](docs/01-architecture.md) · [02-protocol.md](docs/02-protocol.md) · [03-media.md](docs/03-media.md) · [04-ui.md](docs/04-ui.md)
- 协议定义：[proto/gv_pb.proto](proto/gv_pb.proto)
- 已移除：云设备（CloudPC / CloudDisk）全部功能

## 构建

```bash
swift build -c release
bash scripts/make_app.sh
```

CI：GitHub Actions `macos-14`，产物 `UURemoteClone.app`。

## 状态

| 模块 | 状态 |
|---|---|
| protobuf 编解码 | ✅ 与官方字段编号一致 |
| HTTP / Socket.IO 信令 | ✅ 客户端实现 |
| WebRTC 媒体 + DataChannel | ✅ |
| 被控端采集 / 注入 | ✅ ScreenCaptureKit + CGEvent |
| UI（设备/远控/设置） | ✅ 结构还原，图标占位 |
| H.265 / KCP / 私有屏 | ❌ 见文档 |
