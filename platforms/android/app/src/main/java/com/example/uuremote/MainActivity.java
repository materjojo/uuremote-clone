package com.example.uuremote;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.media.projection.MediaProjectionManager;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.ResultReceiver;
import android.provider.Settings;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.*;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import org.json.JSONArray;
import org.json.JSONObject;
import org.webrtc.IceCandidate;
import org.webrtc.VideoTrack;
import gv_pb.Message;
import gv_pb.InputEvent;
import gv_pb.TouchEvent;
import gv_pb.TouchEventPoint;

/** Device/assistance/profile navigation follows the recovered Android tabs, minus cloud. */
public class MainActivity extends Activity {
    private static final int BLUE = 0xff3482ff, INK = 0xff20232a, MUTED = 0xff8b9099, BG = 0xfff5f6f8;
    private static final int SHARE_REQUEST = 4001;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService network = Executors.newCachedThreadPool();
    private PeerAPI.Store store;
    private List<PeerAPI.Invitation> devices = new ArrayList<>();
    private LinearLayout root, page, nav;
    private FrameLayout body;
    private TextView title, hostStatus, remoteStatus;
    private EditText serverField;
    private StreamerSession session;
    private PeerAPI.Mailbox mailbox;
    private ClipboardSync clipboard;
    private RemoteView remoteView;
    private volatile boolean receiving, destroyed;
    private boolean hostMode, connecting;
    private PeerAPI hostApi;
    private String pendingId;
    private long sequence, sessionGeneration;
    private int tab;
    private float touchX, touchY;
    private long touchStart;

    @Override public void onCreate(Bundle saved) {
        super.onCreate(saved);
        getWindow().setStatusBarColor(Color.WHITE); getWindow().setNavigationBarColor(Color.WHITE);
        getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
        store = new PeerAPI.Store(this);
        try { devices = store.devices(); } catch (Exception e) { toast("读取设备失败：" + e.getMessage()); }
        root = column(); root.setBackgroundColor(BG);
        LinearLayout header = new LinearLayout(this); header.setGravity(Gravity.CENTER_VERTICAL); header.setPadding(dp(20), dp(16), dp(16), dp(14));
        title = text("我的设备", 23, INK); header.addView(title, new LinearLayout.LayoutParams(0, -2, 1));
        Button add = button("＋", v -> addDevice()); header.addView(add); root.addView(header);
        body = new FrameLayout(this); root.addView(body, new LinearLayout.LayoutParams(-1, 0, 1));
        nav = new LinearLayout(this); nav.setBackgroundColor(Color.WHITE); root.addView(nav);
        setContentView(root); selectPage(0);
    }
    private int dp(float value) { return (int)(value * getResources().getDisplayMetrics().density + .5f); }
    private LinearLayout column() { LinearLayout v = new LinearLayout(this); v.setOrientation(LinearLayout.VERTICAL); return v; }
    private TextView text(String value, int size, int color) { TextView t = new TextView(this); t.setText(value); t.setTextSize(size); t.setTextColor(color); return t; }
    private Button button(String label, View.OnClickListener action) {
        Button b = new Button(this); b.setText(label); b.setTextColor(BLUE); b.setAllCaps(false); b.setOnClickListener(action); return b;
    }
    private void toast(String message) { Toast.makeText(this, message, Toast.LENGTH_LONG).show(); }
    private void card(LinearLayout v) {
        GradientDrawable background = new GradientDrawable(); background.setColor(Color.WHITE); background.setCornerRadius(dp(14)); v.setBackground(background);
        v.setPadding(dp(18), dp(16), dp(18), dp(16));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2); lp.bottomMargin = dp(12); v.setLayoutParams(lp);
    }
    private void selectPage(int selected) {
        tab = selected;
        title.setText(new String[]{"我的设备", "远程协助", "我的"}[tab]);
        nav.removeAllViews();
        String[] names = {"我的设备", "远程协助", "我的"};
        int[] normal = {R.drawable.ui_tab_devices_normal, R.drawable.ui_tab_assist_normal, R.drawable.ui_tab_mine_normal};
        int[] active = {R.drawable.ui_tab_devices_selected, R.drawable.ui_tab_assist_selected, R.drawable.ui_tab_mine_selected};
        for (int i = 0; i < names.length; i++) {
            final int index = i; LinearLayout item = column(); item.setGravity(Gravity.CENTER); item.setPadding(0, dp(12), 0, dp(10));
            ImageView icon = new ImageView(this); icon.setImageResource(selected == i ? active[i] : normal[i]); item.addView(icon, new LinearLayout.LayoutParams(dp(26), dp(26)));
            TextView label = text(names[i], 11, selected == i ? BLUE : INK); label.setPadding(0, dp(4), 0, 0); item.addView(label);
            item.setOnClickListener(v -> selectPage(index)); nav.addView(item, new LinearLayout.LayoutParams(0, -2, 1));
        }
        body.removeAllViews(); ScrollView scroll = new ScrollView(this); page = column(); page.setPadding(dp(16), dp(8), dp(16), dp(12)); scroll.addView(page); body.addView(scroll);
        if (selected == 0) showDevices();
        else if (selected == 1) showReceiving();
        else showProfile();
    }
    private void showDevices() {
        if (devices.isEmpty()) {
            LinearLayout empty = column(); empty.setGravity(Gravity.CENTER); empty.setPadding(dp(16), dp(64), dp(16), dp(30));
            ImageView image = new ImageView(this); image.setImageResource(R.drawable.ui_empty_computer); image.setAdjustViewBounds(true); empty.addView(image, new LinearLayout.LayoutParams(dp(160), dp(130)));
            TextView heading = text("还没有添加设备", 18, INK); heading.setPadding(0, dp(24), 0, dp(8)); empty.addView(heading);
            TextView help = text("在另一台设备开启接收，复制配对码后添加", 13, MUTED); help.setGravity(Gravity.CENTER); empty.addView(help);
            empty.addView(button("添加设备", v -> addDevice())); page.addView(empty); return;
        }
        for (PeerAPI.Invitation device : devices) {
            LinearLayout item = column(); card(item);
            LinearLayout line = new LinearLayout(this); line.setGravity(Gravity.CENTER_VERTICAL);
            ImageView icon = new ImageView(this); icon.setImageResource(device.platform.equals("mac") ? R.drawable.ui_device_mac :
                    device.platform.equals("windows") ? R.drawable.ui_device_win : R.drawable.ui_device_android);
            line.addView(icon, new LinearLayout.LayoutParams(dp(44), dp(44)));
            TextView name = text(device.name, 17, INK); name.setPadding(dp(12), 0, 0, 0); line.addView(name, new LinearLayout.LayoutParams(0, -2, 1));
            line.addView(text("已配对", 11, MUTED)); item.addView(line);
            item.addView(button("远程控制", v -> connect(device)));
            item.setOnLongClickListener(v -> { new AlertDialog.Builder(this).setTitle("移除设备？").setMessage(device.name)
                    .setPositiveButton("移除", (d, w) -> { devices.remove(device); saveDevices(); selectPage(0); }).setNegativeButton("取消", null).show(); return true; });
            page.addView(item);
        }
    }
    private void showReceiving() {
        LinearLayout panel = column(); card(panel); panel.addView(text("接收远程连接", 18, INK));
        hostStatus = text(receiving ? "等待连接 · 每次连接需本机确认" : "开启后可生成本机配对码", 13, MUTED); panel.addView(hostStatus);
        serverField = new EditText(this); serverField.setSingleLine(true); serverField.setText(store.server()); serverField.setHint("自建信令服务地址"); serverField.setInputType(17); serverField.setEnabled(!receiving); panel.addView(serverField);
        panel.addView(button(receiving ? "停止接收" : "开启接收", v -> { if (receiving) stopReceiving(); else startReceiving(); }));
        if (receiving) panel.addView(button("复制本机配对码", v -> {
            try {
                String code = new PeerAPI.Invitation(store.server(), store.id, store.pairKey,
                        android.os.Build.MANUFACTURER + " " + android.os.Build.MODEL, "android").code();
                ((ClipboardManager)getSystemService(CLIPBOARD_SERVICE)).setPrimaryClip(ClipData.newPlainText("配对码", code)); toast("配对码已复制");
            } catch (Exception e) { toast(e.getMessage()); }
        }));
        page.addView(panel);
        page.addView(text("两端使用同一自建信令服务。媒体通过 IPv6 / IPv4 尝试直连；直连失败时尝试已连接的 Tailscale。", 13, MUTED));
    }
    private void showProfile() {
        LinearLayout item = column(); card(item); item.addView(text(android.os.Build.MANUFACTURER + " " + android.os.Build.MODEL, 18, INK));
        item.addView(text("设备和配对信息仅保存在本机", 13, MUTED));
        item.addView(button("远程控制授权", v -> startActivity(new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))));
        item.addView(text("Android 被控需屏幕共享许可；触控还需在系统设置中开启本应用的无障碍服务。", 13, MUTED)); page.addView(item);
    }
    private void addDevice() {
        EditText code = new EditText(this); code.setHint("粘贴配对码"); code.setMinLines(3); code.setMaxLines(6);
        AlertDialog dialog = new AlertDialog.Builder(this).setTitle("添加设备").setView(code).setNegativeButton("取消", null).setPositiveButton("添加", null).create();
        dialog.setOnShowListener(d -> dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> {
            try {
                PeerAPI.Invitation value = PeerAPI.Invitation.parse(code.getText().toString());
                if (value.id.equals(store.id)) throw new IllegalArgumentException("不能把本机添加为远程设备");
                devices.removeIf(p -> p.id.equals(value.id) && p.server.equals(value.server)); devices.add(value); saveDevices(); dialog.dismiss(); selectPage(0);
            } catch (Exception e) { code.setError(e.getMessage()); }
        })); dialog.show();
    }
    private void saveDevices() { try { store.save(devices); } catch (Exception e) { toast(e.getMessage()); } }
    private void connect(PeerAPI.Invitation value) {
        disconnect(); connecting = true; long generation = sessionGeneration; showRemote("等待 " + value.name + " 确认连接…");
        network.execute(() -> {
            try {
                PeerAPI api = new PeerAPI(value.server);
                JSONObject result = api.request("/v1/connect", null, PeerAPI.description().put("target", value.id).put("key", value.key));
                String id = result.getString("id"), token = result.getString("token");
                main.post(() -> { if (connecting && !destroyed && generation == sessionGeneration) bindMailbox(api, id, token, false); });
            } catch (Exception e) { main.post(() -> { if (generation == sessionGeneration && !destroyed) { disconnect(); toast("连接失败：" + e.getMessage()); } }); }
        });
    }
    private void showRemote(String status) {
        LinearLayout stage = column(); stage.setBackgroundColor(Color.BLACK);
        remoteStatus = text(status, 13, Color.WHITE); remoteStatus.setPadding(dp(16), dp(12), dp(16), dp(12)); stage.addView(remoteStatus);
        if (session != null) {
            remoteView = new RemoteView(this, session.eglContext()); stage.addView(remoteView, new LinearLayout.LayoutParams(-1, 0, 1));
            remoteView.setOnTouchListener((view, event) -> {
                if (session == null) return true;
                float[] point = remoteView.normalize(event.getX(), event.getY()); if (point == null) return true;
                int type = event.getActionMasked() == MotionEvent.ACTION_DOWN ? 1 : event.getActionMasked() == MotionEvent.ACTION_UP ? 3 : event.getActionMasked() == MotionEvent.ACTION_CANCEL ? 4 : 2;
                TouchEvent touch = TouchEvent.newBuilder().setEventTypeValue(type).addTouchPoints(TouchEventPoint.newBuilder().setId(0).setX(point[0]).setY(point[1])).build();
                session.sendControl(Message.newBuilder().setSeq(++sequence).setTimestamp(System.currentTimeMillis()).setInputEvent(InputEvent.newBuilder().setTouchEvent(touch)).build().toByteArray());
                return true;
            });
        } else stage.addView(new View(this), new LinearLayout.LayoutParams(-1, 0, 1));
        LinearLayout actions = new LinearLayout(this);
        actions.addView(button("发送文本", v -> {
            EditText input = new EditText(this); input.setHint("输入要发送的文本");
            new AlertDialog.Builder(this).setTitle("发送文本到远程设备").setView(input).setNegativeButton("取消", null)
                    .setPositiveButton("发送", (d, which) -> {
                        try {
                            byte[] bytes = new JSONObject().put("action", "text_input").put("content", input.getText().toString())
                                    .toString().getBytes(java.nio.charset.StandardCharsets.UTF_8);
                            if (bytes.length <= 65536 && session != null) session.sendControl(bytes);
                        } catch (Exception e) { toast(e.getMessage()); }
                    }).show();
        }));
        actions.addView(button("断开连接", v -> disconnect())); stage.addView(actions); setContentView(stage);
    }
    private void createSession(boolean host) {
        hostMode = host;
        session = new StreamerSession(this, new StreamerSession.Listener() {
            @Override public void onOffer(String sdp) { signal("offer", "sdp", sdp); }
            @Override public void onAnswer(String sdp) { signal("answer", "sdp", sdp); }
            @Override public void onCandidate(IceCandidate c) {
                try { if (mailbox != null) mailbox.send("candidate", new JSONObject().put("candidate", c.sdp).put("sdpMid", c.sdpMid).put("sdpMLineIndex", c.sdpMLineIndex)); }
                catch (Exception e) { onError(e.getMessage()); }
            }
            @Override public void onVideo(VideoTrack track) { if (remoteView != null) remoteView.attach(track); }
            @Override public void onState(String state) {
                if (remoteStatus != null) remoteStatus.setText("连接状态：" + state);
                if (hostMode && hostStatus != null) hostStatus.setText("被控连接：" + state);
            }
            @Override public void onError(String error) { disconnect(); toast(error); }
            @Override public void onControl(byte[] data) {
                if (hostMode && data.length > 0 && data[0] == '{') {
                    try {
                        if (data.length <= 65536 && RemoteInputService.get() != null) {
                            JSONObject value = new JSONObject(new String(data, java.nio.charset.StandardCharsets.UTF_8));
                            if (value.optString("action").equals("text_input")) RemoteInputService.get().typeText(value.getString("content"));
                        }
                    } catch (Exception ignored) { }
                    return;
                }
                if (clipboard != null) clipboard.apply(data);
                if (!hostMode || RemoteInputService.get() == null) return;
                try {
                    Message msg = Message.parseFrom(data);
                    if (!msg.hasInputEvent() || !msg.getInputEvent().hasTouchEvent()) return;
                    TouchEvent touch = msg.getInputEvent().getTouchEvent(); if (touch.getTouchPointsCount() == 0) return;
                    TouchEventPoint p = touch.getTouchPoints(0);
                    if (touch.getEventTypeValue() == 1) { touchX = p.getX(); touchY = p.getY(); touchStart = System.currentTimeMillis(); }
                    if (touch.getEventTypeValue() == 3) {
                        if (Math.abs(p.getX() - touchX) + Math.abs(p.getY() - touchY) < .02f) RemoteInputService.get().tap(p.getX(), p.getY());
                        else RemoteInputService.get().swipe(touchX, touchY, p.getX(), p.getY(), System.currentTimeMillis() - touchStart);
                    }
                } catch (Exception ignored) { }
            }
        });
        clipboard = new ClipboardSync(this, data -> { if (session != null) session.sendControl(data); }); clipboard.start();
    }
    private void bindMailbox(PeerAPI api, String id, String token, boolean host) {
        long generation = sessionGeneration;
        mailbox = new PeerAPI.Mailbox(api, id, token, new PeerAPI.Mailbox.Listener() {
            @Override public void onError(String error) { if (generation == sessionGeneration && !destroyed) { disconnect(); toast(error); } }
            @Override public void onSignal(String type, JSONObject data) {
                if (generation != sessionGeneration || destroyed) return;
                try {
                    switch (type) {
                        case "accepted": createSession(false); showRemote("正在建立直连…"); session.start(); break;
                        case "offer": if (host && session != null) session.handleOffer(data.getString("sdp")); break;
                        case "answer": if (session != null) session.setRemoteAnswer(data.getString("sdp")); break;
                        case "candidate": if (session != null) session.addCandidate(new IceCandidate(data.optString("sdpMid", "0"), data.optInt("sdpMLineIndex"), data.getString("candidate"))); break;
                        case "close": disconnect(); toast("对端已拒绝或断开连接"); break;
                    }
                } catch (Exception e) { onError(e.getMessage()); }
            }
        }); mailbox.start();
    }
    private void signal(String type, String key, String value) { try { if (mailbox != null) mailbox.send(type, new JSONObject().put(key, value)); } catch (Exception e) { toast(e.getMessage()); } }
    private void startReceiving() {
        try {
            store.server(PeerAPI.endpoint(serverField.getText().toString())); hostApi = new PeerAPI(store.server()); receiving = true;
            network.execute(() -> {
                Set<String> seen = new HashSet<>();
                try {
                    hostApi.request("/v1/register", null, PeerAPI.description().put("id", store.id).put("key", store.ownerKey).put("pair_key", store.pairKey));
                    main.post(() -> { if (receiving) selectPage(1); });
                    while (receiving && !destroyed) {
                        JSONArray requests = hostApi.request("/v1/devices/" + store.id + "/inbox", store.ownerKey, null).getJSONArray("requests");
                        for (int i = 0; i < requests.length(); i++) {
                            JSONObject request = requests.getJSONObject(i); String id = request.getString("id"), name = request.getString("name");
                            if (seen.add(id)) main.post(() -> requestConsent(id, name));
                        }
                        Thread.sleep(2000);
                    }
                } catch (Exception e) { main.post(() -> { if (receiving && !destroyed) { stopReceiving(); toast(e.getMessage()); } }); }
            });
        } catch (Exception e) { receiving = false; toast(e.getMessage()); }
    }
    private void requestConsent(String id, String name) {
        if (!receiving || session != null || connecting || pendingId != null) { reject(id); return; }
        pendingId = id;
        new AlertDialog.Builder(this).setTitle("允许远程控制？").setMessage("“" + name + "”请求查看并控制此设备。")
                .setPositiveButton("允许", (d, which) -> startActivityForResult(((MediaProjectionManager)getSystemService(MEDIA_PROJECTION_SERVICE)).createScreenCaptureIntent(), SHARE_REQUEST))
                .setNegativeButton("拒绝", (d, which) -> { reject(id); pendingId = null; })
                .setOnCancelListener(d -> { reject(id); pendingId = null; }).show();
    }
    private void reject(String id) {
        PeerAPI.Mailbox box = new PeerAPI.Mailbox(hostApi, id, store.ownerKey, new PeerAPI.Mailbox.Listener() {
            @Override public void onSignal(String t, JSONObject d) { }
            @Override public void onError(String e) { }
        }); box.start(); box.send("close", null); main.postDelayed(box::close, 800);
    }
    @Override protected void onActivityResult(int request, int result, Intent data) {
        super.onActivityResult(request, result, data);
        if (request != SHARE_REQUEST || pendingId == null) return;
        String id = pendingId; pendingId = null;
        if (result != RESULT_OK || data == null || !receiving) { reject(id); return; }
        Intent service = new Intent(this, ScreenShareService.class);
        service.putExtra("ready", new ResultReceiver(main) { @Override protected void onReceiveResult(int result, Bundle extras) {
            if (result == 0) { if (hostMode) disconnect(); return; }
            if (destroyed || !receiving) { stopService(service); reject(id); return; }
            try {
                createSession(true);
                android.util.DisplayMetrics metrics = getResources().getDisplayMetrics();
                int width = (metrics.widthPixels / 2) * 2, height = (metrics.heightPixels / 2) * 2;
                session.prepareHost(MainActivity.this, data, width, height);
                bindMailbox(hostApi, id, store.ownerKey, true); mailbox.send("accept", null);
            } catch (Exception e) { reject(id); disconnect(); toast(e.getMessage()); }
        } }); startForegroundService(service);
    }
    private void stopReceiving() { receiving = false; if (hostMode) disconnect(); if (!destroyed) selectPage(1); }
    private void disconnect() {
        sessionGeneration++;
        connecting = false;
        if (mailbox != null) { PeerAPI.Mailbox box = mailbox; box.send("close", null); main.postDelayed(box::close, 600); mailbox = null; }
        if (clipboard != null) { clipboard.stop(); clipboard = null; }
        if (remoteView != null) { remoteView.release(); remoteView = null; }
        if (session != null) { session.stop(); session = null; }
        hostMode = false; remoteStatus = null; stopService(new Intent(this, ScreenShareService.class));
        if (root != null && !destroyed) setContentView(root);
    }
    @Override public void onBackPressed() { if (session != null || connecting) disconnect(); else super.onBackPressed(); }
    @Override public void onDestroy() { destroyed = true; receiving = false; disconnect(); network.shutdownNow(); super.onDestroy(); }
}
