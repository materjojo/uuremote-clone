package com.example.uuremote;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.GestureDescription;
import android.graphics.Path;
import android.view.accessibility.AccessibilityEvent;

/** 被控端输入注入（AccessibilityService 手势） */
public class RemoteInputService extends AccessibilityService {
    private static RemoteInputService instance;

    public static RemoteInputService get() { return instance; }

    @Override
    protected void onServiceConnected() {
        super.onServiceConnected();
        instance = this;
    }

    @Override
    public void onDestroy() {
        if (instance == this) instance = null;
        super.onDestroy();
    }

    @Override public void onAccessibilityEvent(AccessibilityEvent event) { }

    @Override public void onInterrupt() { }

    /** 归一化坐标 0..1，转换为点击 */
    public void tap(float nx, float ny) {
        int w = getResources().getDisplayMetrics().widthPixels;
        int h = getResources().getDisplayMetrics().heightPixels;
        Path path = new Path();
        path.moveTo(nx * w, ny * h);
        GestureDescription gesture = new GestureDescription.Builder()
                .addStroke(new GestureDescription.StrokeDescription(path, 0, 40))
                .build();
        dispatchGesture(gesture, null, null);
    }

    public void typeText(String value) {
        android.view.accessibility.AccessibilityNodeInfo root = getRootInActiveWindow();
        if (root == null) return;
        android.view.accessibility.AccessibilityNodeInfo node = root.findFocus(android.view.accessibility.AccessibilityNodeInfo.FOCUS_INPUT);
        if (node == null || !node.isEditable()) return;
        String current = node.getText() == null ? "" : node.getText().toString();
        int start = node.getTextSelectionStart(), end = node.getTextSelectionEnd();
        if (start < 0 || end < start || end > current.length()) start = end = current.length();
        String next = current.substring(0, start) + value + current.substring(end);
        android.os.Bundle args = new android.os.Bundle();
        args.putCharSequence(android.view.accessibility.AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, next);
        if (node.performAction(android.view.accessibility.AccessibilityNodeInfo.ACTION_SET_TEXT, args)) {
            args.clear(); args.putInt(android.view.accessibility.AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, start + value.length());
            args.putInt(android.view.accessibility.AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, start + value.length());
            node.performAction(android.view.accessibility.AccessibilityNodeInfo.ACTION_SET_SELECTION, args);
        }
    }

    public void swipe(float x1, float y1, float x2, float y2, long durationMs) {
        int w = getResources().getDisplayMetrics().widthPixels;
        int h = getResources().getDisplayMetrics().heightPixels;
        Path path = new Path();
        path.moveTo(x1 * w, y1 * h);
        path.lineTo(x2 * w, y2 * h);
        GestureDescription gesture = new GestureDescription.Builder()
                .addStroke(new GestureDescription.StrokeDescription(path, 0, Math.max(20, durationMs)))
                .build();
        dispatchGesture(gesture, null, null);
    }
}
