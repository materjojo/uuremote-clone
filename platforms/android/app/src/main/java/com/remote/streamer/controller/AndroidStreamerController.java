package com.remote.streamer.controller;

import android.view.SurfaceView;
import com.remote.streamer.model.AudioCaptureConfig;
import com.remote.streamer.model.VideoRendererConfig;

/** 官方控制端入口：JNI 按符号名 Java_com_remote_streamer_controller_* 绑定 */
public final class AndroidStreamerController {
    static {
        System.loadLibrary("c++_shared");
        System.loadLibrary("streamer");
        System.loadLibrary("streamer-jni");
    }

    private AndroidStreamerController() {}

    public static native int Initialize(String str, String str2);
    public static native int Finalize();
    public static native long LoginRoom(Object roomConfig);
    public static native int Connect(long j);
    public static native int Disconnect(long j);
    public static native int ExitRoom(long j);
    public static native int StartVideoRender(long j, VideoRendererConfig config);
    public static native int StartAudioRender(long j, SurfaceView surface);
    public static native int StopVideoRender(long j, int i);
    public static native int StopAudioRender(long j, int i);
    public static native int SendControlData(long j, byte[] data);
    public static native int SendTextData(long j, byte[] data);
    public static native int SendBinaryData(long j, byte[] data);
    public static native int SendFileData(long j, byte[] data);
    public static native String GetConnectionStats(long j);
    public static native String GetDecodeCapability();
    public static native String GetStreamerVersion();
    public static native int SwitchIceNetwork(long j);
}
