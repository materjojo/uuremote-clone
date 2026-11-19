// Recovered from the supplied 4.48.1 APK; see analysis/official/android.
package com.remote.streamer;

import android.graphics.SurfaceTexture;
import android.os.Handler;
import android.util.Log;
import java.util.Arrays;

public final class StreamerSurfaceTexture extends SurfaceTexture implements SurfaceTexture.OnFrameAvailableListener {
    private long nativeGLesRenderer;

    public StreamerSurfaceTexture(int i10) {
        super(i10);
    }

    private final native void nativeOnFrameAvailable(long j, SurfaceTexture surfaceTexture);

    public final void SetNativeGLesRenderer(long j, Handler handler) {
        Log.i("StreamerSurfaceTexture", String.format("set native gles renderer %d handler=%s", Arrays.copyOf(new Object[]{Long.valueOf(j), handler}, 2)));
        synchronized (this) {
            try {
                if (j == 0) {
                    setOnFrameAvailableListener(null);
                } else if (handler != null) {
                    setOnFrameAvailableListener(this, handler);
                } else {
                    setOnFrameAvailableListener(this);
                }
                this.nativeGLesRenderer = j;
            } catch (Throwable th) {
                throw th;
            }
        }
    }

    @Override // android.graphics.SurfaceTexture.OnFrameAvailableListener
    public void onFrameAvailable(SurfaceTexture surfaceTexture) {
        java.util.Objects.requireNonNull(surfaceTexture, "surfaceTexture");
        if (this.nativeGLesRenderer == 0) {
            Log.e("StreamerSurfaceTexture", "drop frame because of native renderer handle is zero");
            return;
        }
        synchronized (this) {
            long j = this.nativeGLesRenderer;
            if (j == 0) {
                return;
            }
            nativeOnFrameAvailable(j, surfaceTexture);
        }
    }

    public StreamerSurfaceTexture(int i10, boolean z) {
        super(i10, z);
    }

    public StreamerSurfaceTexture(boolean z) {
        super(z);
    }
}
