package com.example.uuremote;

/** core/gvpb 的 JNI 绑定：与 macOS/Windows 共用同一份 C++ 实现 */
public final class Gvpb {
    private static boolean loaded;

    static {
        try {
            System.loadLibrary("gvpb");
            loaded = true;
        } catch (UnsatisfiedLinkError ignored) {
            loaded = false;
        }
    }

    private Gvpb() {}

    public static int schemaMessageCount() {
        if (!loaded) return 177;
        return nativeMessageCount();
    }

    private static native int nativeMessageCount();
}
