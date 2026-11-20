package com.example.uuremote;

import android.app.*;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.*;

public final class ScreenShareService extends Service {
    private ResultReceiver lifecycle;
    @Override public int onStartCommand(Intent intent, int flags, int id) {
        NotificationManager manager = getSystemService(NotificationManager.class);
        manager.createNotificationChannel(new NotificationChannel("remote-screen", "远程屏幕共享", NotificationManager.IMPORTANCE_LOW));
        Intent stop = new Intent(this, ScreenShareService.class).setAction("stop");
        PendingIntent action = PendingIntent.getService(this, 1, stop, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        Notification notification = new Notification.Builder(this, "remote-screen")
                .setContentTitle("正在共享屏幕").setContentText("远程设备可查看屏幕，点按停止以断开")
                .setSmallIcon(android.R.drawable.ic_menu_view).setOngoing(true)
                .addAction(new Notification.Action.Builder(null, "停止共享", action).build()).build();
        if ("stop".equals(intent.getAction())) { stopForeground(STOP_FOREGROUND_REMOVE); stopSelf(); return START_NOT_STICKY; }
        if (Build.VERSION.SDK_INT >= 29) startForeground(2, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION);
        else startForeground(2, notification);
        ResultReceiver receiver = intent.getParcelableExtra("ready");
        lifecycle = receiver;
        if (receiver != null) receiver.send(1, Bundle.EMPTY);
        return START_NOT_STICKY;
    }
    @Override public void onDestroy() {
        if (lifecycle != null) { lifecycle.send(0, Bundle.EMPTY); lifecycle = null; }
        super.onDestroy();
    }
    @Override public IBinder onBind(Intent intent) { return null; }
}
