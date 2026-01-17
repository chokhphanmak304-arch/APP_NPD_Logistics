package com.example.npd_transport_app

import io.flutter.embedding.android.FlutterActivity
import android.os.Bundle
import android.view.WindowManager
import android.content.ComponentCallbacks2
import android.app.ActivityManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var isCameraOpen = false
    private var photoCount = 0
    private val CHANNEL = "com.npd.transport/camera"
    private val CHANNEL_ID = "camera_protection"
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        println("🚀 MainActivity onCreate with Foreground Service protection")
        isCameraOpen = false
        photoCount = 0
        
        // ✅ Keep screen on
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.addFlags(WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD)
        
        // ✅ Set as important - รองรับทุก Android version
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // Android 13+ ใช้ Builder
            setTaskDescription(ActivityManager.TaskDescription.Builder()
                .setLabel("NPD Transport (Active)")
                .build())
        } else {
            // Android 12 และต่ำกว่า ใช้ deprecated constructor
            @Suppress("DEPRECATION")
            setTaskDescription(ActivityManager.TaskDescription("NPD Transport (Active)"))
        }
        
        // 🆕 Create notification channel for camera
        createNotificationChannel()
        
        // 🆕 Create notification channel for location tracking
        LocationTrackingService.createNotificationChannel(this)
        
        // 🆕 Setup method channel to control foreground service
        setupMethodChannel()
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Camera Protection"
            val descriptionText = "Keeps app alive during camera usage"
            val importance = NotificationManager.IMPORTANCE_LOW
            val channel = NotificationChannel(CHANNEL_ID, name, importance).apply {
                description = descriptionText
                setShowBadge(false)
            }
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    private fun setupMethodChannel() {
        MethodChannel(flutterEngine?.dartExecutor?.binaryMessenger!!, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startForeground" -> {
                    startForegroundProtection()
                    result.success(true)
                }
                "stopForeground" -> {
                    stopForegroundProtection()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
    
    private fun startForegroundProtection() {
        println("🛡️ Starting Foreground Service protection")
        val serviceIntent = Intent(this, CameraProtectionService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
    }
    
    private fun stopForegroundProtection() {
        println("🛡️ Stopping Foreground Service protection")
        val serviceIntent = Intent(this, CameraProtectionService::class.java)
        stopService(serviceIntent)
    }
    
    override fun onTrimMemory(level: Int) {
        println("🔔 onTrimMemory: level=$level, cameraOpen=$isCameraOpen, photos=$photoCount")
        
        if (isCameraOpen) {
            println("📷 BLOCKING trim memory - camera is open!")
            return
        }
        
        when (level) {
            ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN -> {
                println("📷 UI hidden - camera opening (Photo #${photoCount + 1})")
                isCameraOpen = true
                photoCount++
            }
            ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW,
            ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL -> {
                println("⚠️ Low memory detected! Photos taken: $photoCount")
                if (!isCameraOpen) {
                    System.gc()
                }
            }
        }
        
        if (!isCameraOpen) {
            super.onTrimMemory(level)
        }
    }
    
    override fun onLowMemory() {
        println("🔔 onLowMemory: cameraOpen=$isCameraOpen")
        
        if (isCameraOpen) {
            println("📷 BLOCKING onLowMemory - camera is open!")
            return
        }
        
        System.gc()
        super.onLowMemory()
    }
    
    override fun onPause() {
        println("⏸️ onPause: Photo #$photoCount")
        isCameraOpen = true
        super.onPause()
    }
    
    override fun onResume() {
        super.onResume()
        println("▶️ onResume: Clearing camera flag")
        isCameraOpen = false
    }
    
    override fun onStop() {
        println("🛑 onStop: cameraOpen=$isCameraOpen, photos=$photoCount")
        super.onStop()
    }
    
    override fun onRestart() {
        super.onRestart()
        isCameraOpen = false
    }
    
    override fun onDestroy() {
        println("💀 onDestroy")
        stopForegroundProtection()
        isCameraOpen = false
        photoCount = 0
        super.onDestroy()
    }
}

// 🆕 Foreground Service to protect app from being killed
class CameraProtectionService : Service() {
    private val CHANNEL_ID = "camera_protection"
    private val NOTIFICATION_ID = 1
    
    override fun onCreate() {
        super.onCreate()
        println("🛡️ CameraProtectionService created")
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        println("🛡️ CameraProtectionService started")
        
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("NPD Transport")
            .setContentText("กำลังใช้กล้อง - แอปจะไม่ถูกปิด")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()
        
        startForeground(NOTIFICATION_ID, notification)
        
        return START_STICKY
    }
    
    override fun onDestroy() {
        println("🛡️ CameraProtectionService destroyed")
        super.onDestroy()
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
}
