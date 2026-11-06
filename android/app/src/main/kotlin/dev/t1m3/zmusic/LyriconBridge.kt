package dev.t1m3.zmusic

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock

import io.github.proify.lyricon.lyric.model.LyricWord
import io.github.proify.lyricon.lyric.model.RichLyricLine
import io.github.proify.lyricon.lyric.model.Song
import io.github.proify.lyricon.provider.ConnectionListener
import io.github.proify.lyricon.provider.LyriconFactory
import io.github.proify.lyricon.provider.LyriconProvider
import io.github.proify.lyricon.provider.ProviderConstants
import io.github.proify.lyricon.provider.ProviderInfo

/**
 * Publishes the current track, syllable-timed lyrics and play head to the
 * system lyric provider (Lyricon / 词幕), which renders them natively in the
 * status bar and the system island with per-word timing.
 */
class LyriconBridge(context: Context) {
    private val appContext = context.applicationContext
    private val handler = Handler(Looper.getMainLooper())

    @Volatile private var provider: LyriconProvider? = null
    @Volatile private var available = false
    @Volatile private var songId: String? = null
    @Volatile private var lyricsKey = ""

    private var basePosition = 0L
    private var baseElapsed = 0L
    private var playing = false
    private var ticking = false

    private val ticker = object : Runnable {
        override fun run() {
            val p = provider
            if (p == null || !available) {
                ticking = false
                return
            }
            if (playing) {
                val position =
                    basePosition + (SystemClock.elapsedRealtime() - baseElapsed)
                runCatching { p.player.setPosition(maxOf(0L, position)) }
            }
            handler.postDelayed(this, 100L)
        }
    }

    fun start() {
        if (provider != null) return
        try {
            val pkg = appContext.packageName
            val p = LyriconFactory.createProvider(
                appContext,
                ProviderInfo(pkg, pkg, null, null, null),
                null,
                ProviderConstants.SYSTEM_UI_PACKAGE_NAME,
            )
            p.autoSync = true
            p.service.addConnectionListener(object : ConnectionListener {
                override fun onConnected(provider: LyriconProvider) {
                    available = true
                }

                override fun onReconnected(provider: LyriconProvider) {
                    available = true
                }

                override fun onDisconnected(provider: LyriconProvider) {
                    available = false
                }

                override fun onConnectTimeout(provider: LyriconProvider) {
                    available = false
                }
            })
            provider = p
            available = p.register()
        } catch (_: Throwable) {
            provider = null
            available = false
        }
    }

    /** True when the system side accepted the provider registration. */
    fun isAvailable(): Boolean = available

    /**
     * Replaces the song/lyrics block and the play head. Returns false when
     * there is no system provider, so the caller can fall back.
     */
    fun update(payload: Map<String, Any?>): Boolean {
        val p = provider ?: return false
        if (!available) return false

        val id = payload["songId"] as? String ?: ""
        val lines = buildLines(payload["lines"] as? List<*>)
        val key = "$id:${lines.hashCode()}"
        val position = (payload["positionMs"] as? Number)?.toLong() ?: 0L
        playing = payload["playing"] as? Boolean ?: false
        basePosition = maxOf(0L, position)
        baseElapsed = SystemClock.elapsedRealtime()

        try {
            val player = p.player
            if (id != songId || key != lyricsKey) {
                val title = payload["title"] as? String ?: ""
                val artist = payload["artist"] as? String ?: ""
                val duration = (payload["durationMs"] as? Number)?.toLong() ?: 0L
                player.setSong(
                    Song(
                        id,
                        title,
                        artist,
                        maxOf(0L, duration),
                        null,
                        if (lines.isEmpty()) null else lines,
                    ),
                )
                songId = id
                lyricsKey = key
            }
            player.setDisplayTranslation(payload["showTranslation"] as? Boolean ?: true)
            player.setDisplayRoma(payload["showRoma"] as? Boolean ?: true)
            player.setPlaybackState(playing)
            player.seekTo(basePosition)
        } catch (_: Throwable) {
            return false
        }
        startTicker()
        return true
    }

    fun position(positionMs: Int, isPlaying: Boolean) {
        basePosition = maxOf(0L, positionMs.toLong())
        baseElapsed = SystemClock.elapsedRealtime()
        if (playing != isPlaying) {
            playing = isPlaying
            runCatching { provider?.player?.setPlaybackState(isPlaying) }
        }
    }

    fun hide() {
        playing = false
        songId = null
        lyricsKey = ""
        handler.removeCallbacks(ticker)
        ticking = false
        val p = provider ?: return
        try {
            p.player.setSong(null)
            p.player.setPlaybackState(false)
        } catch (_: Throwable) {
            // The SystemUI side may be gone; nothing else to do.
        }
    }

    fun destroy() {
        hide()
        val p = provider
        provider = null
        available = false
        if (p != null) {
            runCatching { p.unregister() }
            runCatching { p.destroy() }
        }
    }

    private fun startTicker() {
        if (ticking) return
        ticking = true
        handler.post(ticker)
    }

    private fun buildLines(raw: List<*>?): List<RichLyricLine> {
        if (raw == null) return emptyList()
        val out = ArrayList<RichLyricLine>(raw.size)
        for (item in raw) {
            val map = item as? Map<*, *> ?: continue
            val text = (map["text"] as? String)?.trim() ?: continue
            if (text.isEmpty()) continue
            val begin = (map["begin"] as? Number)?.toLong() ?: 0L
            var end = (map["end"] as? Number)?.toLong() ?: 0L
            if (end <= begin) end = begin + 500L
            val right = map["right"] as? Boolean ?: false
            val translation = (map["translation"] as? String)
                ?.trim()?.ifEmpty { null }
            val roma = (map["roma"] as? String)?.trim()?.ifEmpty { null }
            out.add(
                RichLyricLine(
                    begin,
                    end,
                    end - begin,
                    right,
                    null,
                    text,
                    buildWords(map["words"] as? List<*>),
                    null,
                    null,
                    translation,
                    null,
                    roma,
                ),
            )
        }
        return out
    }

    private fun buildWords(raw: List<*>?): List<LyricWord>? {
        if (raw == null || raw.isEmpty()) return null
        val out = ArrayList<LyricWord>(raw.size)
        for (item in raw) {
            val map = item as? Map<*, *> ?: continue
            val text = map["text"] as? String ?: continue
            if (text.isEmpty()) continue
            val begin = (map["begin"] as? Number)?.toLong() ?: continue
            var end = (map["end"] as? Number)?.toLong() ?: 0L
            if (end <= begin) continue
            out.add(LyricWord(begin, end, end - begin, text, null))
        }
        return if (out.isEmpty()) null else out
    }
}
