// Recovered from the supplied 4.48.1 APK; see analysis/official/android.
package com.remote.streamer;

import android.media.projection.MediaProjection;

public final class StreamerMediaProjectionCallback extends MediaProjection.Callback {
    private long nativeListener;

    public StreamerMediaProjectionCallback(long j) {
        this.nativeListener = j;
    }

    private final native void nativeOnCapturedContentResize(long j, int i10, int i11);

    private final native void nativeOnStop(long j);

    public final synchronized void clearNativeListener() {
        this.nativeListener = 0L;
    }

    @Override // android.media.projection.MediaProjection.Callback
    public synchronized void onCapturedContentResize(int i10, int i11) {
        long j = this.nativeListener;
        if (j != 0) {
            nativeOnCapturedContentResize(j, i10, i11);
        }
    }

    @Override // android.media.projection.MediaProjection.Callback
    public synchronized void onStop() {
        long j = this.nativeListener;
        if (j != 0) {
            nativeOnStop(j);
        }
    }
}
