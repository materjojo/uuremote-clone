package com.example.uuremote;

import android.content.Context;
import android.hardware.display.DisplayManager;
import android.hardware.display.VirtualDisplay;
import android.media.projection.MediaProjection;
import android.view.Surface;

/** MediaProjection -> VirtualDisplay -> MediaCodec(surface) 采集编码 */
public final class ScreenCapture {
    public interface Listener {
        void onFrame(byte[] annexB, boolean keyFrame);
        void onError(String message);
    }

    private final H264Encoder encoder = new H264Encoder();
    private VirtualDisplay display;

    public void start(Context context, MediaProjection projection,
                      int width, int height, int fps, int bitrate, Listener listener) {
        try {
            Surface surface = encoder.start(width, height, fps, bitrate, listener::onFrame);
            int density = context.getResources().getDisplayMetrics().densityDpi;
            display = projection.createVirtualDisplay(
                    "uuremote-screen",
                    width, height, density,
                    DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                    surface, null, null);
        } catch (Exception e) {
            listener.onError(e.getMessage() == null ? "capture failed" : e.getMessage());
        }
    }

    public void stop() {
        if (display != null) {
            display.release();
            display = null;
        }
        encoder.stop();
    }
}
