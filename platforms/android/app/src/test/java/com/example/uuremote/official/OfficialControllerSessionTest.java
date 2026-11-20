package com.example.uuremote.official;

import static org.junit.Assert.*;

import com.remote.streamer.controller.StreamerController;
import com.remote.streamer.model.AudioCaptureConfig;
import com.remote.streamer.model.AudioRendererConfig;
import com.remote.streamer.model.IceNetworkConfig;
import com.remote.streamer.model.StreamerRoomConfig;

import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.Test;

/** Lifecycle/forwarding tests only. A fake backend never loads official native code. */
public class OfficialControllerSessionTest {
    private static StreamerRoomConfig room(String token, List<String> servers) {
        return new StreamerRoomConfig(token, servers, 8000, 8000, "", "", "", "",
                Collections.emptyList(), "");
    }

    private static final class Fixture {
        final FakeController nativeApi = new FakeController();
        final AtomicInteger released = new AtomicInteger();
        final AtomicInteger received = new AtomicInteger();
        final OfficialControllerSession session = new OfficialControllerSession(
                nativeApi, (handle, config) -> 0, released::incrementAndGet);
        void initialize() {
            session.initialize("/logs", "/original/config.json", new StreamerController.Delegate() {
                @Override public void onReceiveControlData(long handle, byte[] bytes) { received.incrementAndGet(); }
            });
        }
        void join() { session.loginRoom(room("server-issued-token", Collections.singletonList("wss://example.invalid"))); }
    }

    @Test public void rejectsMissingRoomInputsAndUseAfterClose() {
        Fixture f = new Fixture();
        assertThrows(IllegalStateException.class, () -> f.session.sendControl(new byte[]{1}));
        f.initialize();
        assertThrows(IllegalArgumentException.class, () -> f.session.loginRoom(room("", Collections.singletonList("server"))));
        assertThrows(IllegalArgumentException.class, () -> f.session.loginRoom(room("token", Collections.emptyList())));
        assertFalse(f.nativeApi.calls.contains("login"));
        f.session.close();
        f.session.close();
        assertEquals(Arrays.asList("initialize", "finalize"), f.nativeApi.calls);
        assertEquals(1, f.released.get());
        assertThrows(IllegalStateException.class, f.session::version);
    }

    @Test public void zeroRoomHandleDoesNotCauseInvalidRoomCleanup() {
        Fixture f = new Fixture();
        f.nativeApi.loginHandle = 0;
        f.initialize();
        assertThrows(IllegalStateException.class, f::join);
        f.session.close();
        assertEquals(Arrays.asList("initialize", "login", "finalize"), f.nativeApi.calls);
    }

    @Test public void forwardsOriginalPayloadAndSystemTimezoneWithoutExtraFraming() {
        Fixture f = new Fixture();
        f.initialize();
        f.join();
        byte[] options = {8, 1, 72, 3};
        f.session.connect(options, "control-id");
        assertArrayEquals(options, f.nativeApi.options);
        assertEquals("control-id", f.nativeApi.controlId);
        assertEquals(ZoneId.systemDefault().getId(), f.nativeApi.timezone);
        byte[] data = {123, 34, 97, 34, 58, 49, 125};
        f.session.sendControl(data);
        assertArrayEquals(data, f.nativeApi.lastControl);
        f.session.requestConnectionStats();
        assertTrue(f.nativeApi.calls.contains("stats"));
        assertThrows(IllegalStateException.class, () -> f.session.connect(options, "again"));
        f.session.close();
        assertEquals(Arrays.asList("disconnect", "exit", "finalize"),
                f.nativeApi.calls.subList(f.nativeApi.calls.size() - 3, f.nativeApi.calls.size()));
    }

    @Test public void failedConnectStillDisconnectsAndExitsBeforeFinalize() {
        Fixture f = new Fixture();
        f.initialize();
        f.join();
        f.nativeApi.connectCode = -5;
        assertThrows(IllegalStateException.class, () -> f.session.connect(new byte[]{1}, "id"));
        f.session.close();
        assertEquals(Arrays.asList("initialize", "login", "connect", "disconnect", "exit", "finalize"), f.nativeApi.calls);
    }

    @Test public void mediaStopFailureDoesNotSkipOtherResourcesOrRoomTeardown() {
        Fixture f = new Fixture();
        f.initialize();
        f.join();
        f.session.connect(new byte[]{1}, "id");
        f.session.startAudioRender(new AudioRendererConfig(4));
        f.session.startAudioRender(new AudioRendererConfig(4));
        f.session.startAudioCapture(new AudioCaptureConfig(1, 7, null));
        f.nativeApi.OnReceiveControlData(42, new byte[]{1});
        assertEquals(1, f.received.get());
        f.nativeApi.stopAudioCode = -7;
        IllegalStateException failure = assertThrows(IllegalStateException.class, f.session::close);
        assertEquals(1, failure.getSuppressed().length);
        assertEquals(Arrays.asList("initialize", "login", "connect", "audio:4", "capture:7",
                "stop-audio:4", "stop-capture:7", "disconnect", "exit", "finalize"), f.nativeApi.calls);
        assertEquals(1, f.released.get());
        f.nativeApi.OnReceiveControlData(42, new byte[]{2});
        assertEquals(1, f.received.get());
        f.session.close();
        assertEquals(1, f.released.get());
    }

    @Test public void failedStartIsNotTreatedAsAnActiveMediaTrack() {
        Fixture f = new Fixture();
        f.initialize();
        f.join();
        f.nativeApi.startAudioCode = -1;
        assertThrows(IllegalStateException.class, () -> f.session.startAudioRender(new AudioRendererConfig(8)));
        f.session.close();
        assertFalse(f.nativeApi.calls.contains("stop-audio:8"));
    }

    @Test public void failedInitializationIsFinalized() {
        Fixture f = new Fixture();
        f.nativeApi.initializeCode = -1;
        assertThrows(IllegalStateException.class, f::initialize);
        f.session.close();
        assertEquals(Arrays.asList("initialize", "finalize"), f.nativeApi.calls);
        assertEquals(1, f.released.get());
    }

    @Test public void failedFinalizeDoesNotReleaseUncertainGlobalNativeState() {
        Fixture f = new Fixture();
        f.initialize();
        f.nativeApi.finalizeCode = -1;
        assertThrows(IllegalStateException.class, f.session::close);
        assertEquals(0, f.released.get());
        f.session.close();
        assertEquals(Arrays.asList("initialize", "finalize"), f.nativeApi.calls);
    }

    private static final class FakeController extends StreamerController {
        final List<String> calls = new ArrayList<>();
        long loginHandle = 42;
        int initializeCode, finalizeCode, connectCode, startAudioCode, stopAudioCode;
        byte[] options, lastControl;
        String controlId, timezone;
        @Override public int initialize(String log, String config) { calls.add("initialize"); return initializeCode; }
        @Override public int shutdown() { calls.add("finalize"); return finalizeCode; }
        @Override public long loginRoom(StreamerRoomConfig config) { calls.add("login"); return loginHandle; }
        @Override public int connect(long room, byte[] options, String id, String zone) {
            calls.add("connect"); this.options = options.clone(); controlId = id; timezone = zone; return connectCode;
        }
        @Override public int disconnect(long room) { calls.add("disconnect"); return 0; }
        @Override public int exitRoom(long room) { calls.add("exit"); return 0; }
        @Override public String getStreamerVersion() { return "V4.14.2"; }
        @Override public String getDecodeCapability() { return "{}"; }
        @Override public int getConnectionStats(long room) { calls.add("stats"); return 0; }
        @Override public int sendControlData(long room, byte[] bytes) { lastControl = bytes.clone(); return 0; }
        @Override public int sendTextData(long room, byte[] bytes) { return 0; }
        @Override public int sendFileData(long room, byte[] bytes) { return 0; }
        @Override public int sendBinaryData(long room, byte[] bytes) { return 0; }
        @Override public int startAudioRender(long room, AudioRendererConfig config) { calls.add("audio:" + config.getAudioTrackIndex()); return startAudioCode; }
        @Override public int startAudioCapture(long room, AudioCaptureConfig config) { calls.add("capture:" + config.getAudioTrackIndex()); return 0; }
        @Override public int stopVideoRender(long room, int track) { calls.add("stop-video:" + track); return 0; }
        @Override public int stopAudioRender(long room, int track) { calls.add("stop-audio:" + track); return stopAudioCode; }
        @Override public int stopAudioCapture(long room, int track) { calls.add("stop-capture:" + track); return 0; }
        @Override public int switchIceNetwork(long room, IceNetworkConfig config) { return 0; }
    }
}
