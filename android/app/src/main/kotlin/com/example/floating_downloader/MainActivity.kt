package com.example.floating_downloader

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.floating_downloader/storage"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getCacheDirectory" -> result.success(cacheDir.absolutePath)

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

                    else -> result.notImplemented()
                }
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
