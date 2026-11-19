package com.remote.streamer.model;

import android.media.projection.MediaProjection;

/** 官方字段（从官方 Java 层还原）：JNI 通过 GetFieldID 读取，字段名/类型必须一致 */
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

    public VideoCaptureConfig(int captureTarget, int chromaSampling, int codecType, boolean cursorCapture,
                              int fps, int frameQuality, boolean hdr, int maxScaleHeight, int maxScaleWidth,
                              MediaProjection mediaProjection, int resolutionHeight, int resolutionWidth, int screenId) {
        this.captureTarget = captureTarget; this.chromaSampling = chromaSampling; this.codecType = codecType;
        this.cursorCapture = cursorCapture; this.fps = fps; this.frameQuality = frameQuality; this.hdr = hdr;
        this.maxScaleHeight = maxScaleHeight; this.maxScaleWidth = maxScaleWidth;
        this.mediaProjection = mediaProjection; this.resolutionHeight = resolutionHeight;
        this.resolutionWidth = resolutionWidth; this.screenId = screenId;
    }
    public int getCaptureTarget() { return captureTarget; }
    public int getChromaSampling() { return chromaSampling; }
    public int getCodecType() { return codecType; }
    public boolean getCursorCapture() { return cursorCapture; }
    public int getFps() { return fps; }
    public int getFrameQuality() { return frameQuality; }
    public boolean getHdr() { return hdr; }
    public int getMaxScaleHeight() { return maxScaleHeight; }
    public int getMaxScaleWidth() { return maxScaleWidth; }
    public MediaProjection getMediaProjection() { return mediaProjection; }
    public int getResolutionHeight() { return resolutionHeight; }
    public int getResolutionWidth() { return resolutionWidth; }
    public int getScreenId() { return screenId; }
}
