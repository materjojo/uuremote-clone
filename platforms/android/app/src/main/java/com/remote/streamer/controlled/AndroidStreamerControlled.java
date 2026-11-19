package com.remote.streamer.controlled;

/**
 * 官方被控端入口（直调官方 libstreamer-jni.so）。
 * JNI 符号：Java_com_remote_streamer_controlled_AndroidStreamerControlled_*
 * 方法名来自官方 .so 导出符号表；参数签名需按 libstreamer-jni.so 内的
 * JNI 签名字符串逐一核对后才可运行时调用。
 */
public final class AndroidStreamerControlled {
    static {
        System.loadLibrary("c++_shared");
        System.loadLibrary("streamer");
        System.loadLibrary("streamer-jni");
    }

    private AndroidStreamerControlled() {}

    public static native void Initialize(Object context);
    public static native void Finalize();
    public static native int CreateRoom(Object config);
    public static native void DestroyRoom(int handle);
    public static native int StartVideoCapture(int handle, Object videoCaptureConfig);
    public static native int StartAudioCapture(int handle);
    public static native int StopVideoCapture(int handle);
    public static native int StopAudioCapture(int handle);
    public static native int SendControlData(int handle, byte[] data);
    public static native int SendTextData(int handle, String data);
    public static native int SendBinaryData(int handle, byte[] data);
    public static native int SendFileData(int handle, byte[] data);
    public static native int SendSignalData(int handle, byte[] data);
    public static native void ClearRoom(int handle);
    public static native String GetConnectionStats(int handle);
    public static native String GetEncodeCapability();
    public static native boolean CheckAlive(int handle);
    public static native String GetStreamerVersion();
}
