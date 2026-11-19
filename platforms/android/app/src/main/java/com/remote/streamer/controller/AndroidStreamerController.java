// Recovered from the supplied 4.48.1 APK; see analysis/official/android.
package com.remote.streamer.controller;

import com.remote.streamer.model.AudioCaptureConfig;
import com.remote.streamer.model.AudioRendererConfig;
import com.remote.streamer.model.IceNetworkConfig;
import com.remote.streamer.model.StreamerRoomConfig;
import com.remote.streamer.model.VideoRendererConfig;
import java.nio.ByteBuffer;

public final class AndroidStreamerController extends StreamerController {
    static { com.remote.streamer.OfficialLibraries.load(); }

    private final native int Connect(long j, ByteBuffer byteBuffer, String str, String str2);

    private final native int Disconnect(long j);

    private final native int ExitRoom(long j);

    private final native int Finalize();

    private final native int GetConnectionStats(long j);

    private final native String GetDecodeCapability();

    private final native String GetStreamerVersion();

    private final native int Initialize(String str, String str2);

    private final native long LoginRoom(StreamerRoomConfig streamerRoomConfig);

    private final native int SendBinaryData(long j, ByteBuffer byteBuffer);

    private final native int SendControlData(long j, ByteBuffer byteBuffer);

    private final native int SendFileData(long j, ByteBuffer byteBuffer);

    private final native int SendTextData(long j, ByteBuffer byteBuffer);

    private final native int StartAudioCapture(long j, AudioCaptureConfig audioCaptureConfig);

    private final native int StartAudioRender(long j, AudioRendererConfig audioRendererConfig);

    private final native int StartVideoRender(long j, VideoRendererConfig videoRendererConfig);

    private final native int StopAudioCapture(long j, int i10);

    private final native int StopAudioRender(long j, int i10);

    private final native int StopVideoRender(long j, int i10);

    private final native int SwitchIceNetwork(long j, IceNetworkConfig iceNetworkConfig);

    @Override // com.remote.streamer.controller.StreamerController
    public int connect(long j, byte[] bArr, String str, String str2) {
        java.util.Objects.requireNonNull(bArr, "config");
        java.util.Objects.requireNonNull(str, "appControlId");
        java.util.Objects.requireNonNull(str2, "timezone");
        ByteBuffer byteBufferAllocateDirect = ByteBuffer.allocateDirect(bArr.length);
        byteBufferAllocateDirect.put(bArr);
        byteBufferAllocateDirect.flip();
        return Connect(j, byteBufferAllocateDirect, str, str2);
    }

    @Override // com.remote.streamer.controller.StreamerController
    public int disconnect(long j) {
        return Disconnect(j);
    }

    @Override // com.remote.streamer.controller.StreamerController
    public int exitRoom(long j) {
        return ExitRoom(j);
    }

    @Override // com.remote.streamer.controller.StreamerController
    public int shutdown() {
        return Finalize();
    }

    @Override // com.remote.streamer.controller.StreamerController
    public int getConnectionStats(long j) {
        return GetConnectionStats(j);
    }

    @Override // com.remote.streamer.controller.StreamerController
    public String getDecodeCapability() {
        return GetDecodeCapability();
    }

    @Override // com.remote.streamer.controller.StreamerController
    public String getStreamerVersion() {
        return GetStreamerVersion();
    }

    @Override // com.remote.streamer.controller.StreamerController
    public int initialize(String str, String str2) {
        java.util.Objects.requireNonNull(str, "logPath");
        java.util.Objects.requireNonNull(str2, "configPath");
        return Initialize(str, str2);
    }

    @Override // com.remote.streamer.controller.StreamerController
    public long loginRoom(StreamerRoomConfig streamerRoomConfig) {
        java.util.Objects.requireNonNull(streamerRoomConfig, "config");
        return LoginRoom(streamerRoomConfig);
    }

    @Override // com.remote.streamer.controller.StreamerController
    public int sendBinaryData(long j, byte[] bArr) {
        java.util.Objects.requireNonNull(bArr, "data");
        ByteBuffer byteBufferAllocateDirect = ByteBuffer.allocateDirect(bArr.length);
        byteBufferAllocateDirect.put(bArr);
        byteBufferAllocateDirect.flip();
        return SendBinaryData(j, byteBufferAllocateDirect);
    }

    @Override // com.remote.streamer.controller.StreamerController
    public int sendControlData(long j, byte[] bArr) {
        java.util.Objects.requireNonNull(bArr, "data");
        ByteBuffer byteBufferAllocateDirect = ByteBuffer.allocateDirect(bArr.length);
        byteBufferAllocateDirect.put(bArr);
        byteBufferAllocateDirect.flip();
        return SendControlData(j, byteBufferAllocateDirect);
    }

    @Override // com.remote.streamer.controller.StreamerController
    public int sendFileData(long j, byte[] bArr) {
        java.util.Objects.requireNonNull(bArr, "data");
        ByteBuffer byteBufferAllocateDirect = ByteBuffer.allocateDirect(bArr.length);
        byteBufferAllocateDirect.put(bArr);
        byteBufferAllocateDirect.flip();
        return SendFileData(j, byteBufferAllocateDirect);
    }

    @Override // com.remote.streamer.controller.StreamerController
    public int sendTextData(long j, byte[] bArr) {
        java.util.Objects.requireNonNull(bArr, "data");
        ByteBuffer byteBufferAllocateDirect = ByteBuffer.allocateDirect(bArr.length);
        byteBufferAllocateDirect.put(bArr);
        byteBufferAllocateDirect.flip();
        return SendTextData(j, byteBufferAllocateDirect);
    }

    @Override // com.remote.streamer.controller.StreamerController
    public int startAudioCapture(long j, AudioCaptureConfig audioCaptureConfig) {
        java.util.Objects.requireNonNull(audioCaptureConfig, "config");
        return StartAudioCapture(j, audioCaptureConfig);
    }

    @Override // com.remote.streamer.controller.StreamerController
    public int startAudioRender(long j, AudioRendererConfig audioRendererConfig) {
        java.util.Objects.requireNonNull(audioRendererConfig, "config");
        return StartAudioRender(j, audioRendererConfig);
    }

    public final int startVideoRender(long j, VideoRendererConfig videoRendererConfig) {
        java.util.Objects.requireNonNull(videoRendererConfig, "config");
        return StartVideoRender(j, videoRendererConfig);
    }

    @Override // com.remote.streamer.controller.StreamerController
    public int stopAudioCapture(long j, int i10) {
        return StopAudioCapture(j, i10);
    }

    @Override // com.remote.streamer.controller.StreamerController
    public int stopAudioRender(long j, int i10) {
        return StopAudioRender(j, i10);
    }

    @Override // com.remote.streamer.controller.StreamerController
    public int stopVideoRender(long j, int i10) {
        return StopVideoRender(j, i10);
    }

    @Override // com.remote.streamer.controller.StreamerController
    public int switchIceNetwork(long j, IceNetworkConfig iceNetworkConfig) {
        java.util.Objects.requireNonNull(iceNetworkConfig, "config");
        return SwitchIceNetwork(j, iceNetworkConfig);
    }
}
