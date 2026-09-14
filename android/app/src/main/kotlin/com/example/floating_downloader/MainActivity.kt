package com.example.floating_downloader

import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.LoudnessEnhancer
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val storageName = "com.example.floating_downloader/storage"
    private val musicName = "com.example.floating_downloader/music"
    private val eventsName = "com.example.floating_downloader/music/events"
    private var storageChannel: MethodChannel? = null
    private var musicEvents: EventChannel.EventSink? = null
    private var pendingSharedText: String? = null
    private var permissionResult: MethodChannel.Result? = null
    private var equalizer: Equalizer? = null
    private var bassBoost: BassBoost? = null
    private var loudnessEnhancer: LoudnessEnhancer? = null
    private var audioManager: AudioManager? = null
    private val audioDeviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) = publishAudioProfile()
        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) = publishAudioProfile()
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        pendingSharedText = extractSharedText(intent)
        storageChannel = MethodChannel(engine.dartExecutor.binaryMessenger, storageName)
        storageChannel?.setMethodCallHandler { call, result -> handleStorage(call, result) }
        MethodChannel(engine.dartExecutor.binaryMessenger, musicName)
            .setMethodCallHandler { call, result -> handleMusic(call.method, call.arguments, result) }
        EventChannel(engine.dartExecutor.binaryMessenger, eventsName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { musicEvents = events }
                override fun onCancel(arguments: Any?) { musicEvents = null }
            })
        audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
        if (Build.VERSION.SDK_INT >= 23) {
            audioManager?.registerAudioDeviceCallback(audioDeviceCallback, Handler(Looper.getMainLooper()))
        }
        if (!pendingSharedText.isNullOrBlank()) {
            storageChannel?.invokeMethod("onSharedText", pendingSharedText)
        }
    }

    private fun handleStorage(call: MethodChannel.MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getCacheDirectory" -> result.success(cacheDir.absolutePath)
            "getSharedText" -> { result.success(pendingSharedText); pendingSharedText = null }
            "isWifiConnected" -> result.success(isWifiConnected())
            "saveToDownloads" -> {
                val source = call.argument<String>("sourcePath")
                val name = call.argument<String>("fileName")
                if (source.isNullOrBlank() || name.isNullOrBlank()) {
                    result.error("INVALID_ARGUMENT", "sourcePath and fileName are required.", null)
                } else runCatching {
                    saveToDownloads(File(source), name, call.argument("mimeType") ?: "application/octet-stream")
                }.onSuccess(result::success).onFailure {
                    result.error("SAVE_FAILED", it.message ?: "Could not save file.", null)
                }
            }
            "openFile" -> openOrShare(call, result, false)
            "shareFile" -> openOrShare(call, result, true)
            "deleteFile" -> {
                call.argument<String>("uri")?.let { contentResolver.delete(Uri.parse(it), null, null) }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun openOrShare(call: MethodChannel.MethodCall, result: MethodChannel.Result, share: Boolean) {
        runCatching {
            val uri = Uri.parse(call.argument<String>("uri"))
            val mime = call.argument<String>("mimeType") ?: "*/*"
            val intent = if (share) Intent(Intent.ACTION_SEND).apply {
                type = mime; putExtra(Intent.EXTRA_STREAM, uri)
            } else Intent(Intent.ACTION_VIEW).apply { setDataAndType(uri, mime) }
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(if (share) Intent.createChooser(intent, "اشتراک‌گذاری فایل") else intent)
        }.onSuccess { result.success(null) }.onFailure {
            result.error("OPEN_FAILED", it.message ?: "Unable to open file.", null)
        }
    }

    private fun handleMusic(method: String, args: Any?, result: MethodChannel.Result) {
        when (method) {
            "requestAudioPermission" -> requestAudioPermission(result)
            "hasAudioPermission" -> result.success(hasAudioPermission())
            "scanAudio", "queryAudio" -> result.success(scanAudio())
            "requestOverlayPermission" -> {
                if (!Settings.canDrawOverlays(this)) startActivity(
                    Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
                result.success(Settings.canDrawOverlays(this))
            }
            "hasOverlayPermission" -> result.success(Settings.canDrawOverlays(this))
            "getAudioOutputs" -> result.success(audioOutputs())
            "getAudioOutputProfile" -> result.success(audioOutputProfile())
            "play" -> {
                val map = args as? Map<*, *>
                setQueue(map?.get("tracks") as? List<*>, (map?.get("index") as? Number)?.toInt() ?: 0) {
                    it.play()
                }; result.success(null)
            }
            "resume" -> { enqueuePlayback { it.play() }; result.success(null) }
            "pause" -> { enqueuePlayback { it.pause() }; result.success(null) }
            "next" -> { enqueuePlayback { it.seekToNextMediaItem() }; result.success(null) }
            "previous" -> { enqueuePlayback { it.seekToPreviousMediaItem() }; result.success(null) }
            "seek" -> { val position = ((args as? Map<*, *>)?.get("positionMs") as? Number)?.toLong() ?: 0L
                enqueuePlayback { it.seekTo(position.coerceAtLeast(0L)) }; result.success(null) }
            "setLoop" -> { val mode = ((args as? Number)?.toInt() ?: 0).coerceIn(0, 2)
                enqueuePlayback { it.repeatMode = mode }; result.success(null) }
            "setShuffle" -> { val enabled = args as? Boolean ?: false
                enqueuePlayback { it.shuffleModeEnabled = enabled }; result.success(null) }
            "setEqualizerPreset" -> {
                val eq = ensureEffects().first
                val preset = ((args as? Map<*, *>)?.get("preset") as? Number)?.toInt() ?: -1
                if (eq == null || preset !in 0 until eq.numberOfPresets.toInt()) {
                    result.error("INVALID_PRESET", "Equalizer preset is out of range.", null)
                } else {
                    eq.usePreset(preset.toShort()); result.success(null)
                }
            }
            "setBassBoost" -> { ensureEffects().second?.enabled = (args as? Map<*, *>)?.get("enabled") as? Boolean ?: false; result.success(null) }
            "setLoudnessEnhancer" -> { ensureEffects().third?.enabled = (args as? Map<*, *>)?.get("enabled") as? Boolean ?: false; result.success(null) }
            "setEqualizerBand" -> {
                val m = args as? Map<*, *>
                val eq = ensureEffects().first
                val band = (m?.get("band") as? Number)?.toInt() ?: -1
                val level = (m?.get("level") as? Number)?.toInt() ?: Int.MIN_VALUE
                if (eq == null || band !in 0 until eq.numberOfBands) {
                    result.error("INVALID_BAND", "Equalizer band is out of range.", null)
                } else {
                    val range = eq.bandLevelRange
                    eq.setBandLevel(
                        band.toShort(),
                        (level * 100).coerceIn(range[0].toInt(), range[1].toInt()).toShort()
                    )
                    result.success(null)
                }
            }
            "getEqualizerInfo" -> result.success(equalizerInfo())
            else -> result.notImplemented()
        }
        musicEvents?.success(mapOf("method" to method))
    }

    private fun requestAudioPermission(result: MethodChannel.Result) {
        val permission = if (Build.VERSION.SDK_INT >= 33) "android.permission.READ_MEDIA_AUDIO"
        else "android.permission.READ_EXTERNAL_STORAGE"
        if (checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) result.success(true)
        else {
            permissionResult = result
            val requested = if (Build.VERSION.SDK_INT >= 33) {
                arrayOf(permission, "android.permission.POST_NOTIFICATIONS")
            } else {
                arrayOf(permission)
            }
            requestPermissions(requested, 9001)
        }
    }

    private fun hasAudioPermission(): Boolean {
        val permission = if (Build.VERSION.SDK_INT >= 33) "android.permission.READ_MEDIA_AUDIO"
        else "android.permission.READ_EXTERNAL_STORAGE"
        return checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
    }

    private fun scanAudio(): List<Map<String, Any?>> {
        if (!hasAudioPermission()) return emptyList()
        val uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(MediaStore.Audio.Media._ID, MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST, MediaStore.Audio.Media.ALBUM, MediaStore.Audio.Media.DURATION)
        val rows = mutableListOf<Map<String, Any?>>()
        val selection = "${MediaStore.Audio.Media.DURATION} >= ? AND " +
            "${MediaStore.Audio.Media.IS_MUSIC} != 0"
        contentResolver.query(uri, projection, selection, arrayOf("30000"),
            "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC")?.use { c ->
            val id = c.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val title = c.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artist = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val album = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val duration = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            while (c.moveToNext()) {
                val audioId = c.getLong(id)
                rows += mapOf("id" to audioId, "title" to c.getString(title), "artist" to c.getString(artist),
                    "album" to c.getString(album), "duration" to c.getLong(duration),
                    "durationMs" to c.getLong(duration),
                    "uri" to ContentUris.withAppendedId(uri, audioId).toString(),
                    "contentUri" to ContentUris.withAppendedId(uri, audioId).toString(),
                    "albumArtUri" to "content://media/external/audio/albumart/$audioId")
            }
        }
        return rows
    }

    private fun enqueuePlayback(action: (androidx.media3.exoplayer.ExoPlayer) -> Unit) {
        MusicPlaybackService.enqueue(this, action)
    }

    private fun setQueue(
        tracks: List<*>?,
        index: Int,
        afterPrepare: (androidx.media3.exoplayer.ExoPlayer) -> Unit = {}
    ) {
        val items = tracks.orEmpty().mapNotNull { raw ->
            val m = raw as? Map<*, *> ?: return@mapNotNull null
            val uri = m["contentUri"]?.toString() ?: m["uri"]?.toString() ?: return@mapNotNull null
            androidx.media3.common.MediaItem.Builder().setUri(uri).setMediaMetadata(
                androidx.media3.common.MediaMetadata.Builder().setTitle(m["title"]?.toString())
                    .setArtist(m["artist"]?.toString()).setAlbumTitle(m["album"]?.toString()).build()).build()
        }
        enqueuePlayback { player ->
            player.setMediaItems(items, index.coerceIn(0, (items.size - 1).coerceAtLeast(0)), 0L)
            player.prepare()
            afterPrepare(player)
        }
    }

    private fun ensureEffects(): Triple<Equalizer?, BassBoost?, LoudnessEnhancer?> {
        val service = MusicPlaybackService.instance
        if (service == null) {
            enqueuePlayback { }
            return Triple(null, null, null)
        }
        val session = service.player.audioSessionId
        if (equalizer == null || equalizer?.audioSessionId != session) {
            equalizer?.release(); bassBoost?.release(); loudnessEnhancer?.release()
            equalizer = Equalizer(0, session); bassBoost = BassBoost(0, session); loudnessEnhancer = LoudnessEnhancer(session)
        }
        return Triple(equalizer, bassBoost, loudnessEnhancer)
    }

    private fun equalizerInfo(): Map<String, Any> {
        val eq = ensureEffects().first ?: return emptyMap()
        return mapOf("bands" to eq.numberOfBands.toInt(), "minLevel" to eq.bandLevelRange[0].toInt(),
            "maxLevel" to eq.bandLevelRange[1].toInt())
    }

    private fun audioOutputs(): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < 23) return emptyList()
        val manager = getSystemService(AUDIO_SERVICE) as AudioManager
        return manager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).map {
            val bluetooth = isBluetooth(it)
            mapOf("id" to it.id, "type" to it.type, "name" to it.productName.toString(), "bluetooth" to bluetooth,
                "profile" to deviceProfile(it))
        }
    }

    private fun deviceProfile(device: AudioDeviceInfo): String {
        if (Build.VERSION.SDK_INT >= 30 && device.type == AudioDeviceInfo.TYPE_AUTOMOTIVE) return "VEHICLE"
        return when (device.type) {
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "HEADPHONES"
        AudioDeviceInfo.TYPE_BLE_HEADSET -> if (Build.VERSION.SDK_INT >= 31) "HEADPHONES" else "PHONE"
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "SPEAKER"
        AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "PHONE"
        else -> "PHONE"
        }
    }

    private fun isBluetooth(device: AudioDeviceInfo): Boolean =
        device.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
            device.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
            (Build.VERSION.SDK_INT >= 31 && device.type == AudioDeviceInfo.TYPE_BLE_HEADSET)

    private fun audioOutputProfile(): String {
        if (Build.VERSION.SDK_INT < 23) return "PHONE"
        val devices = audioManager?.getDevices(AudioManager.GET_DEVICES_OUTPUTS).orEmpty()
        return devices.map(::deviceProfile).firstOrNull { it == "VEHICLE" }
            ?: devices.firstOrNull { deviceProfile(it) == "HEADPHONES" }?.let { "HEADPHONES" }
            ?: devices.firstOrNull { deviceProfile(it) == "SPEAKER" }?.let { "SPEAKER" }
            ?: "PHONE"
    }

    private fun publishAudioProfile() {
        val profile = audioOutputProfile()
        applyAudioProfile(profile)
        musicEvents?.success(mapOf("event" to "audioProfile", "profile" to profile))
    }

    private fun applyAudioProfile(profile: String) {
        val effects = ensureEffects()
        effects.second?.enabled = profile == "VEHICLE"
        effects.third?.enabled = profile == "VEHICLE"
        val eq = effects.first ?: return
        val curve = when (profile) {
            "VEHICLE" -> listOf(5, 4, 3, 1, 0, 0, 0, 0, 0, 1)
            "HEADPHONES" -> listOf(3, 2, 1, 0, -1, 0, 1, 2, 2, 1)
            "SPEAKER" -> listOf(2, 1, 0, 1, 2, 2, 2, 1, 1, 2)
            else -> List(10) { 0 }
        }
        val range = eq.bandLevelRange
        curve.take(eq.numberOfBands.toInt()).forEachIndexed { band, level ->
            eq.setBandLevel(
                band.toShort(),
                (level * 100).coerceIn(range[0].toInt(), range[1].toInt()).toShort()
            )
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 9001) {
            val audioIndex = permissions.indexOfFirst {
                it == "android.permission.READ_MEDIA_AUDIO" ||
                    it == "android.permission.READ_EXTERNAL_STORAGE"
            }
            permissionResult?.success(
                audioIndex >= 0 && grantResults.getOrNull(audioIndex) == PackageManager.PERMISSION_GRANTED
            )
            permissionResult = null
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent); setIntent(intent)
        extractSharedText(intent)?.let { storageChannel?.invokeMethod("onSharedText", it) ?: run { pendingSharedText = it } }
    }

    override fun onDestroy() {
        if (Build.VERSION.SDK_INT >= 23) audioManager?.unregisterAudioDeviceCallback(audioDeviceCallback)
        audioManager = null
        equalizer?.release(); bassBoost?.release(); loudnessEnhancer?.release()
        super.onDestroy()
    }

    private fun extractSharedText(intent: Intent?): String? =
        if (intent?.action == Intent.ACTION_SEND && intent.type?.startsWith("text/") == true)
            intent.getStringExtra(Intent.EXTRA_TEXT) else null

    private fun isWifiConnected(): Boolean {
        val manager = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = manager.activeNetwork ?: return false
        return manager.getNetworkCapabilities(network)?.let {
            it.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) || it.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
        } ?: false
    }

    private fun saveToDownloads(source: File, fileName: String, mimeType: String): String {
        require(Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
        require(source.isFile) { "Temporary download does not exist." }
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, fileName); put(MediaStore.Downloads.MIME_TYPE, mimeType)
            put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS); put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: error("Could not create Downloads entry.")
        try {
            contentResolver.openOutputStream(uri)?.use { output -> source.inputStream().use { it.copyTo(output, 64 * 1024) } }
                ?: error("Could not open Downloads output stream.")
            contentResolver.update(uri, ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }, null, null)
            return uri.toString()
        } catch (error: Throwable) { contentResolver.delete(uri, null, null); throw error }
    }
}
