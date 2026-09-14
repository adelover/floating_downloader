package com.example.floating_downloader

import android.app.PendingIntent
import android.content.Intent
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService

class MusicPlaybackService : MediaSessionService() {
    companion object {
        var instance: MusicPlaybackService? = null
            private set
        private val pendingActions = mutableListOf<(ExoPlayer) -> Unit>()

        @Synchronized
        fun enqueue(context: android.content.Context, action: (ExoPlayer) -> Unit) {
            instance?.let { action(it.player); return }
            synchronized(pendingActions) { pendingActions += action }
            val intent = Intent(context, MusicPlaybackService::class.java)
            if (android.os.Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent)
            else context.startService(intent)
        }
    }

    lateinit var player: ExoPlayer
        private set
    private lateinit var mediaSession: MediaSession

    override fun onCreate() {
        super.onCreate()
        instance = this
        player = ExoPlayer.Builder(this).build().apply {
            setAudioAttributes(
                AudioAttributes.Builder()
                    .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                    .setUsage(C.USAGE_MEDIA)
                    .build(),
                true
            )
        }
        val actions = synchronized(pendingActions) {
            pendingActions.toList().also { pendingActions.clear() }
        }
        actions.forEach { it(player) }
        val sessionActivity = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        mediaSession = MediaSession.Builder(this, player)
            .setSessionActivity(sessionActivity)
            .build()
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession = mediaSession

    override fun onTaskRemoved(rootIntent: Intent?) {
        if (!player.playWhenReady) stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        mediaSession.release()
        player.release()
        instance = null
        super.onDestroy()
    }
}
