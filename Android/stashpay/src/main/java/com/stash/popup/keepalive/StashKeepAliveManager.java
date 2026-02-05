package com.stash.popup.keepalive;

import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.util.Log;
import androidx.core.content.ContextCompat;

/**
 * Static utility class for managing the Keep-Alive Service.
 * Used to keep the app alive when redirecting to Chrome Custom Tabs or browser for payment.
 */
public class StashKeepAliveManager {
    private static final String TAG = "StashKeepAlive";
    private static final String ACTION_STOP = "com.stash.popup.keepalive.ACTION_STOP";
    
    /**
     * Starts the keep-alive service.
     * 
     * @param context The context to use for starting the service
     * @param reason Reason for starting (e.g., "checkout", "google_pay")
     * @param timeoutBufferMs Buffer time in milliseconds to subtract from platform limit (recommended: 30000 for 30 seconds)
     */
    public static void start(Context context, String reason, long timeoutBufferMs) {
        if (context == null) {
            Log.e(TAG, "Context is null, cannot start keep-alive service");
            return;
        }
        
        try {
            Context appContext = context.getApplicationContext();
            Intent intent = new Intent(appContext, StashKeepAliveService.class);
            intent.putExtra("reason", reason != null ? reason : "checkout");
            intent.putExtra("timeoutBufferMs", timeoutBufferMs > 0 ? timeoutBufferMs : 30000L);
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(appContext, intent);
            } else {
                appContext.startService(intent);
            }
            
            Log.d(TAG, "Keep-alive service started: " + reason);
        } catch (Exception e) {
            Log.e(TAG, "Failed to start keep-alive service: " + e.getMessage(), e);
        }
    }
    
    /**
     * Stops the keep-alive service.
     * 
     * @param context The context to use for stopping the service
     */
    public static void stop(Context context) {
        if (context == null) {
            Log.e(TAG, "Context is null, cannot stop keep-alive service");
            return;
        }
        
        try {
            Context appContext = context.getApplicationContext();
            Intent intent = new Intent(appContext, StashKeepAliveService.class);
            intent.setAction(ACTION_STOP);
            appContext.startService(intent);
            
            Log.d(TAG, "Keep-alive service stop requested");
        } catch (Exception e) {
            Log.e(TAG, "Failed to stop keep-alive service: " + e.getMessage(), e);
        }
    }
}
