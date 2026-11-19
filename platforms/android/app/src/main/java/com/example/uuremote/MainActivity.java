package com.example.uuremote;

import android.app.Activity;
import android.graphics.Color;
import android.os.Bundle;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

public class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.parseColor("#0E0F11"));
        root.setPadding(48, 48, 48, 48);

        TextView title = new TextView(this);
        title.setText("网易UU远程");
        title.setTextColor(Color.WHITE);
        title.setTextSize(24);
        root.addView(title);

        TextView sub = new TextView(this);
        sub.setText("Android 端骨架 · 协议由 core/gvpb 提供");
        sub.setTextColor(Color.parseColor("#9AA0A6"));
        sub.setTextSize(12);
        sub.setPadding(0, 8, 0, 32);
        root.addView(sub);

        String[][] devices = {
                {"工作室主机", "Windows · 4.48.1"},
                {"MacBook Pro", "macOS · 4.48.1"}
        };
        for (String[] d : devices) {
            LinearLayout card = new LinearLayout(this);
            card.setOrientation(LinearLayout.HORIZONTAL);
            card.setBackgroundColor(Color.parseColor("#1C1E22"));
            card.setPadding(32, 32, 32, 32);
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            lp.bottomMargin = 20;
            card.setLayoutParams(lp);

            LinearLayout texts = new LinearLayout(this);
            texts.setOrientation(LinearLayout.VERTICAL);
            TextView name = new TextView(this);
            name.setText(d[0]);
            name.setTextColor(Color.WHITE);
            name.setTextSize(16);
            TextView meta = new TextView(this);
            meta.setText(d[1]);
            meta.setTextColor(Color.parseColor("#9AA0A6"));
            meta.setTextSize(11);
            texts.addView(name);
            texts.addView(meta);
            card.addView(texts, new LinearLayout.LayoutParams(0,
                    ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

            Button connect = new Button(this);
            connect.setText("远程控制");
            connect.setTextColor(Color.parseColor("#5CD96B"));
            connect.setBackgroundColor(Color.TRANSPARENT);
            connect.setOnClickListener(v ->
                    Toast.makeText(this, "将连接 " + d[0] + "（协议消息 " + Gvpb.schemaMessageCount() + " 条）",
                            Toast.LENGTH_SHORT).show());
            card.addView(connect);
            root.addView(card);
        }

        TextView footer = new TextView(this);
        footer.setText("说明：本端为可编译骨架，远控与采集模块按 docs/08-tri-platform.md 逐步接入。");
        footer.setTextColor(Color.parseColor("#6B7075"));
        footer.setTextSize(10);
        footer.setGravity(Gravity.BOTTOM);
        root.addView(footer);

        ScrollView scroll = new ScrollView(this);
        scroll.addView(root);
        setContentView(scroll);
    }
}
