// Recovered from the supplied 4.48.1 APK; see analysis/official/android.
package com.remote.streamer.model;

public final class StreamerAudioCaptureTarget {
    public static final StreamerAudioCaptureTarget INSTANCE = new StreamerAudioCaptureTarget();
    public static final int MICROPHONE = 1;
    public static final int MUMU = 2;
    public static final int SPEAKER = 0;

    private StreamerAudioCaptureTarget() {
    }
}
