package dev.t1m3.zmusic

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Mobile lyric bridge.
 *
 * The primary path publishes structured (syllable-timed) lyrics to the system
 * lyric provider (Lyricon / 词幕) — the same overlay host the official Android
 * player uses — so the status bar and island render them natively.
 *
 * When that provider is not installed and the user explicitly enabled the
 * fallback, an ongoing notification on Android 16+ is used instead and asks to
 * be promoted as a Live Update.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "zmusic/lyric"
    private val notificationId = 0x2A17
    private val channelId = "zmusic_lyric"
    private var bridge: LyriconBridge? = null
    private var permissionAsked = false
    private var lastTitle = ""
    private var lastText = ""

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Draw behind the status and navigation bars so the backdrop reaches
        // the screen edges; Flutter adds the proper insets through SafeArea.
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
        }
        WindowInsetsControllerCompat(window, window.decorView)
            .isAppearanceLightStatusBars = false
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val lyricBridge = LyriconBridge(this)
        bridge = lyricBridge
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        lyricBridge.start()
                        result.success(lyricBridge.isAvailable())
                    }
                    "push" -> {
                        @Suppress("UNCHECKED_CAST")
                        val payload = call.arguments as? Map<String, Any?>
                        if (payload == null) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        val handled = lyricBridge.update(payload)
                        if (!handled &&
                            payload["fallback"] == true &&
                            Build.VERSION.SDK_INT >= 36
                        ) {
                            val title = payload["title"] as? String ?: ""
                            val text = payload["activeText"] as? String ?: ""
                            updateNotification(title, text)
                        } else if (handled) {
                            cancelNotification()
                        }
                        result.success(handled)
                    }
                    "position" -> {
                        lyricBridge.position(
                            (call.argument<Number>("positionMs") ?: 0).toInt(),
                            call.argument<Boolean>("playing") ?: false,
                        )
                        result.success(null)
                    }
                    "hide" -> {
                        lyricBridge.hide()
                        cancelNotification()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        bridge?.destroy()
        bridge = null
        super.onDestroy()
    }

    private fun ensurePermission() {
        if (permissionAsked || Build.VERSION.SDK_INT < 33) return
        permissionAsked = true
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

    private fun updateNotification(title: String, text: String) {
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
            // compiles against an older SDK.
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

    private fun cancelNotification() {
        lastTitle = ""
        lastText = ""
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(notificationId)
    }
}
