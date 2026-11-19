package com.remote.streamer.model;

import android.media.projection.MediaProjection;

public final class AudioCaptureConfig {
    private final int audioTrackIndex;
    private final int captureTarget;
    private final MediaProjection mediaProjection;

    public AudioCaptureConfig(int audioTrackIndex, int captureTarget, MediaProjection mediaProjection) {
        this.audioTrackIndex = audioTrackIndex; this.captureTarget = captureTarget;
        this.mediaProjection = mediaProjection;
    }
    public int getAudioTrackIndex() { return audioTrackIndex; }
    public int getCaptureTarget() { return captureTarget; }
    public MediaProjection getMediaProjection() { return mediaProjection; }
}
