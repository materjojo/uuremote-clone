package com.example.uuremote;

import android.os.Handler;
import android.os.Looper;
import java.util.*;
import java.util.function.BooleanSupplier;
import java.util.function.Consumer;
import org.webrtc.IceCandidate;

/** Run on the main looper. Also gates candidates already embedded in local SDP. */
final class PeerCandidateGate {
    private final Handler main = new Handler(Looper.getMainLooper());
    private final Consumer<IceCandidate> emit;
    private final BooleanSupplier connected;
    private final Set<String> seen = new HashSet<>();
    private final Set<Integer> released = new HashSet<>();
    private final Map<Integer, List<IceCandidate>> queued = new HashMap<>();
    private boolean closed;
    PeerCandidateGate(Consumer<IceCandidate> emit, BooleanSupplier connected) { this.emit = emit; this.connected = connected; }
    static int stage(String value) {
        if (StreamerSession.isOverlay(value)) return 2;
        String[] fields = value.split(" +");
        return fields.length > 4 && fields[4].contains(":") ? 0 : 1;
    }
    void submit(IceCandidate value) {
        if (closed || !seen.add(value.sdpMid + ":" + value.sdpMLineIndex + ":" + value.sdp)) return;
        int stage = stage(value.sdp);
        if (stage == 0) { emit.accept(value); return; }
        if (released.contains(stage)) {
            if (!connected.getAsBoolean()) emit.accept(value);
            return;
        }
        if (!queued.containsKey(stage)) {
            queued.put(stage, new ArrayList<>());
            main.postDelayed(() -> {
                if (closed) return;
                released.add(stage);
                List<IceCandidate> values = queued.remove(stage);
                if (values != null) for (IceCandidate item : values) {
                    if (closed || connected.getAsBoolean()) break;
                    emit.accept(item);
                }
            }, stage == 1 ? 1200 : 8000);
        }
        queued.get(stage).add(value);
    }
    String signalSdp(String sdp) {
        String[] lines = sdp.split("[\\r\\n]+");
        Map<Integer, String> mids = new HashMap<>(); int media = -1;
        for (String line : lines) {
            if (line.startsWith("m=")) media++;
            if (line.startsWith("a=mid:")) mids.put(media, line.substring(6));
        }
        media = -1; StringBuilder output = new StringBuilder();
        for (String line : lines) {
            if (line.startsWith("m=")) media++;
            if (line.startsWith("a=candidate:")) submit(new IceCandidate(mids.getOrDefault(media, "0"), Math.max(0, media), line.substring(2)));
            else if (!line.isEmpty() && !line.equals("a=end-of-candidates")) output.append(line).append("\r\n");
        }
        return output.toString();
    }
    void close() { closed = true; main.removeCallbacksAndMessages(null); queued.clear(); }
}
