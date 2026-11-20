package com.example.uuremote;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.Base64;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ArrayBlockingQueue;
import org.json.JSONArray;
import org.json.JSONObject;

/** Independent pairing/signaling. No vendor endpoints and no assumed remote devices. */
public final class PeerAPI {
    public static final class Invitation {
        public final String server, id, key, name, platform;
        public Invitation(String server, String id, String key, String name, String platform) {
            this.server = server; this.id = id; this.key = key; this.name = name; this.platform = platform;
        }
        public JSONObject json() throws Exception {
            return new JSONObject().put("v", 1).put("server", server).put("id", id).put("key", key)
                    .put("name", name).put("platform", platform);
        }
        public String code() throws Exception {
            return "uur1." + Base64.encodeToString(json().toString().getBytes(StandardCharsets.UTF_8),
                    Base64.URL_SAFE | Base64.NO_WRAP | Base64.NO_PADDING);
        }
        public static Invitation parse(String code) throws Exception {
            code = code.trim();
            if (!code.startsWith("uur1.") || code.length() > 8192) throw new IllegalArgumentException("请粘贴对端生成的配对码");
            JSONObject data = new JSONObject(new String(Base64.decode(code.substring(5), Base64.URL_SAFE), StandardCharsets.UTF_8));
            return from(data);
        }
        static Invitation from(JSONObject data) throws Exception {
            String server = endpoint(data.getString("server"));
            String id = data.getString("id"), key = data.getString("key"), platform = data.getString("platform"), name = data.getString("name");
            if (data.getInt("v") != 1 || !id.matches("[a-zA-Z0-9-]{16,64}") || !key.matches("[a-zA-Z0-9_-]{32,128}") ||
                    name.trim().isEmpty() || !(platform.equals("mac") || platform.equals("windows") || platform.equals("android")))
                throw new IllegalArgumentException("配对码版本或设备信息不正确");
            return new Invitation(server, id, key, name, platform);
        }
    }

    public static final class Store {
        private final SharedPreferences prefs;
        public final String id, ownerKey, pairKey;
        public Store(Context context) {
            prefs = context.getSharedPreferences("peer.v1", Context.MODE_PRIVATE);
            id = prefs.getString("id", UUID.randomUUID().toString());
            ownerKey = prefs.getString("owner", randomKey()); pairKey = prefs.getString("pair", randomKey());
            prefs.edit().putString("id", id).putString("owner", ownerKey).putString("pair", pairKey).apply();
        }
        public String server() { return prefs.getString("server", ""); }
        public void server(String value) { prefs.edit().putString("server", value).apply(); }
        public List<Invitation> devices() throws Exception {
            JSONArray data = new JSONArray(prefs.getString("devices", "[]"));
            List<Invitation> result = new ArrayList<>();
            for (int i = 0; i < data.length(); i++) result.add(Invitation.from(data.getJSONObject(i)));
            return result;
        }
        public void save(List<Invitation> devices) throws Exception {
            JSONArray data = new JSONArray();
            for (Invitation value : devices) data.put(value.json());
            prefs.edit().putString("devices", data.toString()).apply();
        }
        private static String randomKey() {
            byte[] bytes = new byte[32]; new SecureRandom().nextBytes(bytes);
            return Base64.encodeToString(bytes, Base64.URL_SAFE | Base64.NO_WRAP | Base64.NO_PADDING);
        }
    }

    public static String endpoint(String text) throws Exception {
        URI uri = new URI(text.trim());
        if (!("https".equals(uri.getScheme()) || "http".equals(uri.getScheme())) || uri.getHost() == null ||
                uri.getUserInfo() != null || uri.getQuery() != null || uri.getFragment() != null ||
                !(uri.getPath().isEmpty() || uri.getPath().equals("/")))
            throw new IllegalArgumentException("请输入自建信令服务根地址，例如 https://signal.example.org 或 http://局域网地址:8080");
        return text.trim().replaceAll("/+$", "");
    }
    private final String server;
    public PeerAPI(String server) throws Exception { this.server = endpoint(server); }
    public JSONObject request(String path, String token, JSONObject data) throws Exception {
        HttpURLConnection conn = (HttpURLConnection) new URI(server + path).toURL().openConnection();
        conn.setConnectTimeout(8000); conn.setReadTimeout(18000); conn.setInstanceFollowRedirects(false);
        if (token != null) conn.setRequestProperty("Authorization", "Bearer " + token);
        try {
            if (data != null) {
                conn.setRequestMethod("POST"); conn.setDoOutput(true); conn.setRequestProperty("Content-Type", "application/json");
                try (java.io.OutputStream out = conn.getOutputStream()) { out.write(data.toString().getBytes(StandardCharsets.UTF_8)); }
            }
            int status = conn.getResponseCode();
            InputStream stream = status >= 200 && status < 300 ? conn.getInputStream() : conn.getErrorStream();
            ByteArrayOutputStream buffer = new ByteArrayOutputStream();
            if (stream != null) try (InputStream in = stream) {
                byte[] block = new byte[8192]; int n;
                while ((n = in.read(block)) > 0) {
                    if (buffer.size() + n > 1024 * 1024) throw new IllegalStateException("信令响应过大");
                    buffer.write(block, 0, n);
                }
            }
            String content = buffer.toString(StandardCharsets.UTF_8.name());
            if (status < 200 || status >= 300) throw new IllegalStateException("信令服务 " + status + "：" + content.substring(0, Math.min(content.length(), 160)));
            return new JSONObject(content);
        } finally { conn.disconnect(); }
    }
    public static JSONObject description() throws Exception {
        return new JSONObject().put("name", Build.MANUFACTURER + " " + Build.MODEL).put("platform", "android");
    }

    public static final class Mailbox implements AutoCloseable {
        public interface Listener { void onSignal(String type, JSONObject data); void onError(String error); }
        private final PeerAPI api;
        private final String id, token;
        private final Listener listener;
        private final ExecutorService poller = Executors.newSingleThreadExecutor(), sender = Executors.newSingleThreadExecutor();
        private final ArrayBlockingQueue<JSONObject> outgoing = new ArrayBlockingQueue<>(256);
        private final Handler main = new Handler(Looper.getMainLooper());
        private volatile boolean closed;
        public Mailbox(PeerAPI api, String id, String token, Listener listener) { this.api = api; this.id = id; this.token = token; this.listener = listener; }
        public void start() {
            sender.execute(() -> {
                try {
                    while (!closed) {
                        JSONObject item = outgoing.take();
                        for (int retry = 0; ; retry++) {
                            try { api.request("/v1/sessions/" + id + "/signals", token, item); break; }
                            catch (Exception e) { if (closed) return; if (retry == 2) throw e; Thread.sleep(500); }
                        }
                    }
                } catch (InterruptedException ignored) { Thread.currentThread().interrupt(); }
                catch (Exception e) { error(e); }
            });
            poller.execute(() -> {
                int cursor = 0, failures = 0;
                while (!closed) {
                    try {
                        JSONObject result = api.request("/v1/sessions/" + id + "/signals?after=" + cursor, token, null);
                        failures = 0;
                        JSONArray events = result.getJSONArray("events");
                        for (int i = 0; i < events.length(); i++) {
                            JSONObject event = events.getJSONObject(i);
                            if (event.getInt("seq") <= cursor) continue;
                            String type = event.getString("type"); JSONObject data = event.getJSONObject("data");
                            main.post(() -> { if (!closed) listener.onSignal(type, data); });
                            cursor = event.getInt("seq");
                        }
                        if (result.optBoolean("closed")) return;
                    } catch (Exception e) {
                        if (closed) return;
                        if (++failures >= 3) { error(e); return; }
                        try { Thread.sleep(1000); } catch (InterruptedException ignored) { return; }
                    }
                }
            });
        }
        public void send(String type, JSONObject payload) {
            if (closed) return;
            try {
                if (!outgoing.offer(new JSONObject().put("type", type).put("data", payload == null ? new JSONObject() : payload)
                        .put("message_id", UUID.randomUUID().toString()))) throw new IllegalStateException("信令队列已满");
            } catch (Exception e) { error(e); }
        }
        private void error(Exception e) { main.post(() -> { if (!closed) listener.onError(e.getMessage()); }); }
        @Override public void close() { closed = true; poller.shutdownNow(); sender.shutdownNow(); outgoing.clear(); }
    }
}
