package com.example.uuremote;

import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;

import gv_pb.General;

/**
 * 剪贴板同步（官方协议 ClipboardChange，信封 field 17）。
 * 发送：系统剪贴板变化 -> ClipboardChange(TEXT)
 * 接收：写回系统剪贴板（带回环抑制）
 * protobuf 类型由官方 gv_pb 生成（protobuf-javalite）。
 */
public final class ClipboardSync {
    public interface Sender { void sendControl(byte[] data); }

    private final ClipboardManager cm;
    private final Sender sender;
    private String lastSent;
    private String lastReceived;
    private long seq = 1;

    public ClipboardSync(Context context, Sender sender) {
        this.cm = (ClipboardManager) context.getSystemService(Context.CLIPBOARD_SERVICE);
        this.sender = sender;
    }

    public void start() {
        cm.addPrimaryClipChangedListener(this::onClipboardChanged);
    }

    public void stop() {
        // ClipboardManager 无对应 remove API（监听器随进程结束），置空防泄漏即可
        lastSent = null;
    }

    private void onClipboardChanged() {
        try {
            CharSequence text = cm.getPrimaryClip() != null
                    ? cm.getPrimaryClip().getItemAt(0).getText() : null;
            if (text == null || text.length() == 0) return;
            String t = text.toString();
            if (t.equals(lastSent) || t.equals(lastReceived)) return;
            lastSent = t;

            General.ClipboardChange change = General.ClipboardChange.newBuilder()
                    .setType(General.ClipboardChange.Type.TEXT)
                    .setContentId(seq)
                    .setContent(t)
                    .setToBeContinued(false)
                    .build();
            gv_pb.Main.Message message = gv_pb.Main.Message.newBuilder()
                    .setSeq(seq)
                    .setTimestamp(System.currentTimeMillis())
                    .setClipboardChange(change)
                    .build();
            seq++;
            sender.sendControl(message.toByteArray());
        } catch (Exception ignored) {
        }
    }

    /** 收到对端 ClipboardChange：解析并写回系统剪贴板 */
    public void apply(byte[] data) {
        try {
            gv_pb.Main.Message message = gv_pb.Main.Message.parseFrom(data);
            if (!message.hasClipboardChange()) return;
            General.ClipboardChange change = message.getClipboardChange();
            String text = change.getContent();
            if (text == null || text.isEmpty()) return;
            if (text.equals(lastSent) || text.equals(lastReceived)) return;
            lastReceived = text;
            cm.setPrimaryClip(ClipData.newPlainText("uuremote", text));
        } catch (Exception ignored) {
        }
    }
}
