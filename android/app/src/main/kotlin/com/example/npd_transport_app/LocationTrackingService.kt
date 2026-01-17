package com.example.npd_transport_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * 🎯 LocationTrackingService - จัดการ Foreground Service สำหรับติดตามตำแหน่ง
 * 
 * ✅ สร้าง notification channel ให้ valid
 * ✅ ให้ Flutter background service ใช้ notification นี้
 */
class LocationTrackingService : Service() {
    companion object {
        const val NOTIFICATION_CHANNEL_ID = "npd_location_service"
        const val NOTIFICATION_ID = 101
        
        // ช่วยให้ Flutter call ได้
        fun createNotificationChannel(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val name = "Location Tracking"
                val descriptionText = "Tracking delivery location"
                val importance = NotificationManager.IMPORTANCE_LOW
                
                val channel = NotificationChannel(NOTIFICATION_CHANNEL_ID, name, importance).apply {
                    description = descriptionText
                    setShowBadge(false)
                    enableVibration(false)
                    setSound(null, null)
                }
                
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.createNotificationChannel(channel)
                println("✅ Location notification channel created")
            }
        }
    }
    
    override fun onCreate() {
        super.onCreate()
        println("🚀 LocationTrackingService created")
        // สร้าง channel ทันทีเมื่อ service สร้าง
        createNotificationChannel(this)
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        println("🚀 LocationTrackingService onStartCommand")
        
        try {
            // ✅ สร้าง notification ที่ valid เพื่อให้ foreground service ทำงาน
            val notification = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
                .setContentTitle("NPD Transport - ติดตามตำแหน่ง")
                .setContentText("📍 ส่งตำแหน่งไปยัง Odoo")
                .setSmallIcon(android.R.drawable.ic_menu_mylocation)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setOngoing(true)
                .setShowWhen(false)
                .setAutoCancel(false)
                .build()
            
            startForeground(NOTIFICATION_ID, notification)
            println("✅ Foreground service started with notification")
            
        } catch (e: Exception) {
            println("❌ Error starting foreground: ${e.message}")
            e.printStackTrace()
        }
        
        return START_STICKY
    }
    
    override fun onDestroy() {
        println("🛑 LocationTrackingService destroyed")
        super.onDestroy()
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
}
