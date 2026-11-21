package com.kainuwa.encoder;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;

/**
 * Keeps the app alive while a video is being made, and shows the progress in the status bar.
 * The export itself still runs in the plugin; this service only holds the process in the
 * foreground and the CPU awake so the work goes on when the screen is off or the app is left.
 */
public class ExportService extends Service {
    static final String CHANNEL_PROGRESS = "export_progress";
    static final String CHANNEL_DONE = "export_done";
    static final int ID_PROGRESS = 4201;
    static final int ID_DONE = 4202;

    private PowerManager.WakeLock wake;

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        int pct = intent == null ? 0 : intent.getIntExtra("pct", 0);
        String text = intent == null ? null : intent.getStringExtra("text");
        ensureChannels(this);
        Notification n = build(this, text == null ? "Making your video" : text, pct);
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(ID_PROGRESS, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC);
        } else {
            startForeground(ID_PROGRESS, n);
        }
        if (wake == null) {
            try {
                PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
                wake = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "quranstudio:export");
                wake.acquire(4L * 60L * 60L * 1000L);
            } catch (Exception ignored) {
                wake = null;
            }
        }
        return START_NOT_STICKY;
    }

    @Override
    public void onDestroy() {
        try {
            if (wake != null && wake.isHeld()) {
                wake.release();
            }
        } catch (Exception ignored) {
            // nothing to do
        }
        wake = null;
        super.onDestroy();
    }

    static void ensureChannels(Context c) {
        if (Build.VERSION.SDK_INT < 26) {
            return;
        }
        NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm == null) {
            return;
        }
        NotificationChannel p = new NotificationChannel(CHANNEL_PROGRESS, "Video export progress",
                NotificationManager.IMPORTANCE_LOW);
        nm.createNotificationChannel(p);
        NotificationChannel d = new NotificationChannel(CHANNEL_DONE, "Video export finished",
                NotificationManager.IMPORTANCE_DEFAULT);
        nm.createNotificationChannel(d);
    }

    private static PendingIntent openApp(Context c) {
        Intent launch = c.getPackageManager().getLaunchIntentForPackage(c.getPackageName());
        if (launch == null) {
            launch = new Intent();
        }
        launch.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        int f = PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= 23 ? PendingIntent.FLAG_IMMUTABLE : 0);
        return PendingIntent.getActivity(c, 0, launch, f);
    }

    @SuppressWarnings("deprecation")
    private static Notification build(Context c, String text, int pct) {
        Notification.Builder b = Build.VERSION.SDK_INT >= 26
                ? new Notification.Builder(c, CHANNEL_PROGRESS)
                : new Notification.Builder(c);
        b.setSmallIcon(android.R.drawable.stat_sys_upload)
                .setContentTitle("Qur'an Studio")
                .setContentText(text + " " + pct + "%")
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setProgress(100, Math.max(0, Math.min(100, pct)), false)
                .setContentIntent(openApp(c));
        return b.build();
    }

    /** Shows or updates the progress notification (starts the service when needed). */
    static void show(Context c, int pct, String text) {
        Intent i = new Intent(c, ExportService.class);
        i.putExtra("pct", pct);
        i.putExtra("text", text);
        if (Build.VERSION.SDK_INT >= 26) {
            c.startForegroundService(i);
        } else {
            c.startService(i);
        }
    }

    /** Stops the service; state is done, failed or cancelled. Done and failed leave a message. */
    @SuppressWarnings("deprecation")
    static void stop(Context c, String state) {
        c.stopService(new Intent(c, ExportService.class));
        if (!"done".equals(state) && !"failed".equals(state)) {
            return;
        }
        try {
            ensureChannels(c);
            NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
            Notification.Builder b = Build.VERSION.SDK_INT >= 26
                    ? new Notification.Builder(c, CHANNEL_DONE)
                    : new Notification.Builder(c);
            boolean ok = "done".equals(state);
            b.setSmallIcon(ok ? android.R.drawable.stat_sys_download_done : android.R.drawable.stat_notify_error)
                    .setContentTitle("Qur'an Studio")
                    .setContentText(ok ? "Your video is ready. Open the app to save or share it."
                            : "The export stopped. Open the app to try again.")
                    .setAutoCancel(true)
                    .setContentIntent(openApp(c));
            if (nm != null) {
                nm.notify(ID_DONE, b.build());
            }
        } catch (Exception ignored) {
            // no permission to show notifications; nothing to do
        }
    }
}
