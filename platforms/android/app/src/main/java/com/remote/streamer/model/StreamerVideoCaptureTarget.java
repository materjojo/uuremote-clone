// Recovered from the supplied 4.48.1 APK; see analysis/official/android.
package com.remote.streamer.model;

public final class StreamerVideoCaptureTarget {
    public static final int DESKTOP = 0;
    public static final StreamerVideoCaptureTarget INSTANCE = new StreamerVideoCaptureTarget();
    public static final int MUMU = 2;
    public static final int WINDOW = 1;

    private StreamerVideoCaptureTarget() {
    }
}
