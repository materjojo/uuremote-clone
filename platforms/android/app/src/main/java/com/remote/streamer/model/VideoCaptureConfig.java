// Recovered from the supplied 4.48.1 APK; see analysis/official/android.
package com.remote.streamer.model;

import android.media.projection.MediaProjection;

public final class VideoCaptureConfig {
    private final int captureTarget;
    private final int chromaSampling;
    private final int codecType;
    private final boolean cursorCapture;
    private final int fps;
    private final int frameQuality;
    private final boolean hdr;
    private final int maxScaleHeight;
    private final int maxScaleWidth;
    private final MediaProjection mediaProjection;
    private final int resolutionHeight;
    private final int resolutionWidth;
    private final int screenId;
    private final int screenSourceType;
    private final int videoTrackIndex;

    public VideoCaptureConfig() {
        this(0, 0, false, 0, 0, 1, 2, 0, 0, false, null, 0, 0, 0, 0);
    }

    public final int getCaptureTarget() {
        return this.captureTarget;
    }

    public final int getChromaSampling() {
        return this.chromaSampling;
    }

    public final int getCodecType() {
        return this.codecType;
    }

    public final boolean getCursorCapture() {
        return this.cursorCapture;
    }

    public final int getFps() {
        return this.fps;
    }

    public final int getFrameQuality() {
        return this.frameQuality;
    }

    public final boolean getHdr() {
        return this.hdr;
    }

    public final int getMaxScaleHeight() {
        return this.maxScaleHeight;
    }

    public final int getMaxScaleWidth() {
        return this.maxScaleWidth;
    }

    public final MediaProjection getMediaProjection() {
        return this.mediaProjection;
    }

    public final int getResolutionHeight() {
        return this.resolutionHeight;
    }

    public final int getResolutionWidth() {
        return this.resolutionWidth;
    }

    public final int getScreenId() {
        return this.screenId;
    }

    public final int getScreenSourceType() {
        return this.screenSourceType;
    }

    public final int getVideoTrackIndex() {
        return this.videoTrackIndex;
    }

    public VideoCaptureConfig(int i10, int i11, boolean z, int i12, int i13, int i14, int i15, int i16, int i17, boolean z2, MediaProjection mediaProjection, int i18, int i19, int i20, int i21) {
        this.fps = i10;
        this.frameQuality = i11;
        this.cursorCapture = z;
        this.videoTrackIndex = i12;
        this.captureTarget = i13;
        this.chromaSampling = i14;
        this.codecType = i15;
        this.maxScaleWidth = i16;
        this.maxScaleHeight = i17;
        this.hdr = z2;
        this.mediaProjection = mediaProjection;
        this.resolutionWidth = i18;
        this.resolutionHeight = i19;
        this.screenId = i20;
        this.screenSourceType = i21;
    }


}
