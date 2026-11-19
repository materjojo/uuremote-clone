// Recovered from the supplied 4.48.1 APK; see analysis/official/android.
package com.remote.streamer.model;

public final class StreamerFrameQuality {
    public static final int AUTO = 0;
    public static final int BLURAY = 4;
    public static final int CUSTOM_QUALITY = 5;
    public static final int FAST = 1;
    public static final int GENERAL = 2;
    public static final int HD = 3;
    public static final StreamerFrameQuality INSTANCE = new StreamerFrameQuality();
    public static final int UNDEFINED = -1;

    private StreamerFrameQuality() {
    }
}
