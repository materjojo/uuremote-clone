# 独立配对、连接与当前使用边界

三端普通界面现在使用自建 rendezvous 和独立 WebRTC 连接路径，不再要求网易账号、网易业务接口或示例设备。原版 `streamer` 二进制仍被保留和验证，但**普通界面的独立媒体路径尚未改为原版专有媒体会话**。相同 DataChannel 名称、恢复的 protobuf 或同一编解码器名称，都不能证明原版互操作或功能等价。

## 启动信令服务

在你自己的服务器上，从仓库根目录执行：

```sh
python3 -m venv .venv
.venv/bin/pip install -r server/requirements.txt
UU_BIND=127.0.0.1 UU_PORT=8080 .venv/bin/python -m server.rendezvous
```

或者从仓库根目录构建并运行现有 Dockerfile：

```sh
docker build -f server/Dockerfile -t uuremote-signal .
docker run --rm -p 127.0.0.1:8080:8080 uuremote-signal
```

公网使用时，把服务器的 HTTPS 根地址反向代理至 `127.0.0.1:8080`，包括 `/health` 和 `/v1/`。信令轮询最长等待 10 秒，反向代理读取超时须大于这个值。局域网或已有的私有 tailnet 可直接使用相应 HTTP 根地址；HTTP 不加密配对和信令，适合受信任的私网测试。客户端地址必须是根地址，不含用户名、密码、query、fragment 或额外路径，例如 `https://signal.example.org` 或 `http://192.168.1.10:8080`。

此工程没有代为部署一个公共服务，也没有设置默认服务地址。服务只交换同意连接、SDP 和 ICE 候选，不中继屏幕、音频或控制数据。不提供 TURN。浏览器 `GET /health` 返回 `{"protocol":1}` 可以确认根地址和代理路径。代理、服务器和证书由使用者控制；服务器需要被信任，因为它参与 SDP 身份协商。

设备注册、请求和信令保存在服务进程的内存中，重启会清空。重启后，在被控设备上重新关闭/开启接收；本机保存的设备身份和配对记录仍在。空闲请求 10 分钟过期，离线设备记录最多保留一天。服务有请求体、邮箱、设备和会话容量上限，但尚未作为面向不受信任用户的多租户服务进行负载/安全验收。

## 添加真实设备

1. 被控端打开应用，输入自建信令服务根地址，开启“接收远程连接”。Android 的入口在“远程协助”。
2. 在被控端复制“本机配对码”。Windows、macOS、Android 都生成同一个 `uur1.` 版本格式，包含服务地址、设备身份、配对密钥、名称和平台。
3. 主控端选择“添加设备”，粘贴配对码。首次启动设备列表为空；应用不会生成 MacBook、Windows PC 等示例设备。列表中“已配对”不表示当前在线。
4. 主控端点击“远程控制”。被控端每次需确认。Android 随后还会显示系统屏幕共享授权，并运行带“停止共享”操作的前台通知。触控和文本输入需要被控端在系统设置中启用本应用无障碍服务；macOS 输入需要辅助功能权限，屏幕采集需要屏幕录制权限。
5. 使用“断开”或停止接收结束会话。配对码包含可发起请求的凭据，持有者仍需本机同意才能进入会话。当前 UI 尚未提供配对密钥轮换和跨设备账号同步。

所有设备组合在配对和信令层使用同一合同，未限制为固定 Mac→Windows 组合。**这不等于九种主控/被控组合已经在实机验收。** 当前运行证据覆盖各平台原生连接代码的两端回环测试和共享服务测试，见下文。

## 连接次序

三端候选发布使用同一规则：原生 IPv6 立即发布；原生 IPv4 和 mDNS 候选在约 1.2 秒宽限后发布；识别出的 Tailscale 地址 `100.64.0.0/10` 和 `fd7a:115c:a1e0::/48` 在约 8 秒后发布。若已经连接，延迟队列不再发送。SDP 内嵌的候选也经过同一规则，防止绕过延迟的 trickle 消息。代码不修改 WebRTC 的本地描述或候选优先级算法，因此此规则是**候选披露次序**，不是公网环境中绝对固定的最终路由保证。

独立路径使用 Cloudflare 和 Google 公共 STUN 发现地址，并让 ICE 执行连通性检查与打洞。服务可用、对端同意和 STUN 有响应均不保证跨所有 NAT 可直连；对称 NAT、UDP 防火墙和网络策略仍可能使连接失败。公网双 NAT、IPv6 优先路由选择和网络切换尚未实测。

Tailscale 必须先由使用者在两端安装、登录并加入可互通网络。应用不登录 Tailscale、不创建 tailnet，也没有内置 Tailscale 客户端。已有 Tailscale 可承载候选地址间的连接；Tailscale 自身是否走 DERP 由其网络状态决定，尚未在本工程中验证。`100.64.0.0/10` 也是 CGNAT 地址范围，此简单识别会把该范围内的非 Tailscale 原生候选一起延迟；未确认适配器身份是当前限制。

## 媒体与输入

- macOS：ScreenCaptureKit 采集后推送至原生 WebRTC RTP 视频路径。渲染支持 native CVPixelBuffer、NV12、软件 I420 和 BGRA；独立 RTP 路径不再借用未参与编码的 HEVC 实例声称硬件状态。
- Windows：GDI 桌面采集、FFmpeg H.264 编码、SIPSorcery RTP、FFmpeg 解码及 WPF BGRA 显示。当前普通连接使用软件编解码设置，DXGI/WGC 和硬件编码尚未接入。依赖统一为 SIPSorcery / SIPSorceryMedia.FFmpeg 10.0.17；FFmpeg 8.1.1 的 `avcodec-62` shared 库在 Actions 下载并按已固定 SHA-256 校验后打包。
- Android：原生 WebRTC、hardware encoder/decoder factories、SurfaceViewRenderer 和 ScreenCapturerAndroid。工厂允许硬件候选，并不证明指定设备实际选用了硬件；模拟器测试不覆盖真实硬件编解码器。
- 三端控制通道携带恢复的 `gv_pb.Message` 触控和文本剪贴板消息；文本输入使用原 APK `ControllerService.sendText` 中观察到的 UTF-8 JSON `{"action":"text_input","content":...}`。独立应用中的触控消费规则仍需与原版逐项比对。
- 点击按视频实际显示区域归一化，避免把黑边当作远端像素。macOS 拖动时发送拖动事件，并在取消/结束被控会话时释放按键。桌面右键、滚轮、完整快捷键和 Android 连续多指触控仍未完整接入。
- 当前尚未串起系统音频采集/播放、文件传输、交互终端、端口映射和原版完整画质设置。工具条和侧栏中仍有未接入业务的入口，不能作为完成证据。

## 验证与运行记录

编译及需要编译的测试全部在 GitHub Actions 执行。本地只做源码、资源提取、哈希和 XML/生成文件检查。

- 服务 Actions `44657324091`：19 个测试通过，包括经服务 SDP 交换后的真实 ICE/DTLS/SCTP 控制往返及合成 RTP 视频；两端在同一 runner，不是公网 NAT 测试。
- macOS Actions `44670463306`：10 个 Swift 测试通过，包含真实原生 peer 的控制往返与合成视频编码/RTP/解码、渲染格式转换、候选策略以及原版 dylib 工厂/版本；打包与包内文件校验通过。
- Windows Actions `44670938942`：WPF 打包及真实 ICE/DTLS、双向控制、H.264 编码/RTP/解码测试通过，测试检查帧尺寸、通道顺序和已知颜色；不是物理桌面捕获/硬件编码验证。后续 `44671290067` 从该包启动真实首页并生成截图。
- Android Actions `44670528149`：x86_64 Android 11 模拟器启动真实 MainActivity，验证空设备列表、三平台配对码、原生 peer 视频/控制、SDP 候选策略与 8 秒回退生命周期，共 5 项通过，并保存首页截图。原版专有 ARM64 `.so` 不参与此模拟器媒体路径。
- ARM64 APK Actions `44670463306`：应用编译、官方 wrapper 替身测试、237 方法 descriptor / 24 常量对照以及原版三库/配置哈希验证通过。该证据不证明原版 ARM64 native 会话已运行。

后续 Windows 原版专有路径已在 Actions `44911242801` 通过独立本地信令下的两个原库进程、实际双向 binary 和 HWND 窗口采集/编码/解码/渲染；两组 source 图案在 controller 窗口真实呈现，四张位图及[报告和截图来源](../analysis/ci/96cd54e-window-media/evidence.json)保留。该测试尚未接入本页的普通 UI/生产配对服务，fixture 自动授权及测试 CA 不进入生产。它也不建立 H265、物理硬件或跨平台实机结论。

三端候选测试覆盖实际 8 秒 overlay 宽限、重复候选去重、连接后抑制新候选和关闭时中断同一批次余项。完整运行、产物、日志摘录和截图哈希见 [latest-independent-results.json](../analysis/ci/latest-independent-results.json)。截图只证明本次构建实际显示的页面，尚未获得同条件原版运行截图进行像素差分。

## 资源恢复

Android 直接复用同 APK 的 10 个非云设备导航/设备/空状态图，来源和字节哈希见 [ui-resource-reuse.json](../analysis/official/android/ui-resource-reuse.json)。原首页枚举 `f9.S2.<clinit>` 的 smali 明确包含 Device、CloudPc、Assist、Mine，见 [REA 静态记录 ev_26c197c3…](../analysis/official/android/home-tab-enum.json)；结合资源路径用于去云后的导航，未恢复 Compose 的全部布局参数。

Windows Qt5 导入由 REA 静态证据确认，解析同一 `GameViewer.exe` 的 `qRegisterResourceData` 三个参数定位资源表。共恢复 1,381 个节点、1,316 个文件，其中 1,199 个 SVG。`scripts/recover_windows_resources.py` 绑定样本哈希、检查指针边界和解压大小，清单包含完整路径及存储/解压哈希。应用只复用显式选出的 9 个非云 SVG 和 1 个 ICO；SVG 保留原字节，PNG 为 CairoSVG 2 倍栅格化产物。主题中的 `#3A7BFC` 来自原版按钮资源，白色卡片和深色正文也有资源线索。清单保留云资源名称以描述完整样本，应用不打包这些云图。

资源文件和颜色不等于 widget 几何、交互状态或像素一致。macOS `Assets.car` 尚未逐个恢复，原版 UI 三端逐页面对照仍未完成。
