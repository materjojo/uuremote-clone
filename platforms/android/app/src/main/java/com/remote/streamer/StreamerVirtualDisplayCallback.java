// Recovered from the supplied 4.48.1 APK; see analysis/official/android.
package com.remote.streamer;

import android.hardware.display.VirtualDisplay;

public final class StreamerVirtualDisplayCallback extends VirtualDisplay.Callback {
    private long nativeListener;

    public StreamerVirtualDisplayCallback(long j) {
        this.nativeListener = j;
    }

    private final native void nativeOnPaused(long j);

    private final native void nativeOnResumed(long j);

    private final native void nativeOnStopped(long j);

    public final synchronized void clearNativeListener() {
        this.nativeListener = 0L;
    }

    @Override // android.hardware.display.VirtualDisplay.Callback
    public synchronized void onPaused() {
        long j = this.nativeListener;
        if (j != 0) {
            nativeOnPaused(j);
        }
    }

    @Override // android.hardware.display.VirtualDisplay.Callback
    public synchronized void onResumed() {
        long j = this.nativeListener;
        if (j != 0) {
            nativeOnResumed(j);
        }
    }

    @Override // android.hardware.display.VirtualDisplay.Callback
    public synchronized void onStopped() {
        long j = this.nativeListener;
        if (j != 0) {
            nativeOnStopped(j);
        }
    }
}
