package com.example.dimly

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

class FlashlightBackgroundService : Service() {
    companion object {
        private const val CHANNEL_ID = "DIMLY_BACKGROUND_SERVICE"
        private const val NOTIFICATION_ID = 1001
        private const val ACTION_STOP_SERVICE = "STOP_SERVICE"
        
        fun startService(context: Context) {
            val intent = Intent(context, FlashlightBackgroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
        
        fun stopService(context: Context) {
            val intent = Intent(context, FlashlightBackgroundService::class.java)
            context.stopService(intent)
        }
    }

    private lateinit var cameraManager: CameraManager
    private var cameraId: String? = null
    private var isServiceActive = false

    override fun onCreate() {
        super.onCreate()
        cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
        cameraId = cameraManager.cameraIdList.firstOrNull { id ->
            cameraManager.getCameraCharacteristics(id)
                .get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
        }
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP_SERVICE -> {
                stopSelf()
                return START_NOT_STICKY
            }
            else -> {
                startForeground(NOTIFICATION_ID, createNotification())
                isServiceActive = true
                Log.d("FlashlightBGService", "Background service started")
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        isServiceActive = false
        // Turn off flashlight when service is destroyed
        try {
            cameraId?.let { cameraManager.setTorchMode(it, false) }
        } catch (e: Exception) {
            Log.e("FlashlightBGService", "Error turning off torch on service destroy", e)
        }
        Log.d("FlashlightBGService", "Background service destroyed")
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Dimly Background Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps Dimly running for Quick Settings functionality"
                setShowBadge(false)
            }
            
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        val stopIntent = Intent(this, FlashlightBackgroundService::class.java).apply {
            action = ACTION_STOP_SERVICE
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 
            0, 
            stopIntent, 
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val mainIntent = Intent(this, MainActivity::class.java)
        val mainPendingIntent = PendingIntent.getActivity(
            this, 
            0, 
            mainIntent, 
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Dimly Quick Settings Active")
            .setContentText("Tap to open app, or swipe to access stop action")
            .setSmallIcon(R.drawable.dimly_tile_icon)
            .setContentIntent(mainPendingIntent)
            .addAction(
                R.drawable.ambient_tile_icon,
                "Stop Background Service",
                stopPendingIntent
            )
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }
}
