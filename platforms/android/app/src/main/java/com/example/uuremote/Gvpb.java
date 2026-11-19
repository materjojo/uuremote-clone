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
    private static native String nativeSchemaName(String message, int field);
    private static native int nativeFieldNumber(String message, String name);
    private static native byte[] nativeEncodeVarint(int field, long value);
    private static native byte[] nativeEncodeString(int field, String value);

    public static String schemaName(String message, int field) {
        if (!loaded) return null;
        return nativeSchemaName(message, field);
    }

    public static int fieldNumber(String message, String name) {
        if (!loaded) return -1;
        return nativeFieldNumber(message, name);
    }

    public static byte[] encodeVarint(int field, long value) {
        if (!loaded) return new byte[0];
        return nativeEncodeVarint(field, value);
    }

    public static byte[] encodeString(int field, String value) {
        if (!loaded) return new byte[0];
        return nativeEncodeString(field, value);
    }
}
