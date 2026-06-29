package com.wanadi.chasqui

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class BLEForegroundService : Service() {
    companion object {
        const val CHANNEL_ID = "wanadi_foreground_channel"
        const val NOTIFICATION_ID = 1
    }
    
    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundDaemon()
        return START_STICKY
    }
    
    fun startForegroundDaemon() {
        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
        .setContentTitle("Wanadi Chasqui")
        .setContentText("Modo rescate activo")
        .setSmallIcon(android.R.drawable.ic_dialog_info)
        .setOngoing(true)
        .build()
        startForeground(NOTIFICATION_ID, notification)
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Wanadi foreground service",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Mantiene vivo el daemon BLE de Wanadi"
                enableVibration(true)
            }
            val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
}
