package com.example.uuremote;

import android.content.Context;
import android.content.Intent;
import android.media.projection.MediaProjection;
import android.os.Handler;
import android.os.Looper;
import org.webrtc.*;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Locale;

/** Independent native WebRTC path. Proprietary streamer parity remains separate. */
public class StreamerSession {
    public interface Listener {
        void onOffer(String sdp);
        default void onAnswer(String sdp) { }
        void onCandidate(IceCandidate candidate);
        void onControl(byte[] data);
        void onState(String state);
        default void onVideo(VideoTrack track) { }
        default void onError(String error) { onState("失败：" + error); }
    }
    private final Listener listener;
    private final PeerConnectionFactory factory;
    private final EglBase egl = EglBase.create();
    private final Handler main = new Handler(Looper.getMainLooper());
    private PeerConnection peer;
    private DataChannel control, binary, file;
    private boolean remoteReady, overlayScheduled, overlayEnabled;
    private volatile boolean closed;
    private final List<IceCandidate> pending = new ArrayList<>(), overlay = new ArrayList<>();
    private VideoCapturer capturer;
    private SurfaceTextureHelper texture;
    private VideoSource source;
    private VideoTrack localTrack;

    public StreamerSession(Context context, Listener listener) {
        this.listener = listener;
        PeerConnectionFactory.initialize(PeerConnectionFactory.InitializationOptions.builder(context.getApplicationContext()).createInitializationOptions());
        factory = PeerConnectionFactory.builder()
                .setVideoEncoderFactory(new DefaultVideoEncoderFactory(egl.getEglBaseContext(), true, true))
                .setVideoDecoderFactory(new DefaultVideoDecoderFactory(egl.getEglBaseContext()))
                .createPeerConnectionFactory();
    }
    public EglBase.Context eglContext() { return egl.getEglBaseContext(); }
    private void createPeer(boolean host) {
        List<PeerConnection.IceServer> servers = Arrays.asList(
                PeerConnection.IceServer.builder("stun:stun.cloudflare.com:3478").createIceServer(),
                PeerConnection.IceServer.builder("stun:stun.l.google.com:19302").createIceServer());
        PeerConnection.RTCConfiguration config = new PeerConnection.RTCConfiguration(servers);
        config.sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN;
        config.continualGatheringPolicy = PeerConnection.ContinualGatheringPolicy.GATHER_CONTINUALLY;
        peer = factory.createPeerConnection(config, new PeerConnection.Observer() {
            @Override public void onSignalingChange(PeerConnection.SignalingState state) { }
            @Override public void onIceConnectionChange(PeerConnection.IceConnectionState state) {
                main.post(() -> { if (!closed) listener.onState(state.name()); });
            }
            @Override public void onIceConnectionReceivingChange(boolean receiving) { }
            @Override public void onIceGatheringChange(PeerConnection.IceGatheringState state) { }
            @Override public void onIceCandidate(IceCandidate candidate) { main.post(() -> emitCandidate(candidate)); }
            @Override public void onIceCandidatesRemoved(IceCandidate[] candidates) { }
            @Override public void onAddStream(MediaStream stream) { if (!stream.videoTracks.isEmpty()) video(stream.videoTracks.get(0)); }
            @Override public void onRemoveStream(MediaStream stream) { }
            @Override public void onDataChannel(DataChannel channel) { main.post(() -> bind(channel)); }
            @Override public void onRenegotiationNeeded() { }
            @Override public void onAddTrack(RtpReceiver receiver, MediaStream[] streams) {
                if (receiver.track() instanceof VideoTrack) video((VideoTrack) receiver.track());
            }
            @Override public void onTrack(RtpTransceiver transceiver) {
                if (transceiver.getReceiver().track() instanceof VideoTrack) video((VideoTrack) transceiver.getReceiver().track());
            }
        });
        if (peer == null) throw new IllegalStateException("无法创建 WebRTC 连接");
        if (!host) peer.addTransceiver(MediaStreamTrack.MediaType.MEDIA_TYPE_VIDEO,
                new RtpTransceiver.RtpTransceiverInit(RtpTransceiver.RtpTransceiverDirection.RECV_ONLY));
    }
    private void video(VideoTrack track) { main.post(() -> { if (!closed) listener.onVideo(track); }); }
    public void start() {
        createPeer(false);
        DataChannel.Init init = new DataChannel.Init(); init.ordered = true;
        bind(peer.createDataChannel("CONTROL_DATA_CHANNEL", init));
        bind(peer.createDataChannel("BINARY_DATA_CHANNEL", init));
        bind(peer.createDataChannel("FILE_DATA_CHANNEL", init));
        peer.createOffer(new Observer() {
            @Override public void onCreateSuccess(SessionDescription sdp) {
                if (closed) return;
                peer.setLocalDescription(new Observer() { @Override public void onSetSuccess() {
                    main.post(() -> { if (!closed) listener.onOffer(sdp.description); });
                } }, sdp);
            }
        }, new MediaConstraints());
    }
    /** Call only after MediaProjection consent and the foreground service started. */
    public void prepareHost(Context context, Intent consent, int width, int height) {
        prepareHost(context, new ScreenCapturerAndroid(consent, new MediaProjection.Callback() {
            @Override public void onStop() { main.post(() -> { if (!closed) listener.onError("屏幕共享已停止"); }); }
        }), width, height);
    }
    /** Capture abstraction also permits synthetic frames in a real native peer test. */
    public void prepareHost(Context context, VideoCapturer input, int width, int height) {
        createPeer(true);
        capturer = input;
        texture = SurfaceTextureHelper.create("UU-screen-capture", egl.getEglBaseContext());
        source = factory.createVideoSource(input.isScreencast());
        capturer.initialize(texture, context.getApplicationContext(), source.getCapturerObserver());
        localTrack = factory.createVideoTrack("screen0", source);
        peer.addTrack(localTrack, Arrays.asList("screen"));
        capturer.startCapture(width, height, 30);
    }
    public void handleOffer(String text) {
        peer.setRemoteDescription(new Observer() { @Override public void onSetSuccess() {
            main.post(() -> {
                if (closed) return;
                ready();
                peer.createAnswer(new Observer() { @Override public void onCreateSuccess(SessionDescription sdp) {
                    if (closed) return;
                    peer.setLocalDescription(new Observer() { @Override public void onSetSuccess() {
                        main.post(() -> { if (!closed) listener.onAnswer(sdp.description); });
                    } }, sdp);
                } }, new MediaConstraints());
            });
        } }, new SessionDescription(SessionDescription.Type.OFFER, text));
    }
    public void setRemoteAnswer(String sdp) {
        peer.setRemoteDescription(new Observer() { @Override public void onSetSuccess() { main.post(() -> { if (!closed) ready(); }); } },
                new SessionDescription(SessionDescription.Type.ANSWER, sdp));
    }
    private void ready() { remoteReady = true; for (IceCandidate c : pending) peer.addIceCandidate(c); pending.clear(); }
    public void addCandidate(IceCandidate c) { if (closed) return; if (remoteReady) peer.addIceCandidate(c); else pending.add(c); }
    static boolean isOverlay(String candidate) {
        String[] fields = candidate.split(" +"); if (fields.length < 5) return false;
        if (fields[4].toLowerCase(Locale.ROOT).startsWith("fd7a:115c:a1e0:")) return true;
        String[] ip = fields[4].split("\\.");
        try { return ip.length == 4 && Integer.parseInt(ip[0]) == 100 && Integer.parseInt(ip[1]) >= 64 && Integer.parseInt(ip[1]) <= 127; }
        catch (NumberFormatException e) { return false; }
    }
    private void emitCandidate(IceCandidate c) {
        if (closed) return;
        if (isOverlay(c.sdp) && !overlayEnabled) {
            overlay.add(c);
            if (!overlayScheduled) {
                overlayScheduled = true;
                main.postDelayed(() -> {
                    if (closed || peer.iceConnectionState() == PeerConnection.IceConnectionState.CONNECTED ||
                            peer.iceConnectionState() == PeerConnection.IceConnectionState.COMPLETED) return;
                    overlayEnabled = true;
                    for (IceCandidate candidate : overlay) listener.onCandidate(candidate);
                    overlay.clear();
                }, 8000);
            }
        } else listener.onCandidate(c);
    }
    private void bind(DataChannel channel) {
        if (channel == null || closed) return;
        if (channel.label().equals("CONTROL_DATA_CHANNEL")) control = channel;
        if (channel.label().equals("BINARY_DATA_CHANNEL")) binary = channel;
        if (channel.label().equals("FILE_DATA_CHANNEL")) file = channel;
        channel.registerObserver(new DataChannel.Observer() {
            @Override public void onBufferedAmountChange(long previous) { }
            @Override public void onStateChange() { }
            @Override public void onMessage(DataChannel.Buffer buffer) {
                if (!channel.label().equals("CONTROL_DATA_CHANNEL")) return;
                byte[] data = new byte[buffer.data.remaining()]; buffer.data.get(data);
                main.post(() -> { if (!closed) listener.onControl(data); });
            }
        });
    }
    public void sendControl(byte[] data) {
        if (!closed && control != null && control.state() == DataChannel.State.OPEN)
            control.send(new DataChannel.Buffer(ByteBuffer.wrap(data), true));
    }
    public void stop() {
        if (closed) return; closed = true;
        main.removeCallbacksAndMessages(null);
        if (capturer != null) { try { capturer.stopCapture(); } catch (Exception ignored) { } capturer.dispose(); }
        if (localTrack != null) localTrack.dispose();
        if (source != null) source.dispose();
        if (texture != null) texture.dispose();
        if (control != null) { control.unregisterObserver(); control.close(); control.dispose(); }
        if (binary != null) { binary.unregisterObserver(); binary.close(); binary.dispose(); }
        if (file != null) { file.unregisterObserver(); file.close(); file.dispose(); }
        if (peer != null) { peer.close(); peer.dispose(); }
        factory.dispose(); egl.release();
        peer = null;
    }
    private class Observer implements SdpObserver {
        @Override public void onCreateSuccess(SessionDescription sdp) { }
        @Override public void onSetSuccess() { }
        @Override public void onCreateFailure(String error) { main.post(() -> { if (!closed) listener.onError(error); }); }
        @Override public void onSetFailure(String error) { main.post(() -> { if (!closed) listener.onError(error); }); }
    }
}
