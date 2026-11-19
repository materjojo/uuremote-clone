// Recovered from the supplied 4.48.1 APK; see analysis/official/android.
package com.remote.streamer.model;

import android.media.projection.MediaProjection;

public final class AudioCaptureConfig {
    private final int audioTrackIndex;
    private final int captureTarget;
    private final MediaProjection mediaProjection;

    public AudioCaptureConfig(int i10, int i11, MediaProjection mediaProjection) {
        this.captureTarget = i10;
        this.audioTrackIndex = i11;
        this.mediaProjection = mediaProjection;
    }

    public final int getAudioTrackIndex() {
        return this.audioTrackIndex;
    }

    public final int getCaptureTarget() {
        return this.captureTarget;
    }

    public final MediaProjection getMediaProjection() {
        return this.mediaProjection;
    }


}
