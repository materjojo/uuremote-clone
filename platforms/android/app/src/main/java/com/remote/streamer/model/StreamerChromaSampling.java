// Recovered from the supplied 4.48.1 APK; see analysis/official/android.
package com.remote.streamer.model;

public final class StreamerChromaSampling {
    public static final StreamerChromaSampling INSTANCE = new StreamerChromaSampling();
    public static final int K400 = 4;
    public static final int K420 = 1;
    public static final int K422 = 2;
    public static final int K444 = 3;

    private StreamerChromaSampling() {
    }
}
