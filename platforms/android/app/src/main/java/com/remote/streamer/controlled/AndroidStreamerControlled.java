package com.remote.streamer.controlled;

import com.remote.streamer.model.AudioCaptureConfig;
import com.remote.streamer.model.StreamerRoomConfig;
import com.remote.streamer.model.VideoCaptureConfig;

/** 官方被控端入口：JNI 按符号名 Java_com_remote_streamer_controlled_* 绑定（签名来自官方 Java 层还原） */
public final class AndroidStreamerControlled {
    static {
        System.loadLibrary("c++_shared");
        System.loadLibrary("streamer");
        System.loadLibrary("streamer-jni");
    }

    private AndroidStreamerControlled() {}

    public static native int Initialize(String str, String str2);
    public static native int Finalize();
    public static native long CreateRoom(StreamerRoomConfig config);
    public static native int DestroyRoom(long j);
    public static native int StartVideoCapture(long j, VideoCaptureConfig config);
    public static native int StartAudioCapture(long j, AudioCaptureConfig config);
    public static native int StopVideoCapture(long j, int i);
    public static native int StopAudioCapture(long j, int i);
    public static native int SendControlData(long j, byte[] data);
    public static native int SendTextData(long j, byte[] data);
    public static native int SendBinaryData(long j, byte[] data);
    public static native int SendFileData(long j, byte[] data);
    public static native int SendSignalData(long j, byte[] data);
    public static native int ClearRoom(long j);
    public static native int GetConnectionStats(long j, byte[] out);
    public static native String GetEncodeCapability();
    public static native boolean CheckAlive(long j);
    public static native String GetStreamerVersion();
}
