// Recovered from the supplied 4.48.1 APK; see analysis/official/android.
package com.remote.streamer.model;

import android.view.SurfaceView;

public final class VideoRendererConfig {
    private final SurfaceView surface;
    private final int videoTrackIndex;

    public VideoRendererConfig(int i10, SurfaceView surfaceView) {
        java.util.Objects.requireNonNull(surfaceView, "surface");
        this.videoTrackIndex = i10;
        this.surface = surfaceView;
    }

    public final SurfaceView getSurface() {
        return this.surface;
    }

    public final int getVideoTrackIndex() {
        return this.videoTrackIndex;
    }
}
