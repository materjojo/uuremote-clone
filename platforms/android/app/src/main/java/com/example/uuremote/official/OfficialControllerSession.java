package com.example.uuremote.official;

import com.remote.streamer.controller.AndroidStreamerController;
import com.remote.streamer.controller.StreamerController;
import com.remote.streamer.model.AudioCaptureConfig;
import com.remote.streamer.model.AudioRendererConfig;
import com.remote.streamer.model.IceNetworkConfig;
import com.remote.streamer.model.StreamerRoomConfig;
import com.remote.streamer.model.VideoRendererConfig;

import java.time.ZoneId;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Objects;
import java.util.Set;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.IntSupplier;

/**
 * Owns one official Android controller engine and its room/media lifetime.
 *
 * Calls recovered from ControllerService/AndroidControllerService are used
 * directly: the native core owns signaling, ICE, codecs and channel framing.
 * Room configuration and serialized ConnectOptions must come from the room/API
 * layer. This class does not invent a signaling endpoint or report connected
 * after merely submitting connect(). Native callbacks retain their original
 * room handles/status codes and thread semantics; the UI must dispatch them.
 */
public final class OfficialControllerSession implements AutoCloseable {
    private static final AtomicBoolean ENGINE_OWNED = new AtomicBoolean();

    interface VideoRenderer {
        int start(long room, VideoRendererConfig config);
    }

    private final StreamerController controller;
    private final VideoRenderer videoRenderer;
    private final Runnable releaseEngine;
    private final Set<Integer> videoTracks = new LinkedHashSet<>();
    private final Set<Integer> audioTracks = new LinkedHashSet<>();
    private final Set<Integer> captureTracks = new LinkedHashSet<>();
    private boolean initializationAttempted;
    private boolean initialized;
    private boolean closed;
    private boolean connectionAttempted;
    private long room;

    public static OfficialControllerSession open(String logPath, String configPath,
                                                 StreamerController.Delegate delegate) {
        Objects.requireNonNull(logPath, "logPath");
        Objects.requireNonNull(configPath, "configPath");
        Objects.requireNonNull(delegate, "delegate");
        if (!ENGINE_OWNED.compareAndSet(false, true)) {
            throw new IllegalStateException("The official controller engine already has an owner");
        }
        final AndroidStreamerController nativeController;
        try {
            nativeController = new AndroidStreamerController();
        } catch (RuntimeException | LinkageError error) {
            ENGINE_OWNED.set(false);
            throw error;
        }
        OfficialControllerSession session = new OfficialControllerSession(
                nativeController, nativeController::startVideoRender, () -> ENGINE_OWNED.set(false));
        try {
            session.initialize(logPath, configPath, delegate);
            return session;
        } catch (RuntimeException | LinkageError error) {
            try { session.close(); }
            catch (RuntimeException | LinkageError cleanup) { error.addSuppressed(cleanup); }
            throw error;
        }
    }

    // Injection keeps lifecycle tests independent of native loading/Android hardware.
    OfficialControllerSession(StreamerController controller, VideoRenderer renderer, Runnable releaseEngine) {
        this.controller = Objects.requireNonNull(controller);
        this.videoRenderer = Objects.requireNonNull(renderer);
        this.releaseEngine = Objects.requireNonNull(releaseEngine);
    }

    synchronized void initialize(String logPath, String configPath, StreamerController.Delegate delegate) {
        if (closed || initializationAttempted) throw new IllegalStateException("Engine cannot be initialized again");
        initializationAttempted = true;
        check("Initialize", controller.initialize(logPath, configPath));
        initialized = true;
        controller.setDelegate(Objects.requireNonNull(delegate));
    }

    public synchronized String version() {
        requireEngine();
        return controller.getStreamerVersion();
    }

    public synchronized String decodeCapability() {
        requireEngine();
        return controller.getDecodeCapability();
    }

    public synchronized long loginRoom(StreamerRoomConfig config) {
        requireEngine();
        Objects.requireNonNull(config, "config");
        if (room != 0) throw new IllegalStateException("This session already owns a room");
        if (config.getToken().isEmpty() || config.getSignalServers().length == 0) {
            throw new IllegalArgumentException("Room token and signaling servers are required");
        }
        long handle = controller.loginRoom(config);
        if (handle <= 0) throw new IllegalStateException("LoginRoom did not return a valid handle: " + handle);
        room = handle;
        return handle;
    }

    public synchronized void connect(byte[] connectOptions, String appControlId) {
        requireRoom();
        Objects.requireNonNull(connectOptions, "connectOptions");
        Objects.requireNonNull(appControlId, "appControlId");
        if (connectOptions.length == 0 || appControlId.isEmpty()) {
            throw new IllegalArgumentException("Serialized ConnectOptions and appControlId are required");
        }
        if (connectionAttempted) throw new IllegalStateException("Connect was already submitted for this session");
        connectionAttempted = true; // clean up even when native connection setup returns an error
        check("Connect", controller.connect(room, connectOptions, appControlId, ZoneId.systemDefault().getId()));
    }

    public synchronized void startVideoRender(VideoRendererConfig config) {
        requireRoom();
        Objects.requireNonNull(config, "config");
        // The official Android service stops the old surface before replacing it.
        for (int track : new ArrayList<>(videoTracks)) {
            check("StopVideoRender", controller.stopVideoRender(room, track));
            videoTracks.remove(track);
        }
        check("StartVideoRender", videoRenderer.start(room, config));
        videoTracks.add(config.getVideoTrackIndex());
    }

    public synchronized void startAudioRender(AudioRendererConfig config) {
        requireRoom();
        Objects.requireNonNull(config, "config");
        if (audioTracks.contains(config.getAudioTrackIndex())) return;
        check("StartAudioRender", controller.startAudioRender(room, config));
        audioTracks.add(config.getAudioTrackIndex());
    }

    /** Caller obtains RECORD_AUDIO/MediaProjection permission before supplying capture config. */
    public synchronized void startAudioCapture(AudioCaptureConfig config) {
        requireRoom();
        Objects.requireNonNull(config, "config");
        if (captureTracks.contains(config.getAudioTrackIndex())) return;
        check("StartAudioCapture", controller.startAudioCapture(room, config));
        captureTracks.add(config.getAudioTrackIndex());
    }

    /** Payload may be original protobuf or UTF-8 JSON; bytes are passed unchanged. */
    public synchronized void sendControl(byte[] data) {
        requireRoom();
        check("SendControlData", controller.sendControlData(room, Objects.requireNonNull(data)));
    }

    public synchronized void sendTextData(byte[] data) {
        requireRoom();
        check("SendTextData", controller.sendTextData(room, Objects.requireNonNull(data)));
    }

    public synchronized void sendFileData(byte[] data) {
        requireRoom();
        check("SendFileData", controller.sendFileData(room, Objects.requireNonNull(data)));
    }

    public synchronized void sendBinaryData(byte[] data) {
        requireRoom();
        check("SendBinaryData", controller.sendBinaryData(room, Objects.requireNonNull(data)));
    }

    public synchronized void requestConnectionStats() {
        requireRoom();
        // Stats arrive through native callbacks; the return value is a status code.
        check("GetConnectionStats", controller.getConnectionStats(room));
    }

    public synchronized void switchIceNetwork(IceNetworkConfig config) {
        requireRoom();
        check("SwitchIceNetwork", controller.switchIceNetwork(room, Objects.requireNonNull(config)));
    }

    @Override public synchronized void close() {
        if (closed) return;
        closed = true;
        controller.setDelegate(null);
        List<RuntimeException> errors = new ArrayList<>();
        if (room != 0) {
            for (int track : videoTracks) cleanup(errors, "StopVideoRender", () -> controller.stopVideoRender(room, track));
            for (int track : audioTracks) cleanup(errors, "StopAudioRender", () -> controller.stopAudioRender(room, track));
            for (int track : captureTracks) cleanup(errors, "StopAudioCapture", () -> controller.stopAudioCapture(room, track));
            if (connectionAttempted) cleanup(errors, "Disconnect", () -> controller.disconnect(room));
            cleanup(errors, "ExitRoom", () -> controller.exitRoom(room));
        }
        boolean finalized = !initializationAttempted || cleanup(errors, "Finalize", controller::shutdown);
        room = 0;
        videoTracks.clear();
        audioTracks.clear();
        captureTracks.clear();
        // A failed Finalize leaves native global state uncertain: do not allow a
        // second owner to initialize over it in the same application process.
        if (finalized) releaseEngine.run();
        if (!errors.isEmpty()) {
            IllegalStateException failure = new IllegalStateException("Official controller cleanup failed");
            for (RuntimeException error : errors) failure.addSuppressed(error);
            throw failure;
        }
    }

    private static boolean cleanup(List<RuntimeException> errors, String operation, IntSupplier action) {
        try { check(operation, action.getAsInt()); return true; }
        catch (RuntimeException | LinkageError error) {
            errors.add(new IllegalStateException(operation + " failed during cleanup", error));
            return false;
        }
    }

    private void requireEngine() {
        if (!initialized || closed) throw new IllegalStateException("Official engine is not available");
    }

    private void requireRoom() {
        requireEngine();
        if (room == 0) throw new IllegalStateException("LoginRoom must succeed first");
    }

    private static void check(String operation, int code) {
        if (code != 0) throw new IllegalStateException(operation + " returned " + code);
    }
}
