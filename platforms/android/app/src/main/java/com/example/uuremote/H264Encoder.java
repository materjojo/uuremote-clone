package com.example.uuremote;

import android.media.MediaCodec;
import android.media.MediaCodecInfo;
import android.media.MediaFormat;
import android.view.Surface;

import java.nio.ByteBuffer;

/** MediaCodec H.264 硬编（surface 输入，零拷贝），输出 Annex-B */
public class H264Encoder {
    public interface Callback {
        void onFrame(byte[] annexB, boolean keyFrame);
    }

    private MediaCodec codec;
    private Surface surface;
    private Thread thread;
    private volatile boolean running;
    private byte[] sps;
    private byte[] pps;

    public Surface start(int width, int height, int fps, int bitrate, Callback callback) throws Exception {
        MediaFormat format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height);
        format.setInteger(MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface);
        format.setInteger(MediaFormat.KEY_BIT_RATE, bitrate);
        format.setInteger(MediaFormat.KEY_FRAME_RATE, fps);
        format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 2);
        format.setInteger(MediaFormat.KEY_BITRATE_MODE,
                MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR);

        codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC);
        codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
        surface = codec.createInputSurface();
        codec.start();

        running = true;
        thread = new Thread(() -> drain(callback), "uuremote-enc");
        thread.start();
        return surface;
    }

    private void drain(Callback callback) {
        MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
        while (running) {
            try {
                int index = codec.dequeueOutputBuffer(info, 10_000);
                if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    MediaFormat out = codec.getOutputFormat();
                    sps = toBytes(out.getByteBuffer("csd-0"));
                    pps = toBytes(out.getByteBuffer("csd-1"));
                } else if (index >= 0) {
                    ByteBuffer buffer = codec.getOutputBuffer(index);
                    if (buffer != null && info.size > 0) {
                        byte[] data = new byte[info.size];
                        buffer.position(info.offset);
                        buffer.get(data, 0, info.size);
                        boolean key = (info.flags & MediaCodec.BUFFER_FLAG_KEY_FRAME) != 0;
                        callback.onFrame(key ? withParameterSets(data) : startCode(data), key);
                    }
                    codec.releaseOutputBuffer(index, false);
                }
            } catch (IllegalStateException stopped) {
                break;
            }
        }
    }

    private byte[] withParameterSets(byte[] frame) {
        byte[] body = startCode(frame);
        if (sps == null || pps == null) return body;
        byte[] out = new byte[sps.length + pps.length + body.length];
        System.arraycopy(sps, 0, out, 0, sps.length);
        System.arraycopy(pps, 0, out, sps.length, pps.length);
        System.arraycopy(body, 0, out, sps.length + pps.length, body.length);
        return out;
    }

    private static byte[] startCode(byte[] nal) {
        byte[] out = new byte[nal.length + 4];
        out[0] = 0; out[1] = 0; out[2] = 0; out[3] = 1;
        System.arraycopy(nal, 0, out, 4, nal.length);
        return out;
    }

    private static byte[] toBytes(ByteBuffer buffer) {
        if (buffer == null) return new byte[0];
        byte[] out = new byte[buffer.remaining()];
        buffer.get(out);
        return out;
    }

    public void stop() {
        running = false;
        try {
            if (thread != null) thread.join(500);
        } catch (InterruptedException ignored) {
        }
        if (codec != null) {
            try { codec.stop(); } catch (Exception ignored) { }
            codec.release();
            codec = null;
        }
        if (surface != null) {
            surface.release();
            surface = null;
        }
    }
}
