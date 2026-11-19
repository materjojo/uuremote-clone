package com.remote.streamer.model;

import android.view.SurfaceView;

public final class VideoRendererConfig {
    private final SurfaceView surface;
    private final int videoTrackIndex;

    public VideoRendererConfig(int videoTrackIndex, SurfaceView surface) {
        this.videoTrackIndex = videoTrackIndex; this.surface = surface;
    }
    public SurfaceView getSurface() { return surface; }
    public int getVideoTrackIndex() { return videoTrackIndex; }
}
