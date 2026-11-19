package com.remote.streamer.controller;

/**
 * 官方控制端入口（直调官方 libstreamer-jni.so）。
 * JNI 符号：Java_com_remote_streamer_controller_AndroidStreamerController_*
 */
public final class AndroidStreamerController {
    static {
        System.loadLibrary("c++_shared");
        System.loadLibrary("streamer");
        System.loadLibrary("streamer-jni");
    }

    private AndroidStreamerController() {}

    public static native void Initialize(Object context);
    public static native void Finalize();
    public static native int LoginRoom(Object roomInfo);
    public static native int Connect(int handle);
    public static native void Disconnect(int handle);
    public static native void ExitRoom(int handle);
    public static native int StartVideoRender(int handle, Object renderConfig);
    public static native int StartAudioRender(int handle);
    public static native int StopVideoRender(int handle);
    public static native int StopAudioRender(int handle);
    public static native int SendControlData(int handle, byte[] data);
    public static native int SendTextData(int handle, String data);
    public static native int SendBinaryData(int handle, byte[] data);
    public static native int SendFileData(int handle, byte[] data);
    public static native String GetConnectionStats(int handle);
    public static native String GetDecodeCapability();
    public static native String GetStreamerVersion();
    public static native int SwitchIceNetwork(int handle);
}
