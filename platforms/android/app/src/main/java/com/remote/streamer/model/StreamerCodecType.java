// Recovered from the supplied 4.48.1 APK; see analysis/official/android.
package com.remote.streamer.model;

public final class StreamerCodecType {
    public static final int AV1 = 5;
    public static final int H264 = 1;
    public static final int H265 = 2;
    public static final StreamerCodecType INSTANCE = new StreamerCodecType();
    public static final int VP8 = 3;
    public static final int VP9 = 4;

    private StreamerCodecType() {
    }
}
