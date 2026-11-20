package com.example.uuremote;

import static org.junit.Assert.*;
import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import java.nio.ByteBuffer;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.webrtc.*;

@RunWith(AndroidJUnit4.class)
public class PeerMediaTest {
    @Test public void realVideoAndControl() throws Exception {
        Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        StreamerSession[] sessions = new StreamerSession[2];
        CountDownLatch video = new CountDownLatch(1), echo = new CountDownLatch(1);
        AtomicReference<String> error = new AtomicReference<>();
        SyntheticCapture capture = new SyntheticCapture();
        VideoTrack[] remote = new VideoTrack[1];
        VideoSink sink = frame -> { if (frame.getBuffer().getWidth() == 64 && frame.getBuffer().getHeight() == 64) video.countDown(); };
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
            StreamerSession.Listener host = new StreamerSession.Listener() {
                public void onOffer(String sdp) { }
                public void onAnswer(String sdp) { sessions[1].setRemoteAnswer(sdp); }
                public void onCandidate(IceCandidate c) { sessions[1].addCandidate(c); }
                public void onState(String state) { }
                public void onError(String message) { error.set(message); }
                public void onControl(byte[] data) { sessions[0].sendControl(data); }
            };
            StreamerSession.Listener controller = new StreamerSession.Listener() {
                public void onOffer(String sdp) { sessions[0].handleOffer(sdp); }
                public void onCandidate(IceCandidate c) { sessions[0].addCandidate(c); }
                public void onState(String state) { }
                public void onError(String message) { error.set(message); }
                public void onControl(byte[] data) { if (new String(data, java.nio.charset.StandardCharsets.UTF_8).equals("input")) echo.countDown(); }
                public void onVideo(VideoTrack track) { if (remote[0] != null) remote[0].removeSink(sink); remote[0] = track; track.addSink(sink); }
            };
            sessions[0] = new StreamerSession(context, host);
            sessions[1] = new StreamerSession(context, controller);
            sessions[0].prepareHost(context, capture, 64, 64);
            sessions[1].start();
        });
        try {
            long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(30);
            while (echo.getCount() > 0 && error.get() == null && System.nanoTime() < deadline) {
                InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> sessions[1].sendControl("input".getBytes(java.nio.charset.StandardCharsets.UTF_8)));
                echo.await(100, TimeUnit.MILLISECONDS);
            }
            assertNull(error.get());
            assertTrue("SCTP control must return from the opposite native peer", echo.await(1, TimeUnit.SECONDS));
            assertTrue("Opposite native peer must decode RTP video", video.await(10, TimeUnit.SECONDS));
        } finally {
            InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
                if (remote[0] != null) remote[0].removeSink(sink);
                sessions[1].stop(); sessions[0].stop();
            });
        }
    }

    private static final class SyntheticCapture implements VideoCapturer {
        private final Handler main = new Handler(Looper.getMainLooper());
        private CapturerObserver observer;
        private boolean running;
        private final Runnable next = new Runnable() {
            public void run() {
                if (!running) return;
                JavaI420Buffer data = JavaI420Buffer.allocate(64, 64);
                fill(data.getDataY(), (byte)100); fill(data.getDataU(), (byte)128); fill(data.getDataV(), (byte)128);
                VideoFrame frame = new VideoFrame(data, 0, System.nanoTime());
                observer.onFrameCaptured(frame); frame.release();
                main.postDelayed(this, 50);
            }
        };
        private static void fill(ByteBuffer value, byte b) { while (value.hasRemaining()) value.put(b); value.rewind(); }
        public void initialize(SurfaceTextureHelper helper, Context context, CapturerObserver observer) { this.observer = observer; }
        public void startCapture(int width, int height, int fps) { running = true; observer.onCapturerStarted(true); main.post(next); }
        public void stopCapture() { running = false; main.removeCallbacks(next); observer.onCapturerStopped(); }
        public void changeCaptureFormat(int width, int height, int fps) { }
        public void dispose() { running = false; main.removeCallbacks(next); }
        public boolean isScreencast() { return true; }
    }
}
