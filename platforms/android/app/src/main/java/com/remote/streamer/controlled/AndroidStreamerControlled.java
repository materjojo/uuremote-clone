// Recovered from the supplied 4.48.1 APK; see analysis/official/android.
package com.remote.streamer.controlled;

import com.remote.streamer.model.AudioCaptureConfig;
import com.remote.streamer.model.StreamerRoomConfig;
import com.remote.streamer.model.VideoCaptureConfig;

public final class AndroidStreamerControlled extends StreamerControlled {
    static { com.remote.streamer.OfficialLibraries.load(); }

    private final native int CheckAlive();

    private final native int ClearRoom(long j);

    private final native long CreateRoom(StreamerRoomConfig streamerRoomConfig);

    private final native int DestroyRoom(long j);

    private final native int Finalize();

    private final native int GetConnectionStats(long j);

    private final native String GetEncodeCapability();

    private final native String GetStreamerVersion();

    private final native int Initialize(String str, String str2);

    private final native int SendBinaryData(long j, byte[] bArr);

    private final native int SendControlData(long j, byte[] bArr);

    private final native int SendFileData(long j, byte[] bArr);

    private final native int SendSignalData(long j, byte[] bArr);

    private final native int SendTextData(long j, byte[] bArr);

    private final native int StartAudioCapture(long j, AudioCaptureConfig audioCaptureConfig);

    private final native int StartVideoCapture(long j, VideoCaptureConfig videoCaptureConfig);

    private final native int StopAudioCapture(long j, int i10);

    private final native int StopVideoCapture(long j, int i10);

    @Override // com.remote.streamer.controlled.StreamerControlled
    public int checkAlive() {
        return CheckAlive();
    }

    @Override // com.remote.streamer.controlled.StreamerControlled
    public int clearRoom(long j) {
        return ClearRoom(j);
    }

    @Override // com.remote.streamer.controlled.StreamerControlled
    public long createRoom(StreamerRoomConfig streamerRoomConfig) {
        java.util.Objects.requireNonNull(streamerRoomConfig, "config");
        return CreateRoom(streamerRoomConfig);
    }

    @Override // com.remote.streamer.controlled.StreamerControlled
    public int destroyRoom(long j) {
        return DestroyRoom(j);
    }

    @Override // com.remote.streamer.controlled.StreamerControlled
    public int shutdown() {
        return Finalize();
    }

    @Override // com.remote.streamer.controlled.StreamerControlled
    public int getConnectionStats(long j) {
        return GetConnectionStats(j);
    }

    @Override // com.remote.streamer.controlled.StreamerControlled
    public String getEncodeCapability() {
        return GetEncodeCapability();
    }

    @Override // com.remote.streamer.controlled.StreamerControlled
    public String getStreamerVersion() {
        return GetStreamerVersion();
    }

    @Override // com.remote.streamer.controlled.StreamerControlled
    public int initialize(String str, String str2) {
        java.util.Objects.requireNonNull(str, "logPath");
        java.util.Objects.requireNonNull(str2, "configPath");
        return Initialize(str, str2);
    }

    @Override // com.remote.streamer.controlled.StreamerControlled
    public int sendBinaryData(long j, byte[] bArr) {
        java.util.Objects.requireNonNull(bArr, "data");
        return SendBinaryData(j, bArr);
    }

    @Override // com.remote.streamer.controlled.StreamerControlled
    public int sendControlData(long j, byte[] bArr) {
        java.util.Objects.requireNonNull(bArr, "data");
        return SendControlData(j, bArr);
    }

    @Override // com.remote.streamer.controlled.StreamerControlled
    public int sendFileData(long j, byte[] bArr) {
        java.util.Objects.requireNonNull(bArr, "data");
        return SendFileData(j, bArr);
    }

    @Override // com.remote.streamer.controlled.StreamerControlled
    public int sendSignalData(long j, byte[] bArr) {
        java.util.Objects.requireNonNull(bArr, "data");
        return SendSignalData(j, bArr);
    }

    @Override // com.remote.streamer.controlled.StreamerControlled
    public int sendTextData(long j, byte[] bArr) {
        java.util.Objects.requireNonNull(bArr, "data");
        return SendTextData(j, bArr);
    }

    @Override // com.remote.streamer.controlled.StreamerControlled
    public int startAudioCapture(long j, AudioCaptureConfig audioCaptureConfig) {
        java.util.Objects.requireNonNull(audioCaptureConfig, "config");
        return StartAudioCapture(j, audioCaptureConfig);
    }

    @Override // com.remote.streamer.controlled.StreamerControlled
    public int startVideoCapture(long j, VideoCaptureConfig videoCaptureConfig) {
        java.util.Objects.requireNonNull(videoCaptureConfig, "config");
        return StartVideoCapture(j, videoCaptureConfig);
    }

    @Override // com.remote.streamer.controlled.StreamerControlled
    public int stopAudioCapture(long j, int i10) {
        return StopAudioCapture(j, i10);
    }

    @Override // com.remote.streamer.controlled.StreamerControlled
    public int stopVideoCapture(long j, int i10) {
        return StopVideoCapture(j, i10);
    }
}
