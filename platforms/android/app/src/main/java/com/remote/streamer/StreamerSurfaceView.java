// Recovered from the supplied 4.48.1 APK; see analysis/official/android.
package com.remote.streamer;

import android.content.Context;
import android.util.AttributeSet;
import android.util.Log;
import android.view.SurfaceView;
import java.util.Arrays;

public final class StreamerSurfaceView extends SurfaceView {
    private long nativeGLesRendererHandle;

    public StreamerSurfaceView(Context context) {
        super(context);
        java.util.Objects.requireNonNull(context, "context");
    }

    private final native void nativeRendererInvalidate(long j);

    private final native void nativeSetTransform(long j, float f7, float f10, float f11, float f12, float f13, float f14);

    public final void SetNativeGLesRenderer(long j) {
        Log.i("StreamerSurfaceView", String.format("set native gles renderer %d", Arrays.copyOf(new Object[]{Long.valueOf(j)}, 1)));
        synchronized (this) {
            this.nativeGLesRendererHandle = j;
        }
    }

    @Override // android.view.View
    public void invalidate() {
        super.invalidate();
        if (this.nativeGLesRendererHandle == 0) {
            Log.e("StreamerSurfaceView", "current native gles renderer handle is zero");
            return;
        }
        synchronized (this) {
            long j = this.nativeGLesRendererHandle;
            if (j == 0) {
                return;
            }
            nativeRendererInvalidate(j);
        }
    }

    public final void setTransform(float f7, float f10, float f11, float f12, float f13, float f14) {
        if (this.nativeGLesRendererHandle == 0) {
            Log.e("StreamerSurfaceView", "current native gles renderer handle is zero");
            return;
        }
        synchronized (this) {
            long j = this.nativeGLesRendererHandle;
            if (j == 0) {
                return;
            }
            nativeSetTransform(j, f7, f10, f11, f12, f13, f14);
        }
    }

    public StreamerSurfaceView(Context context, AttributeSet attributeSet) {
        super(context, attributeSet);
        java.util.Objects.requireNonNull(context, "context");
    }

    public StreamerSurfaceView(Context context, AttributeSet attributeSet, int i10) {
        super(context, attributeSet, i10);
        java.util.Objects.requireNonNull(context, "context");
    }

    public StreamerSurfaceView(Context context, AttributeSet attributeSet, int i10, int i11) {
        super(context, attributeSet, i10, i11);
        java.util.Objects.requireNonNull(context, "context");
    }
}
