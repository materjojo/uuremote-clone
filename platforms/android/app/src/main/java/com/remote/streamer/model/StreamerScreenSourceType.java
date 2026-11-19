// Recovered from the supplied 4.48.1 APK; see analysis/official/android.
package com.remote.streamer.model;

public final class StreamerScreenSourceType {
    public static final int CAST_SCREEN = 1;
    public static final StreamerScreenSourceType INSTANCE = new StreamerScreenSourceType();
    public static final int NORMAL_SCREEN = 0;

    private StreamerScreenSourceType() {
    }
}
