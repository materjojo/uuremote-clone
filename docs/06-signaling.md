# 信令 JSON 是做什么的

> 一句话：**信令 JSON 只负责把两端牵到一起，不承载业务数据**。
> 音视频走 RTP，控制指令走 Protobuf，剪贴板/文件走各自 DataChannel；JSON 只在建立连接前后传递元信息。

---

## 1. 为什么必须有信令

WebRTC 本身不规定如何找到对方。它只定义了两端拿到同一份 SDP 之后怎么加密、怎么打洞、怎么传 RTP。
把 SDP 和 ICE candidate 从 A 送到 B 的这个过程就是信令。官方用 Socket.IO（Engine.IO v4）做这层传输，
所以载荷是 JSON 文本，而不是 Protobuf。

## 2. 帧格式

```
0{json}                     OPEN        服务端下发 sid / pingInterval / pingTimeout
2 / 3                       PING/PONG   心跳（25s 间隔，20s 超时）
40{json}                    CONNECT     进入默认命名空间
42["event", payload]        EVENT       业务事件（本文重点）
43{id}[...]                 ACK         可选确认
45{attachments}-{json}      BINARY      带二进制附件的 JSON（大 SDP 分片时使用）
```

## 3. 各事件的作用

| 事件 | 方向 | 载荷作用 |
|---|---|---|
| login | C→S | 携带 room_id / token，把 Socket 绑定到房间 |
| room_info | S→C | 对端上线、能力位、publisher 信息 |
| send_offer | C→S | **SDP offer**（媒体能力、DTLS 指纹、ICE ufrag/pwd、m-line 布局） |
| send_candidates | C→S | **ICE candidate** 数组（IP:port、类型 host/srflx/prflx/relay） |
| bmsg_push | S→C | 服务端推送：对端 answer、candidate、restart_ice、断开通知 |
| restart_ice | 双向 | 网络切换后重新收集候选 |
| qos_stats_upload | C→S | 每秒 QoS（RTT/丢包/码率/分辨率），用于服务端侧质量看板 |
| auto_frame_quality | C→S | 自适应画质切换结果上报 |
| streamer_data_channel_event | C→S | DataChannel 打开/关闭状态 |
| ice_connection_timeout | C→S | 连接超时埋点 |
| publisher_disconnect | S→C | 被控端掉线，会话结束 |

## 4. 一次连接的 JSON 时序

```
控制端                                    服务端/被控端
  │ 42["login",{room_id,token}]              │
  │ ────────────────────────────────────────►│
  │ ◄──────── 42["room_info",{peer,flags}] ──│
  │ 42["send_offer",{sdp:"v=0…"}]            │
  │ ────────────────────────────────────────►│ ──► 被控端 setRemoteDescription
  │ ◄──────── 42["bmsg_push",{type:"answer",sdp:"v=0…"}]
  │ 42["send_candidates",[{candidate:"candidate:…",sdpMid:"0",sdpMLineIndex:0}]
  │ ◄──────── 42["bmsg_push",{type:"candidate",…}]
  │ ══════════ DTLS 握手 / SRTP 建立 ══════════│
```

## 5. JSON 与控制协议的分工

| 内容 | 通道 | 格式 |
|---|---|---|
| 找对端、交换 SDP/ICE | Socket.IO | JSON |
| 视频/音频 | RTP（SRTP 加密） | H.264/H.265/Opus |
| 输入、屏幕、剪贴板、文件、RPC | DataChannel | Protobuf gv_pb.* |
| 房间列表、设备、版本 | HTTPS | JSON |

因此**信令断了不会丢帧，只会导致重连**；而 DataChannel 断了会直接中断控制。

## 6. 复刻实现

- SocketIOClient.swift：EIO4 解析、ping/pong、42 事件收发
- RemoteSession.swift：send_offer / send_candidates / bmsg_push 处理
- 载荷字段名（sdp/candidate/sdpMid/sdpMLineIndex）按 WebRTC 通用约定与二进制中的 Codable 键还原

> 注意：官方 bmsg_push 的内层字段未做抓包验证，若接入真实服务需要按实际抓包校准
> （通常只差外层包装，例如 {"data":{...}}）。
