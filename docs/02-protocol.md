# UU远程 macOS 4.48.1 逆向分析（二）：通信协议

> 本文所有字段名、字段编号、枚举取值均从 `UURemote` 二进制的 Swift 类型元数据与
> SwiftProtobuf name-map 表直接还原，非猜测。消息类型命名空间为 `gv_pb`。

---

## 1. 协议分层

| 层 | 载体 | 内容 | 证据 |
|---|---|---|---|
| L1 业务 API | HTTPS/HTTP2 | 登录、设备、房间、版本、埋点 | `api.nrd.nie.163.com`、59 个 `/api/v1|2/…` |
| L2 信令 | Socket.IO v4 (Engine.IO 4) over WSS | SDP、ICE、房间事件、QoS | `?EIO=4&transport=websocket`、`WebSocket++/0.8.2` |
| L3 媒体 | WebRTC (ICE + DTLS 1.2 + SRTP) | H.264/H.265 视频、Opus 音频 | `nrd-webrtc`、`dtls1_*`、`srtp` |
| L4 控制 | SCTP/QUIC DataChannel | Protobuf `gv_pb.*` | `CONTROL_DATA_CHANNEL`、`_protobuf_nameMap` |
| L5 安全 | TLS 1.2/1.3, DTLS-SRTP | 证书校验可配置 | `tls_verify_host`、`sni_enabled` |

## 2. 业务 API（节选，共 59 条）

### 2.1 账号
```
POST /api/v1/login/by_mobile        POST /api/v1/login/by_email
POST /api/v1/login/by_qrcode        POST /api/v1/qrcode/gen/login
POST /api/v1/qrcode/login/status    GET  /api/v1/user/info
POST /api/v1/user/logout            POST /api/v1/user/verify/realname
POST /api/v1/security/mobile/code   POST /api/v1/security/email/verification/code
POST /api/v1/security/client_lock/send_code  /reset
```

### 2.2 设备与房间
```
GET  /api/v1/device/list            GET  /api/v1/device/groups/of/my
GET  /api/v1/device/mac_controllable
POST /api/v1/device/preferences     POST /api/v1/device/macos/init
POST /api/v1/device/wake_on_lan/info
POST /api/v1/room/create            POST /api/v1/room/join/refetch
POST /api/v1/room/join/share/by_code
POST /api/v1/guest/room/create      POST /api/v1/guest/create
POST /api/v2/room/share/control_mode
```

`room/create` 响应中与流媒体直接相关的字段（从 Codable 键还原）：

```
signaling_server            // 首选信令服务器 URL
signaling_list[]            // 备用信令列表
sni_required_signaling_list[]  // 需要 SNI 的信令
publisher_device_id         // 被控端设备 id
publisher_platform          // windows / mac / android …
publisher_version_name
ws_connect_timeout_ms       // Socket.IO 连接超时
max_reconnect_delta         // 重连退避上限
streamer_config             // JSON（见 streamer-config.json）
streamer_retry_delta_ms
report_token / report_url / report_server_address
international_connect       // 海外线路标记
device_binding
```

### 2.3 云设备（复刻时移除）
```
POST /api/v1/cloud_pc/create        GET /api/v1/cloud_pc/features
GET  /api/v1/cloud_pc/disks         GET  /api/v1/cloud_pc/network/speed
GET  /api/v1/device/cloud_pc/list   GET /api/v1/cloud_disk/consumption
```

## 3. 信令层（Socket.IO / Engine.IO 4）

连接串：

```
wss://{signaling_host}/socket.io/?EIO=4&transport=websocket&t={timestamp}
（重连时追加 &sid={session_id}）
```

引擎包格式为标准 EIO4：`0{json}` OPEN、`2` PING、`3` PONG、`40` CONNECT、`42["event",payload]` EVENT、`43` ACK。
二进制事件使用 `45` 前缀（`45{attachments}-{json}`）。

### 3.1 事件表（从 `libstreamer` 的字符串常量还原）

| 方向 | 事件名 | 载荷 | 说明 |
|---|---|---|---|
| C→S | `send_offer` | SDP（JSON: type/sdp/session） | 控制端发起 Offer |
| C→S | `send_candidates` | ICE candidate 数组 | trickle ICE |
| C→S | `restart_ice` | — | ICE 重启 |
| C→S | `qos_stats_upload` | 统计 JSON | 每秒 QoS |
| C→S | `auto_frame_quality` | 画质切换结果 | 自适应画质 |
| C→S | `ice_connection_timeout` | — | 连接超时上报 |
| C→S | `streamer_data_channel_event` | DataChannel 状态 | 通道就绪 |
| S→C | `bmsg_push` | 信令消息（offer/answer/candidate 等） | 服务端推送 |
| S→C | `room_info` | 房间信息 | 登录后下发 |
| S→C | `publisher_disconnect` | 被控端断开 | 会话终止 |
| S→C | `streamer_notification` / `streamer_error` | 状态/错误 | UI 提示 |

> `bmsg_push` 内层带 `type` 字段（`send_offer`/`answer`/`candidate`/`restart_ice`），
> 由 `OnControllerPush parse json` 分支处理。

### 3.2 连接时序

```
控制端                                     被控端
  │ POST /api/v1/room/create                 │
  │◄── room_id, token, signaling_list        │
  │ Socket.IO connect                        │
  │ emit login(token) ──────────────────────►│
  │◄─ room_info (peer 上线, feature flags) ──│
  │ createOffer → emit send_offer ──────────►│
  │◄────────────── bmsg_push(type=answer) ───│
  │ emit send_candidates ◄──────────────────►│  (双向 trickle)
  │ ══════ DTLS-SRTP 建立，DataChannel OPEN ══│
  │ CONTROL: ConnectOptions ────────────────►│
  │◄──────────── CaptureSettingResponse ─────│
  │◄════════════ 视频 RTP (H264/H265) ═══════│
  │ CONTROL: InputEvent(TouchEvent) ────────►│
```

## 4. 控制层（Protobuf）

### 4.1 封装

DataChannel 为消息型通道，**一个 SCTP 消息 = 一个完整 `gv_pb.Message`**（无额外长度前缀）。

```protobuf
message Message {
  int64  seq       = 1;
  int64  timestamp = 2;
  oneof payload {
    SimpleAction        simple_action         = 3;
    LaunchApp           launch_app            = 4;
    ShowApp             show_app              = 5;
    MumuOperate         mumu_operate          = 6;
    ScreenSources       screens               = 7;
    CaptureChange       capture_change        = 8;
    CaptureConfig       capture_config        = 9;
    RomMessage          rom_message           = 10;
    SendToRom           send_to_rom           = 11;
    ReportError         report_error          = 12;
    SystemMetrics       system_metrics        = 13;
    ReportQosStats      report_qos_stats      = 14;
    SystemStateChange   system_state_change   = 15;
    QuerySystemState    query_system_state    = 16;
    ClipboardChange     clipboard_change      = 17;
    CodecNegotiation    codec_negotiation     = 18;
    CaptureConfigResponse capture_config_response = 19;
    InputEvent          input_event           = 20;
    RpcRequest          rpc_request           = 21;
    RpcResponse         rpc_response          = 22;
    ActiveWindowChange  active_window_change  = 23;
    LaunchCloudPcApp    launch_cloud_pc_app   = 24;   // 移除
    CaptureSettingSync  capture_setting_sync  = 25;
    RemoteDownloadPath  remote_download_path  = 26;
    PortMappingFrame    port_mapping_frame    = 27;
    TerminalSessionChanged terminal_session_changed = 28;
  }
}
```

### 4.2 握手

```protobuf
message ConnectOptions {          // 控制端 → 被控端，首个 CONTROL 消息
  CaptureMode        capture_type        = 1;
  int32              type_value          = 2;
  CaptureParams      capture_params      = 3;
  repeated DecoderCap decoder_cap_list   = 4;
  bool               force_virtual_display = 5;
  repeated VirtualDisplayMode virtual_display_modes = 6;
  VirtualDisplayInitResolution virtual_display_init_resolution = 7;
  ClientType         client_type         = 8;   // clientMac = 4
  string             device_id           = 9;
  ControlConnectType control_connect_type = 10;  // normal / assistance
  FeatureFlag        feature_flag        = 11;
  string             client_version      = 12;
  string             entitlement_data    = 13;
  int64              current_server_time = 14;
}

message CaptureParams {
  int32  fps                    = 1;
  VideoQuality video_quality    = 2;   // fast=1 general=2 hd=3 bluray=4 auto=5 custom=6
  bool   cursor_capture         = 3;
  ChooseResolutionType choose_resolution_type = 4;
  Resolution local_resolution   = 5;
  Resolution choose_resolution  = 6;
  ChromaFormat chroma_format    = 7;
  int32  max_custom_bitrate     = 8;
  bool   enable_hdr             = 9;
  bool   auto_frame_quality     = 10;
  int32  fpsCount               = 11;
}
```

```protobuf
message DecoderCap { int32 fps = 1; CodecType codec_type = 2;
                     int32 resolution_width = 3; int32 resolution_height = 4;
                     ChromaFormat chroma_format = 5; }
message EncoderCap { CaptureMode capture_mode = 1; int32 fps = 2;
                     CodecType corec_type = 3;  // 原始拼写 corec
                     int32 resolution_width = 4; int32 resolution_height = 5; }
message CodecNegotiation { repeated EncoderCap encoder_cap_list = 1; }
```

### 4.3 输入

```protobuf
message InputEvent { TouchEvent touch_event = 1; }

message TouchEvent {
  TouchEventType event_type = 1;   // UNDEFINED=0 START=1 MOVE=2 END=3 CANCEL=4
  repeated TouchEventPoint touch_points = 2;
}

message TouchEventPoint {
  int32  id       = 1;
  float  x        = 2;   // 归一化 0..1（按屏幕宽）
  float  y        = 3;
  float  radius_x = 4;
  float  radius_y = 5;
  float  angle    = 6;
  float  pressure = 7;
}
```

### 4.4 屏幕与画质

```protobuf
message Screen {
  int32 id = 1;  int32 fps = 2;
  repeated Resolution resolutions = 3;  Resolution current_resolution = 4;
  ScreenType screen_type = 5;           // physics=0 virtual=1 super=2
  Resolution init_resolution = 6;
  bool is_primary_screen = 7;  double dpr = 8;  DpiScale dpi_scale = 9;
  string display_name = 10;  ChooseResolutionType resolution_type = 11;
  int32 video_track_index = 12;  BuiltinScreenType builtin_screen_type = 13;
}
message ScreenSources { repeated Screen screens = 1; int32 current_screen_id = 2; }

message CaptureSettingRequest {   // 控制端动态改画质
  int32 fps = 1; VideoQuality frame_quality = 2; bool cursor_capture = 3;
  int32 screen_id = 4; int32 resolution_width = 5; int32 resolution_height = 6;
  ChromaFormat chorma_format = 7;  // 原始拼写 chorma
  int32 max_custom_bitrate = 8;  int32 dpi_scale = 9;
  ChooseResolutionType resolution_type = 10;  bool enable_hdr = 11;
  VideoQuality auto_frame_quality = 12;  CodecType codec_type = 13;
  int32 max_scale_width = 14;  int32 max_scale_height = 15;
  int32 resolution_pixel_width = 16;  int32 resolution_pixel_height = 17;
  int32 fpsCount = 18;
}
```

### 4.5 系统状态

```protobuf
message SystemStateChange {
  oneof which {
    SdState sd_state = 1;
    CursorShape cursor_shape = 2;
    PermissionState permission_state = 3;
    RemoteAssistFileTransferState remote_assist_file_transfer_state = 4;
    PrivateScreenState private_screen_state = 5;
    ClientUiReadyState client_ui_ready_state = 6;
  }
}
message CursorShape {
  int32 pos_x = 1; int32 pos_y = 2; int32 width = 3; int32 height = 4;
  bytes byte_value = 5; int32 cursor_type = 6;
  double coordinate_x_scale = 7; double coordinate_y_scale = 8; int32 screen_id = 9;
}
```

### 4.6 特征位

```protobuf
message FeatureFlag {
  FF_CaptureSetting ff_capture_setting = 1;   // initVerion / autoCreateVirtualDisplay / chromaSampling / customBitrate / dpiScale / hdr
  FF_SimpleAction   ff_simple_action   = 2;   // muting / autoLock / stopStreaming
  FF_SystemMetrics  ff_system_metrics  = 3;
  FF_PrivateScreenSetting ff_private_screen = 4;
  FF_UpdateAcquire  ff_update_acquire  = 5;
  FF_FileTransfer_FTP  ff_file_transfer_ftp  = 6;
  FF_FileTransfer_FTP2 ff_file_transfer_ftp2 = 7;   // resumable / speedy
  FF_Clipboard      ff_clipboard       = 8;   // supportFile / supportTextChange
  FF_Qos_Stat       ff_qos_stat        = 9;
  MuMu_Control      ff_mumu_control    = 10;
  Virtual_Mouse_Device ff_virtual_mouse_device = 11;
}
```

## 5. 完整消息清单（160 条已还原字段编号）

从元数据还原并完成 name-map 对齐的消息共 160 条，覆盖：

- 剪贴板：`ClipboardFormat(List|DataAsk)`、`ClipboardDataBlock`、`ClipboardFile*`、`ClipboardTextChange*`
- 文件传输：`FileTransfer(Send|Receive|Ask|Block|Confirm|Complete|Result)`、`FileList/DirCreate/Rename/Remove*`、`ReadDir`
- 绘图标注：`DrawRequest/Response`、`DrawStroke/Clear/Toggle`、`DrawPoint`
- 终端：`TerminalSessionChanged`、`RenameSessionReq/Resp`
- 外设：`VirtualMouseSwitch*`、`ActionKeyToggle`、`MuMu_Control`
- 端口映射：`PortMappingFrame`
- RPC：`RpcRequest/RpcResponse` + `RequestHeader/ResponseHeader`（`PbRpcManager`）

原始清单见 `analysis/derived/schema_matched.json`（含每条消息的字段编号、proto 名、Swift 属性名、类型线索）。

## 6. 传输语义

| 通道 label | 内容 | 保证 |
|---|---|---|
| `CONTROL_DATA_CHANNEL` | `gv_pb.Message` | 可靠有序 |
| `BINARY_DATA_CHANNEL` | 大块二进制（剪贴板图片/文件片段） | 可靠 |
| `FILE_DATA_CHANNEL` | `gv_pb.FileTransfer*` | 可靠 |
| `internal_data_channel` | 内部保活/统计 | — |

日志中的 `dc_msg_bytes_proto_kcp_sent`、`dc_pro_kcp_rsfec_*` 表明：控制数据在 DataChannel 之上还有一层
**KCP + RS-FEC** 的可选可靠传输（弱网增强），由 `port_mapping_frame`/`rpc` 复用。

## 7. 与 UI 的对应关系

- `ControllerConnectRoom`：房间状态机（`startConnect → loginRoom → connect`）
- `PbRpcManager`：请求/响应复用（`pbRpcRequestId`）
- `StreamerReceiveMessageType` / `RoomMessageType`：回调分发枚举
- 连接状态码：`kControllerPeerDisconnected/Connecting/Offer/Answer/ExchangeCandidate/Connected/Error/Unavailable(reason:)`
