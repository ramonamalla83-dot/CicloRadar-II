package com.cicloradar.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "sos_alerts",
                "Alertas SOS",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Alertas de emergencia ciclista de CicloRadar"
                enableVibration(true)
            }
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
        super.onCreate(savedInstanceState)
    }
}
