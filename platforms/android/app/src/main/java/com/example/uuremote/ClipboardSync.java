package com.example.uuremote;

import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;

import gv_pb.ClipboardChange;
import gv_pb.Message;

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
    private boolean listening;
    private final ClipboardManager.OnPrimaryClipChangedListener clipListener = this::onClipboardChanged;

    public ClipboardSync(Context context, Sender sender) {
        this.cm = (ClipboardManager) context.getSystemService(Context.CLIPBOARD_SERVICE);
        this.sender = sender;
    }

    public void start() {
        if (cm != null && !listening) {
            cm.addPrimaryClipChangedListener(clipListener);
            listening = true;
        }
    }

    public void stop() {
        if (cm != null && listening) cm.removePrimaryClipChangedListener(clipListener);
        listening = false;
        lastSent = null;
        lastReceived = null;
    }

    private void onClipboardChanged() {
        try {
            if (!listening || cm == null) return;
            ClipData clip = cm.getPrimaryClip();
            CharSequence text = clip != null && clip.getItemCount() > 0
                    ? clip.getItemAt(0).getText() : null;
            if (text == null || text.length() == 0) return;
            String t = text.toString();
            if (t.equals(lastSent) || t.equals(lastReceived)) return;
            lastSent = t;

            ClipboardChange change = ClipboardChange.newBuilder()
                    .setContentId((int) seq)
                    .setContent(t)
                    .setToBeContinued(false)
                    .build();
            Message message = Message.newBuilder()
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
            Message message = Message.parseFrom(data);
            if (!message.hasClipboardChange()) return;
            ClipboardChange change = message.getClipboardChange();
            String text = change.getContent();
            if (text == null || text.isEmpty()) return;
            if (text.equals(lastSent) || text.equals(lastReceived)) return;
            lastReceived = text;
            cm.setPrimaryClip(ClipData.newPlainText("uuremote", text));
        } catch (Exception ignored) {
        }
    }
}
