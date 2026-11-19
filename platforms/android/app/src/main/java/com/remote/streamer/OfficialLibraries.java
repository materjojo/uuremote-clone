package com.remote.streamer;

/** Loads only the native media core from the supplied APK. No room is opened here. */
public final class OfficialLibraries {
    private static boolean loaded;
    private OfficialLibraries() {}

    public static synchronized void load() {
        if (loaded) return;
        System.loadLibrary("c++_shared");
        System.loadLibrary("streamer");
        System.loadLibrary("streamer-jni");
        loaded = true;
    }
}
