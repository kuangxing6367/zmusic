package dev.t1m3.zmusic

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Posts the current lyric as an ongoing notification so it can surface in the
 * status bar and, on Android 16+, as a promoted Live Update chip
 * ("灵动岛" / 流体云). Xiaomi's 超级岛 needs a whitelist from Xiaomi's developer
 * portal, but the same notification is what those systems promote.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "zmusic/lyric"
    private val notificationId = 0x2A17
    private val channelId = "zmusic_lyric"
    private var lastTitle = ""
    private var lastText = ""

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "show" -> {
                        val title = call.argument<String>("title") ?: ""
                        val text = call.argument<String>("text") ?: ""
                        update(title, text)
                        result.success(true)
                    }
                    "hide" -> {
                        hide()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun ensurePermission() {
        if (Build.VERSION.SDK_INT < 33) return
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                1001,
            )
        }
    }

    private fun ensureChannel(): NotificationManager {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            manager.getNotificationChannel(channelId) == null
        ) {
            val channel = NotificationChannel(
                channelId,
                "歌词",
                NotificationManager.IMPORTANCE_LOW,
            )
            channel.setShowBadge(false)
            channel.setSound(null, null)
            channel.enableVibration(false)
            manager.createNotificationChannel(channel)
        }
        return manager
    }

    private fun update(title: String, text: String) {
        if (text.isBlank()) return
        if (title == lastTitle && text == lastText) return
        lastTitle = title
        lastText = text
        ensurePermission()
        val manager = ensureChannel()
        val launch = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val pending = PendingIntent.getActivity(
            this,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = Notification.Builder(this, channelId)
            .setSmallIcon(R.drawable.ic_stat_lyric)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(pending)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(Notification.CATEGORY_TRANSPORT)
            .setVisibility(Notification.VISIBILITY_PUBLIC)

        if (Build.VERSION.SDK_INT >= 36) {
            // Android 16 Live Updates. Called reflectively so the app still
            // compiles against SDK 35.
            runCatching {
                builder.javaClass
                    .getMethod("setShortCriticalText", CharSequence::class.java)
                    .invoke(builder, text.take(12))
            }
            runCatching {
                builder.javaClass
                    .getMethod(
                        "setRequestPromotedOngoing",
                        Boolean::class.javaPrimitiveType,
                    )
                    .invoke(builder, true)
            }
        }
        runCatching { manager.notify(notificationId, builder.build()) }
    }

    private fun hide() {
        lastTitle = ""
        lastText = ""
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(notificationId)
    }
}
