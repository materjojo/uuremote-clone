// Recovered from the supplied 4.48.1 APK; see analysis/official/android.
package com.remote.streamer;

import android.content.Context;
import android.graphics.Point;
import android.hardware.display.DisplayManager;
import android.view.Display;

public final class StreamerDisplayListener implements DisplayManager.DisplayListener {
    private final DisplayManager displayManager;
    private long nativeListener;
    private final int targetDisplayId;

    public StreamerDisplayListener(Context context, long j, int i10) {
        java.util.Objects.requireNonNull(context, "context");
        this.nativeListener = j;
        this.targetDisplayId = i10;
        Object systemService = context.getSystemService("display");
        this.displayManager = systemService instanceof DisplayManager ? (DisplayManager) systemService : null;
        synchronized (this) {
            notifyDisplayChanged(i10);
        }
    }

    private final native void nativeOnDisplayChanged(long j, int i10, int i11, int i12, int i13);

    private final void notifyDisplayChanged(int i10) {
        Display display;
        long j = this.nativeListener;
        DisplayManager displayManager = this.displayManager;
        if (i10 != this.targetDisplayId || j == 0 || displayManager == null || (display = displayManager.getDisplay(i10)) == null) {
            return;
        }
        Point point = new Point();
        display.getRealSize(point);
        nativeOnDisplayChanged(j, i10, display.getRotation(), point.x, point.y);
    }

    public final synchronized void clearNativeListener() {
        this.nativeListener = 0L;
    }

    @Override // android.hardware.display.DisplayManager.DisplayListener
    public synchronized void onDisplayAdded(int i10) {
        notifyDisplayChanged(i10);
    }

    @Override // android.hardware.display.DisplayManager.DisplayListener
    public synchronized void onDisplayChanged(int i10) {
        notifyDisplayChanged(i10);
    }

    @Override // android.hardware.display.DisplayManager.DisplayListener
    public synchronized void onDisplayRemoved(int i10) {
        notifyDisplayChanged(i10);
    }
}
