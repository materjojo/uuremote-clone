package com.example.uuremote;

import static org.junit.Assert.*;
import android.app.Activity;
import android.app.Instrumentation;
import android.content.Intent;
import android.graphics.Bitmap;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import org.junit.Test;
import org.junit.runner.RunWith;

@RunWith(AndroidJUnit4.class)
public class HomeTest {
    private static boolean hasText(View root, String text) {
        if (root instanceof TextView && ((TextView)root).getText().toString().equals(text)) return true;
        if (root instanceof ViewGroup) for (int i = 0; i < ((ViewGroup)root).getChildCount(); i++)
            if (hasText(((ViewGroup)root).getChildAt(i), text)) return true;
        return false;
    }
    @Test public void firstLaunchShowsRealEmptyDeviceList() throws Exception {
        Instrumentation instrumentation = InstrumentationRegistry.getInstrumentation();
        instrumentation.getTargetContext().getSharedPreferences("peer.v1", 0).edit().clear().commit();
        Activity activity = instrumentation.startActivitySync(new Intent(instrumentation.getTargetContext(), MainActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        try {
            instrumentation.waitForIdleSync();
            instrumentation.runOnMainSync(() -> {
                View root = activity.findViewById(android.R.id.content);
                assertTrue(hasText(root, "还没有添加设备"));
                assertTrue(hasText(root, "我的设备"));
                assertTrue(hasText(root, "远程协助"));
                assertTrue(hasText(root, "我的"));
                assertFalse(hasText(root, "云设备"));
            });
            Bitmap image = instrumentation.getUiAutomation().takeScreenshot();
            assertNotNull("Emulator UI screenshot", image);
            image.recycle();
            // AGP uninstalls the app after tests, removing its external-files
            // directory. Capture with the shell into shared Downloads instead.
            try (android.os.ParcelFileDescriptor result = instrumentation.getUiAutomation()
                    .executeShellCommand("screencap -p /sdcard/Download/uuremote-home-empty.png");
                 java.io.FileInputStream stream = new java.io.FileInputStream(result.getFileDescriptor())) {
                byte[] block = new byte[1024]; while (stream.read(block) >= 0) { }
            }
        } finally { instrumentation.runOnMainSync(activity::finish); }
    }
    @Test public void invitationsAcceptAllSupportedPlatforms() throws Exception {
        for (String platform : new String[]{"mac", "windows", "android"}) {
            PeerAPI.Invitation value = new PeerAPI.Invitation("https://signal.example.org",
                    "peer-00000000000001", "a".repeat(64), "设备", platform);
            PeerAPI.Invitation decoded = PeerAPI.Invitation.parse(value.code());
            assertEquals(platform, decoded.platform); assertEquals(value.id, decoded.id);
            assertEquals(value.server, decoded.server); assertEquals(value.key, decoded.key);
        }
    }
}
