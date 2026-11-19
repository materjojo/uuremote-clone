// Recovered from the supplied 4.48.1 APK; see analysis/official/android.
package com.remote.streamer.controller;

import com.remote.streamer.model.AudioCaptureConfig;
import com.remote.streamer.model.AudioRendererConfig;
import com.remote.streamer.model.IceNetworkConfig;
import com.remote.streamer.model.StreamerRoomConfig;

public abstract class StreamerController {
    private volatile Delegate delegate;

    public interface Delegate {



        default void onConnectionError(long j, int i10) {}

        default void onConnectionState(long j, int i10, int i11) {}

        default void onControllerPush(long j, String str) {}

        default void onEventReport(long j, String str, String str2) {}

        default void onFrameChange(long j, int i10, int i11, int i12, int i13, String str) {}

        default void onNatInfo(long j, String str) {}

        default void onNegotiateResult(long j, String str) {}

        default void onQosStats(long j, String str) {}

        default void onReceiveBinaryData(long j, byte[] bArr) {}

        default void onReceiveControlData(long j, String str) {}

        default void onReceiveControlData(long j, byte[] bArr) {}

        default void onReceiveDataChannel(long j, String str) {}

        default void onReceiveFileData(long j, byte[] bArr) {}

        default void onReceiveMediaTrack(long j, int i10, String str) {}

        default void onReceiveTextData(long j, byte[] bArr) {}

        default void onRemoveMediaTrack(long j, int i10, String str) {}

        default void onRoomState(long j, int i10) {}

        default void onSignalData(long j, byte[] bArr) {}
    }

    public final void OnConnectionError(long j, int i10) {
        Delegate delegate = this.delegate;
        if (delegate != null) {
            delegate.onConnectionError(j, i10);
        }
    }

    public final void OnConnectionState(long j, int i10, int i11) {
        Delegate delegate = this.delegate;
        if (delegate != null) {
            delegate.onConnectionState(j, i10, i11);
        }
    }

    public final void OnDualNegotiate(long j, String str) {
        java.util.Objects.requireNonNull(str, "dataJson");
        Delegate delegate = this.delegate;
        if (delegate != null) {
            delegate.onNegotiateResult(j, str);
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

    public final void OnNatInfo(long j, String str) {
        java.util.Objects.requireNonNull(str, "dataJson");
        Delegate delegate = this.delegate;
        if (delegate != null) {
            delegate.onNatInfo(j, str);
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

    public final void OnReceiveMediaTrack(long j, int i10, String str) {
        java.util.Objects.requireNonNull(str, "mediaType");
        Delegate delegate = this.delegate;
        if (delegate != null) {
            delegate.onReceiveMediaTrack(j, i10, str);
        }
    }

    public final void OnReceiveTextData(long j, byte[] bArr) {
        java.util.Objects.requireNonNull(bArr, "data");
        Delegate delegate = this.delegate;
        if (delegate != null) {
            delegate.onReceiveTextData(j, bArr);
        }
    }

    public final void OnRemoveMediaTrack(long j, int i10, String str) {
        java.util.Objects.requireNonNull(str, "mediaType");
        Delegate delegate = this.delegate;
        if (delegate != null) {
            delegate.onRemoveMediaTrack(j, i10, str);
        }
    }

    public final void OnRoomState(long j, int i10) {
        Delegate delegate = this.delegate;
        if (delegate != null) {
            delegate.onRoomState(j, i10);
        }
    }

    public final void OnSignalData(long j, byte[] bArr) {
        java.util.Objects.requireNonNull(bArr, "data");
        Delegate delegate = this.delegate;
        if (delegate != null) {
            delegate.onSignalData(j, bArr);
        }
    }

    public final void OnSignalPush(long j, String str) {
        java.util.Objects.requireNonNull(str, "dataJson");
        Delegate delegate = this.delegate;
        if (delegate != null) {
            delegate.onControllerPush(j, str);
        }
    }

    public abstract int connect(long j, byte[] bArr, String str, String str2);

    public abstract int disconnect(long j);

    public abstract int exitRoom(long j);

    public abstract int shutdown();

    public abstract int getConnectionStats(long j);

    public abstract String getDecodeCapability();

    public abstract String getStreamerVersion();

    public abstract int initialize(String str, String str2);

    public abstract long loginRoom(StreamerRoomConfig streamerRoomConfig);

    public final void onFrameChange(long j, int i10, int i11, int i12, int i13, String str) {
        java.util.Objects.requireNonNull(str, "viewPortJson");
        Delegate delegate = this.delegate;
        if (delegate != null) {
            delegate.onFrameChange(j, i10, i11, i12, i13, str);
        }
    }

    public abstract int sendBinaryData(long j, byte[] bArr);

    public abstract int sendControlData(long j, byte[] bArr);

    public abstract int sendFileData(long j, byte[] bArr);

    public abstract int sendTextData(long j, byte[] bArr);

    public final void setDelegate(Delegate delegate) {
        this.delegate = delegate;
    }

    public abstract int startAudioCapture(long j, AudioCaptureConfig audioCaptureConfig);

    public abstract int startAudioRender(long j, AudioRendererConfig audioRendererConfig);

    public abstract int stopAudioCapture(long j, int i10);

    public abstract int stopAudioRender(long j, int i10);

    public abstract int stopVideoRender(long j, int i10);

    public abstract int switchIceNetwork(long j, IceNetworkConfig iceNetworkConfig);

    public final void OnReceiveControlData(long j, byte[] bArr) {
        java.util.Objects.requireNonNull(bArr, "data");
        Delegate delegate = this.delegate;
        if (delegate != null) {
            delegate.onReceiveControlData(j, bArr);
        }
    }
}
