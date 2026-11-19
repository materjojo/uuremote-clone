// Recovered from the supplied 4.48.1 APK; see analysis/official/android.
package com.remote.streamer.controlled;

import com.remote.streamer.model.AudioCaptureConfig;
import com.remote.streamer.model.NewControlInfo;
import com.remote.streamer.model.StreamerRoomConfig;
import com.remote.streamer.model.VideoCaptureConfig;

public abstract class StreamerControlled {
    private volatile Delegate delegate;

    public interface Delegate {



        default void onCaptureFailed(long j, int i10, int i11, int i12, int i13) {}

        default void onConnectionError(long j, int i10) {}

        default void onConnectionState(long j, int i10) {}

        default void onControlledPush(long j, String str) {}

        default void onEventReport(long j, String str, String str2) {}

        default void onNewControl(long j, NewControlInfo newControlInfo) {}

        default void onQosStats(long j, String str) {}

        default void onReceiveBinaryData(long j, byte[] bArr) {}

        default void onReceiveControlData(long j, String str) {}

        default void onReceiveControlData(long j, byte[] bArr) {}

        default void onReceiveDataChannel(long j, String str) {}

        default void onReceiveFileData(long j, byte[] bArr) {}

        default void onReceiveTextData(long j, byte[] bArr) {}

        default void onRoomState(long j, int i10) {}
    }

    public final void OnConnectionError(long j, int i10) {
        Delegate delegate = this.delegate;
        if (delegate != null) {
            delegate.onConnectionError(j, i10);
        }
    }

    public final void OnConnectionState(long j, int i10) {
        Delegate delegate = this.delegate;
        if (delegate != null) {
            delegate.onConnectionState(j, i10);
        }
    }

    public final void OnEventReport(long j, String str, String str2) {
        java.util.Objects.requireNonNull(str, "eventName");
        java.util.Objects.requireNonNull(str2, "eventData");
        Delegate delegate = this.delegate;
        if (delegate != null) {
            delegate.onEventReport(j, str, str2);
        }
    }

    public final void OnNewControl(long j, NewControlInfo newControlInfo) {
        java.util.Objects.requireNonNull(newControlInfo, "info");
        Delegate delegate = this.delegate;
        if (delegate != null) {
            delegate.onNewControl(j, newControlInfo);
        }
    }

    public final void OnQosStats(long j, String str) {
        java.util.Objects.requireNonNull(str, "dataJson");
        Delegate delegate = this.delegate;
        if (delegate != null) {
            delegate.onQosStats(j, str);
        }
    }

    public final void OnReceiveBinaryData(long j, byte[] bArr) {
        java.util.Objects.requireNonNull(bArr, "data");
        Delegate delegate = this.delegate;
        if (delegate != null) {
            delegate.onReceiveBinaryData(j, bArr);
        }
    }

    public final void OnReceiveControlData(long j, String str) {
        java.util.Objects.requireNonNull(str, "dataJson");
        Delegate delegate = this.delegate;
        if (delegate != null) {
            delegate.onReceiveControlData(j, str);
        }
    }

    public final void OnReceiveDataChannel(long j, String str) {
        java.util.Objects.requireNonNull(str, "name");
        Delegate delegate = this.delegate;
        if (delegate != null) {
            delegate.onReceiveDataChannel(j, str);
        }
    }

    public final void OnReceiveFileData(long j, byte[] bArr) {
        java.util.Objects.requireNonNull(bArr, "data");
        Delegate delegate = this.delegate;
        if (delegate != null) {
            delegate.onReceiveFileData(j, bArr);
        }
    }

    public final void OnReceiveTextData(long j, byte[] bArr) {
        java.util.Objects.requireNonNull(bArr, "data");
        Delegate delegate = this.delegate;
        if (delegate != null) {
            delegate.onReceiveTextData(j, bArr);
        }
    }

    public final void OnRoomState(long j, int i10) {
        Delegate delegate = this.delegate;
        if (delegate != null) {
            delegate.onRoomState(j, i10);
        }
    }

    public final void OnSignalPush(long j, String str) {
        java.util.Objects.requireNonNull(str, "dataJson");
        Delegate delegate = this.delegate;
        if (delegate != null) {
            delegate.onControlledPush(j, str);
        }
    }

    public abstract int checkAlive();

    public abstract int clearRoom(long j);

    public abstract long createRoom(StreamerRoomConfig streamerRoomConfig);

    public abstract int destroyRoom(long j);

    public abstract int shutdown();

    public abstract int getConnectionStats(long j);

    public abstract String getEncodeCapability();

    public abstract String getStreamerVersion();

    public abstract int initialize(String str, String str2);

    public final void onCaptureFailed(long j, int i10, int i11, int i12, int i13) {
        Delegate delegate = this.delegate;
        if (delegate != null) {
            delegate.onCaptureFailed(j, i10, i11, i12, i13);
        }
    }

    public abstract int sendBinaryData(long j, byte[] bArr);

    public abstract int sendControlData(long j, byte[] bArr);

    public abstract int sendFileData(long j, byte[] bArr);

    public abstract int sendSignalData(long j, byte[] bArr);

    public abstract int sendTextData(long j, byte[] bArr);

    public final void setDelegate(Delegate delegate) {
        this.delegate = delegate;
    }

    public abstract int startAudioCapture(long j, AudioCaptureConfig audioCaptureConfig);

    public abstract int startVideoCapture(long j, VideoCaptureConfig videoCaptureConfig);

    public abstract int stopAudioCapture(long j, int i10);

    public abstract int stopVideoCapture(long j, int i10);

    public final void OnReceiveControlData(long j, byte[] bArr) {
        java.util.Objects.requireNonNull(bArr, "data");
        Delegate delegate = this.delegate;
        if (delegate != null) {
            delegate.onReceiveControlData(j, bArr);
        }
    }
}
