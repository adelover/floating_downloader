package com.example.floating_downloader

import android.content.ContentValues
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.floating_downloader/storage"
    private var methodChannel: MethodChannel? = null
    private var pendingSharedText: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        pendingSharedText = extractSharedText(intent)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getCacheDirectory" -> result.success(cacheDir.absolutePath)

                "getSharedText" -> {
                    result.success(pendingSharedText)
                    pendingSharedText = null
                }

                "isWifiConnected" -> result.success(isWifiConnected())

                "saveToDownloads" -> {
                    val sourcePath = call.argument<String>("sourcePath")
                    val fileName = call.argument<String>("fileName")
                    val mimeType = call.argument<String>("mimeType")
                        ?: "application/octet-stream"

                    if (sourcePath.isNullOrBlank() || fileName.isNullOrBlank()) {
                        result.error(
                            "INVALID_ARGUMENT",
                            "sourcePath and fileName are required.",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    runCatching {
                        saveToDownloads(File(sourcePath), fileName, mimeType)
                    }.onSuccess {
                        result.success(it)
                    }.onFailure {
                        result.error("SAVE_FAILED", it.message ?: "Could not save file.", null)
                    }
                }

                "openFile" -> {
                    val uriString = call.argument<String>("uri")
                    val mimeType = call.argument<String>("mimeType") ?: "*/*"
                    runCatching {
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(Uri.parse(uriString), mimeType)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                    }.onSuccess {
                        result.success(null)
                    }.onFailure {
                        result.error("OPEN_FAILED", it.message ?: "برنامه‌ای برای باز کردن این فایل پیدا نشد.", null)
                    }
                }

                "shareFile" -> {
                    val uriString = call.argument<String>("uri")
                    val mimeType = call.argument<String>("mimeType") ?: "*/*"
                    runCatching {
                        val sendIntent = Intent(Intent.ACTION_SEND).apply {
                            type = mimeType
                            putExtra(Intent.EXTRA_STREAM, Uri.parse(uriString))
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(Intent.createChooser(sendIntent, "اشتراک‌گذاری فایل").apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        })
                    }.onSuccess {
                        result.success(null)
                    }.onFailure {
                        result.error("SHARE_FAILED", it.message ?: "اشتراک‌گذاری ناموفق بود.", null)
                    }
                }

                "deleteFile" -> {
                    val uriString = call.argument<String>("uri")
                    runCatching {
                        if (uriString != null) {
                            contentResolver.delete(Uri.parse(uriString), null, null)
                        }
                    }
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        if (!pendingSharedText.isNullOrBlank()) {
            channel.invokeMethod("onSharedText", pendingSharedText)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val text = extractSharedText(intent)
        if (!text.isNullOrBlank()) {
            val channel = methodChannel
            if (channel != null) {
                channel.invokeMethod("onSharedText", text)
            } else {
                pendingSharedText = text
            }
        }
    }

    private fun extractSharedText(intent: Intent?): String? {
        if (intent == null) return null
        if (intent.action != Intent.ACTION_SEND) return null
        if (intent.type?.startsWith("text/") != true) return null
        return intent.getStringExtra(Intent.EXTRA_TEXT)
    }

    private fun isWifiConnected(): Boolean {
        return try {
            val manager = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
            val network = manager.activeNetwork ?: return false
            val capabilities = manager.getNetworkCapabilities(network) ?: return false
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
        } catch (e: Throwable) {
            true
        }
    }

    private fun saveToDownloads(source: File, fileName: String, mimeType: String): String {
        require(Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            "Android 10 or newer is required."
        }
        require(source.isFile) { "Temporary download does not exist." }

        val resolver = contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, fileName)
            put(MediaStore.Downloads.MIME_TYPE, mimeType)
            put(
                MediaStore.Downloads.RELATIVE_PATH,
                Environment.DIRECTORY_DOWNLOADS
            )
            put(MediaStore.Downloads.IS_PENDING, 1)
        }

        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: error("Android could not create the Downloads entry.")

        try {
            resolver.openOutputStream(uri)?.use { output ->
                source.inputStream().use { input ->
                    input.copyTo(output, bufferSize = 64 * 1024)
                }
            } ?: error("Android could not open the Downloads output stream.")

            val completed = ContentValues().apply {
                put(MediaStore.Downloads.IS_PENDING, 0)
            }
            resolver.update(uri, completed, null, null)
            return uri.toString()
        } catch (error: Throwable) {
            resolver.delete(uri, null, null)
            throw error
        }
    }
}
