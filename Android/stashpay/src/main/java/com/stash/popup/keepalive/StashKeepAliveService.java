package com.stash.popup.keepalive;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.util.Log;
import androidx.core.app.NotificationCompat;

/**
 * Foreground service that keeps the app alive when redirecting to Chrome Custom Tabs or browser for payment.
 * 
 * This service prevents the app from being killed by Android's memory management while the user
 * completes payment in an external browser. It automatically stops when:
 * - The app regains focus (via ACTION_STOP)
 * - A soft timeout elapses (5 minutes on Android 13 and below, ~2.5 minutes on Android 14+)
 * - The platform timeout fires (Android 14+ enforces a 3-minute limit for shortService)
 */
public class StashKeepAliveService extends Service {
    private static final String TAG = "StashKeepAlive";
    private static final String CHANNEL_ID = "stash_keep_alive_channel";
    private static final String CHANNEL_NAME = "Active session";
    private static final int NOTIFICATION_ID = 1001;
    private static final String ACTION_STOP = "com.stash.popup.keepalive.ACTION_STOP";
    
    // Timeouts: 5 minutes for <34, ~2.5 minutes (3 min - 30s buffer) for 34+
    private static final long SOFT_TIMEOUT_MS_LEGACY = 5 * 60 * 1000; // 5 minutes
    private static final long PLATFORM_TIMEOUT_MS = 3 * 60 * 1000; // 3 minutes (Android 14+)
    private static final long DEFAULT_TIMEOUT_BUFFER_MS = 30 * 1000; // 30 seconds
    
    private Handler handler;
    private Runnable softTimeoutRunnable;
    private String reason;
    private long timeoutBufferMs;
    private long softTimeoutMs;
    
    @Override
    public void onCreate() {
        super.onCreate();
        handler = new Handler(Looper.getMainLooper());
        createNotificationChannel();
        Log.d(TAG, "Keep-alive service created");
    }
    
    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) {
            stopSelf();
            return START_NOT_STICKY;
        }
        
        String action = intent.getAction();
        if (ACTION_STOP.equals(action)) {
            Log.d(TAG, "Stop action received, stopping service");
            stopForeground(true);
            stopSelf();
            return START_NOT_STICKY;
        }
        
        // Extract parameters
        reason = intent.getStringExtra("reason");
        if (reason == null) {
            reason = "checkout";
        }
        timeoutBufferMs = intent.getLongExtra("timeoutBufferMs", DEFAULT_TIMEOUT_BUFFER_MS);
        
        // Calculate soft timeout based on Android version
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // Android 14+: Use platform limit minus buffer
            softTimeoutMs = Math.max(PLATFORM_TIMEOUT_MS - timeoutBufferMs, 60000); // Minimum 1 minute
        } else {
            // Android 13 and below: Use 5 minutes
            softTimeoutMs = SOFT_TIMEOUT_MS_LEGACY;
        }
        
        // Start foreground with notification
        startForeground(NOTIFICATION_ID, createNotification());
        
        // Schedule soft timeout
        scheduleSoftTimeout();
        
        Log.d(TAG, "Keep-alive service started for reason: " + reason + ", timeout: " + (softTimeoutMs / 1000) + "s");
        
        return START_NOT_STICKY;
    }
    
    @Override
    public IBinder onBind(Intent intent) {
        return null; // Not a bound service
    }
    
    @Override
    public void onDestroy() {
        if (handler != null && softTimeoutRunnable != null) {
            handler.removeCallbacks(softTimeoutRunnable);
        }
        Log.d(TAG, "Keep-alive service destroyed");
        super.onDestroy();
    }
    
    /**
     * Called by Android 14+ when the platform timeout is reached.
     * This method MUST stop the service quickly to avoid ANR.
     */
    @Override
    public void onTimeout(int timeoutType) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            Log.d(TAG, "Platform timeout reached, stopping service immediately");
            // Remove pending callbacks
            if (handler != null && softTimeoutRunnable != null) {
                handler.removeCallbacks(softTimeoutRunnable);
            }
            // Stop foreground immediately
            stopForeground(STOP_FOREGROUND_REMOVE);
            // Stop the service
            stopSelf();
        }
    }
    
    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_DEFAULT // Changed from LOW to DEFAULT for better visibility
            );
            channel.setDescription("Keeping the session active during payment");
            channel.setShowBadge(false);
            channel.setSound(null, null);
            channel.enableVibration(false);
            
            NotificationManager notificationManager = getSystemService(NotificationManager.class);
            if (notificationManager != null) {
                notificationManager.createNotificationChannel(channel);
            }
        }
    }
    
    private Notification createNotification() {
        // Create a pending intent that opens the app's launcher activity
        Intent intent = getPackageManager().getLaunchIntentForPackage(getPackageName());
        if (intent != null) {
            intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        } else {
            // Fallback: create a generic intent
            intent = new Intent();
            intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        }
        
        PendingIntent pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT
        );
        
        // Use app icon, fallback to system icon if not available
        int icon = getApplicationInfo().icon;
        if (icon == 0) {
            // Fallback to a simple system icon
            icon = android.R.drawable.ic_menu_info_details;
        }
        
        return new NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Active")
            .setContentText("Keeping the session active.")
            .setSmallIcon(icon)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(pendingIntent)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setSilent(true) // No sound or vibration
            .build();
    }
    
    private void scheduleSoftTimeout() {
        if (handler == null) {
            return;
        }
        
        // Remove any existing timeout
        if (softTimeoutRunnable != null) {
            handler.removeCallbacks(softTimeoutRunnable);
        }
        
        // Create new timeout runnable
        softTimeoutRunnable = new Runnable() {
            @Override
            public void run() {
                Log.d(TAG, "Soft timeout reached, stopping service");
                stopForeground(STOP_FOREGROUND_REMOVE);
                stopSelf();
            }
        };
        
        // Schedule timeout
        handler.postDelayed(softTimeoutRunnable, softTimeoutMs);
        Log.d(TAG, "Soft timeout scheduled for " + (softTimeoutMs / 1000) + " seconds");
    }
}
