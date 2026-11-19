package com.example.uuremote;

import android.content.Context;

import org.webrtc.DataChannel;
import org.webrtc.IceCandidate;
import org.webrtc.MediaConstraints;
import org.webrtc.MediaStream;
import org.webrtc.PeerConnection;
import org.webrtc.PeerConnectionFactory;
import org.webrtc.RtpReceiver;
import org.webrtc.RtpTransceiver;
import org.webrtc.SdpObserver;
import org.webrtc.SessionDescription;

import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.List;

/**
 * WebRTC 会话（Android 端）。
 * 通道名与官方一致：CONTROL_DATA_CHANNEL / BINARY_DATA_CHANNEL / FILE_DATA_CHANNEL。
 */
public class StreamerSession {
    public interface Listener {
        void onOffer(String sdp);
        void onCandidate(IceCandidate candidate);
        void onControl(byte[] data);
        void onState(String state);
    }

    private final Context context;
    private final Listener listener;
    private PeerConnectionFactory factory;
    private PeerConnection peer;
    private DataChannel control;
    private DataChannel binary;
    private DataChannel file;

    public StreamerSession(Context context, Listener listener) {
        this.context = context.getApplicationContext();
        this.listener = listener;
    }

    public void start() {
        PeerConnectionFactory.initialize(
                PeerConnectionFactory.InitializationOptions.builder(context).createInitializationOptions());
        factory = PeerConnectionFactory.builder().createPeerConnectionFactory();

        List<PeerConnection.IceServer> servers = new ArrayList<>();
        PeerConnection.RTCConfiguration config = new PeerConnection.RTCConfiguration(servers);
        config.sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN;
        config.continualGatheringPolicy = PeerConnection.ContinualGatheringPolicy.GATHER_CONTINUALLY;

        peer = factory.createPeerConnection(config, new PeerConnection.Observer() {
            @Override public void onSignalingChange(PeerConnection.SignalingState state) {}
            @Override public void onIceConnectionChange(PeerConnection.IceConnectionState state) {
                listener.onState(state.name());
            }
            @Override public void onIceConnectionReceivingChange(boolean receiving) {}
            @Override public void onIceGatheringChange(PeerConnection.IceGatheringState state) {}
            @Override public void onIceCandidate(IceCandidate candidate) {
                listener.onCandidate(candidate);
            }
            @Override public void onIceCandidatesRemoved(IceCandidate[] candidates) {}
            @Override public void onAddStream(MediaStream stream) {}
            @Override public void onRemoveStream(MediaStream stream) {}
            @Override public void onDataChannel(DataChannel dataChannel) {
                bind(dataChannel);
            }
            @Override public void onRenegotiationNeeded() {}
            @Override public void onAddTrack(RtpReceiver receiver, MediaStream[] streams) {}
            @Override public void onTrack(RtpTransceiver transceiver) {}
        });

        // 控制端主动建链
        DataChannel.Init init = new DataChannel.Init();
        init.ordered = true;
        control = peer.createDataChannel("CONTROL_DATA_CHANNEL", init);
        binary = peer.createDataChannel("BINARY_DATA_CHANNEL", init);
        file = peer.createDataChannel("FILE_DATA_CHANNEL", init);
        bind(control);
        bind(binary);
        bind(file);

        MediaConstraints constraints = new MediaConstraints();
        constraints.mandatory.add(new MediaConstraints.KeyValuePair("OfferToReceiveAudio", "true"));
        constraints.mandatory.add(new MediaConstraints.KeyValuePair("OfferToReceiveVideo", "true"));
        peer.createOffer(new SimpleSdpObserver() {
            @Override public void onCreateSuccess(SessionDescription sdp) {
                peer.setLocalDescription(new SimpleSdpObserver(), sdp);
                listener.onOffer(sdp.description);
            }
        }, constraints);
    }

    private void bind(DataChannel channel) {
        if (channel == null) return;
        channel.registerObserver(new DataChannel.Observer() {
            @Override public void onBufferedAmountChange(long previousAmount) {}
            @Override public void onStateChange() {}
            @Override public void onMessage(DataChannel.Buffer buffer) {
                if (!"CONTROL_DATA_CHANNEL".equals(channel.label())) return;
                ByteBuffer data = buffer.data;
                byte[] bytes = new byte[data.remaining()];
                data.get(bytes);
                listener.onControl(bytes);
            }
        });
    }

    public void setRemoteAnswer(String sdp) {
        if (peer == null) return;
        SessionDescription desc = new SessionDescription(SessionDescription.Type.ANSWER, sdp);
        peer.setRemoteDescription(new SimpleSdpObserver(), desc);
    }

    public void addCandidate(IceCandidate candidate) {
        if (peer != null) peer.addIceCandidate(candidate);
    }

    public void sendControl(byte[] data) {
        if (control == null) return;
        control.send(new DataChannel.Buffer(ByteBuffer.wrap(data), true));
    }

    public void stop() {
        if (control != null) control.close();
        if (peer != null) peer.close();
        if (factory != null) factory.dispose();
        peer = null;
        factory = null;
    }

    private static class SimpleSdpObserver implements SdpObserver {
        @Override public void onCreateSuccess(SessionDescription sdp) {}
        @Override public void onSetSuccess() {}
        @Override public void onCreateFailure(String error) {}
        @Override public void onSetFailure(String error) {}
    }
}
