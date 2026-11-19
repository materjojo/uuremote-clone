package com.example.uuremote;

import android.app.Activity;
import android.content.Context;
import android.graphics.Color;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

/**
 * 主界面（与 macOS/Windows 同结构）：设备 / 文件传输 / 终端 / 设置 四页。
 * 文案来自官方 Localizable.strings（1812 条，values/values-zh-rCN/values-en）。
 */
public class MainActivity extends Activity {
    private LinearLayout navDevices, navFiles, navTerminal, navSettings;
    private View pageDevices, pageFiles, pageTerminal, pageSettings;
    private StreamerSession session;
    private RemoteView remoteView;
    private ClipboardSync clipboard;

    private static final int ACCENT = Color.parseColor("#5CD96B");
    private static final int MUTED = Color.parseColor("#9AA0A6");
    private static final int CARD = Color.parseColor("#1C1E22");

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.parseColor("#0E0F11"));

        TextView title = new TextView(this);
        title.setText(L("uuremote", "网易UU远程"));
        title.setTextColor(Color.WHITE);
        title.setTextSize(22);
        title.setPadding(48, 48, 48, 24);
        root.addView(title);

        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setLayoutParams(new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        pageDevices = buildDevicesPage();
        pageFiles = buildPlaceholder(L("filetransfer", "文件传输"), "连接后拖拽文件传输");
        pageTerminal = buildPlaceholder(L("terminal", "终端"), "tmux 会话管理");
        pageSettings = buildSettingsPage();
        content.addView(pageDevices);
        content.addView(pageFiles);
        content.addView(pageTerminal);
        content.addView(pageSettings);
        pageFiles.setVisibility(View.GONE);
        pageTerminal.setVisibility(View.GONE);
        pageSettings.setVisibility(View.GONE);
        root.addView(content);

        // 底部导航（与官方 WindowGroup 的四页对应）
        LinearLayout nav = new LinearLayout(this);
        nav.setOrientation(LinearLayout.HORIZONTAL);
        nav.setBackgroundColor(Color.parseColor("#16171A"));
        navDevices = navItem(L("device", "设备"), v -> selectPage(0));
        navFiles = navItem(L("filetransfer", "文件传输"), v -> selectPage(1));
        navTerminal = navItem("终端", v -> selectPage(2));
        navSettings = navItem(L("setting___", "设置"), v -> selectPage(3));
        nav.addView(navDevices);
        nav.addView(navFiles);
        nav.addView(navTerminal);
        nav.addView(navSettings);
        root.addView(nav);

        ScrollView scroll = new ScrollView(this);
        scroll.addView(root);
        setContentView(scroll);
        selectPage(0);
    }

    /** 按官方文案 key 查找本地化字符串，找不到时用默认值 */
    private String L(String key, String fallback) {
        int id = getResources().getIdentifier(key, "string", getPackageName());
        return id != 0 ? getString(id) : fallback;
    }

    private LinearLayout navItem(String text, View.OnClickListener click) {
        TextView t = new TextView(this);
        t.setText(text);
        t.setTextColor(MUTED);
        t.setTextSize(12);
        t.setGravity(Gravity.CENTER);
        t.setPadding(0, 28, 0, 28);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        t.setLayoutParams(lp);
        t.setOnClickListener(click);
        LinearLayout wrapper = new LinearLayout(this);
        wrapper.addView(t);
        return wrapper;
    }

    private void selectPage(int index) {
        pageDevices.setVisibility(index == 0 ? View.VISIBLE : View.GONE);
        pageFiles.setVisibility(index == 1 ? View.VISIBLE : View.GONE);
        pageTerminal.setVisibility(index == 2 ? View.VISIBLE : View.GONE);
        pageSettings.setVisibility(index == 3 ? View.VISIBLE : View.GONE);
        ((TextView) navDevices.getChildAt(0)).setTextColor(index == 0 ? ACCENT : MUTED);
        ((TextView) navFiles.getChildAt(0)).setTextColor(index == 1 ? ACCENT : MUTED);
        ((TextView) navTerminal.getChildAt(0)).setTextColor(index == 2 ? ACCENT : MUTED);
        ((TextView) navSettings.getChildAt(0)).setTextColor(index == 3 ? ACCENT : MUTED);
    }

    private View buildDevicesPage() {
        LinearLayout page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setPadding(48, 12, 48, 24);

        String[][] devices = {
                {"工作室主机", "Windows · 4.48.1"},
                {"MacBook Pro", "macOS · 4.48.1"}
        };
        for (String[] d : devices) {
            page.addView(deviceCard(d[0], d[1]));
        }

        TextView footer = new TextView(this);
        footer.setText("协议消息 " + Gvpb.schemaMessageCount() + " 条 · 云设备已剔除");
        footer.setTextColor(MUTED);
        footer.setTextSize(10);
        page.addView(footer);
        return page;
    }

    private View deviceCard(String name, String meta) {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.HORIZONTAL);
        card.setBackgroundColor(CARD);
        card.setPadding(32, 32, 32, 32);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.bottomMargin = 20;
        card.setLayoutParams(lp);

        LinearLayout texts = new LinearLayout(this);
        texts.setOrientation(LinearLayout.VERTICAL);
        TextView n = new TextView(this);
        n.setText(name);
        n.setTextColor(Color.WHITE);
        n.setTextSize(16);
        TextView m = new TextView(this);
        m.setText(meta);
        m.setTextColor(MUTED);
        m.setTextSize(11);
        texts.addView(n);
        texts.addView(m);
        card.addView(texts, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        Button connect = new Button(this);
        connect.setText("远程控制");
        connect.setTextColor(ACCENT);
        connect.setBackgroundColor(Color.TRANSPARENT);
        connect.setOnClickListener(v -> connectRemote(name));
        card.addView(connect);
        return card;
    }

    private void connectRemote(String name) {
        Toast.makeText(this, "连接 " + name + "（协议 " + Gvpb.schemaMessageCount() + " 条）",
                Toast.LENGTH_SHORT).show();
        // 远控画面容器：与官方一致用 SurfaceViewRenderer
        LinearLayout stage = new LinearLayout(this);
        stage.setOrientation(LinearLayout.VERTICAL);
        stage.setBackgroundColor(Color.BLACK);
        remoteView = new RemoteView(this);
        remoteView.setLayoutParams(new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 800));
        stage.addView(remoteView);
        Button back = new Button(this);
        back.setText("断开");
        back.setTextColor(ACCENT);
        back.setBackgroundColor(Color.TRANSPARENT);
        back.setOnClickListener(v -> {
            if (session != null) { session.stop(); session = null; }
            setContentView(buildRootView());
        });
        stage.addView(back);
        setContentView(stage);

        ClipboardSync clip = new ClipboardSync(this, session::sendControl);
        clipboard = clip;
        clip.start();
        session = new StreamerSession(this, new StreamerSession.Listener() {
            @Override public void onOffer(String sdp) { }
            @Override public void onCandidate(org.webrtc.IceCandidate c) { }
            @Override public void onControl(byte[] data) { clip.apply(data); }
            @Override public void onState(String state) {
                runOnUiThread(() -> Toast.makeText(MainActivity.this, "连接状态：" + state,
                        Toast.LENGTH_SHORT).show());
            }
        });
        session.start();
    }

    private View buildRootView() { return getWindow().getDecorView(); }

    private View buildPlaceholder(String title, String sub) {
        LinearLayout p = new LinearLayout(this);
        p.setOrientation(LinearLayout.VERTICAL);
        p.setGravity(Gravity.CENTER);
        TextView t = new TextView(this);
        t.setText(title);
        t.setTextColor(Color.WHITE);
        t.setTextSize(20);
        t.setGravity(Gravity.CENTER);
        TextView s = new TextView(this);
        s.setText(sub);
        s.setTextColor(MUTED);
        s.setTextSize(12);
        s.setGravity(Gravity.CENTER);
        p.addView(t);
        p.addView(s);
        return p;
    }

    private View buildSettingsPage() {
        LinearLayout p = new LinearLayout(this);
        p.setOrientation(LinearLayout.VERTICAL);
        p.setPadding(48, 12, 48, 24);
        String[] items = {
                L("autostart", "开机自启动"), "自动创建虚拟屏", "关闭窗口时", "移动设备传输文件存储路径",
                "允许同账号控制本设备"
        };
        for (String item : items) {
            TextView t = new TextView(this);
            t.setText(item);
            t.setTextColor(Color.WHITE);
            t.setTextSize(14);
            t.setPadding(0, 24, 0, 24);
            p.addView(t);
        }
        return p;
    }
}
