package com.example.floating_downloader

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import java.io.BufferedInputStream
import java.net.HttpURLConnection
import java.net.URL

class DownloadManagerRepository(private val context: Context) {
    suspend fun download(
        id: String,
        url: String,
        fileName: String,
        mimeType: String,
        isPaused: () -> Boolean,
        isCancelled: () -> Boolean,
        onProgress: suspend (received: Long, total: Long) -> Unit
    ): Result<Uri> {
        val parsed = runCatching { URL(url) }.getOrElse {
            return Result.failure(IllegalArgumentException("Invalid download URL"))
        }
        require(parsed.protocol == "http" || parsed.protocol == "https") {
            "Only HTTP and HTTPS URLs are supported"
        }

        val connection = (parsed.openConnection() as HttpURLConnection).apply {
            connectTimeout = 20_000
            readTimeout = 30_000
            instanceFollowRedirects = true
            setRequestProperty("Accept", "*/*")
            setRequestProperty("User-Agent", NativeDownloadWorker.USER_AGENT)
        }
        var outputUri: Uri? = null
        try {
            connection.connect()
            require(connection.url.protocol == "http" || connection.url.protocol == "https") {
                "Redirected URL must use HTTP or HTTPS"
            }
            require(connection.responseCode in 200..299) {
                "Server returned HTTP ${connection.responseCode}"
            }

            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, sanitizeFileName(fileName))
                put(MediaStore.Downloads.MIME_TYPE, mimeType)
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            outputUri = context.contentResolver.insert(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                values
            ) ?: error("Could not create Downloads entry")

            val total = connection.contentLengthLong
            var received = 0L
            context.contentResolver.openOutputStream(outputUri)?.use { output ->
                BufferedInputStream(connection.inputStream).use { input ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    while (true) {
                        while (isPaused()) {
                            onProgress(received, total)
                            delay(500)
                            if (isCancelled()) throw CancellationException("Download cancelled")
                        }
                        if (isCancelled()) throw CancellationException("Download cancelled")
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                        received += count
                        onProgress(received, total)
                    }
                }
            } ?: error("Could not open Downloads output")

            context.contentResolver.update(
                outputUri,
                ContentValues().apply {
                    put(MediaStore.Downloads.IS_PENDING, 0)
                },
                null,
                null
            )
            return Result.success(outputUri)
        } catch (error: Throwable) {
            outputUri?.let { context.contentResolver.delete(it, null, null) }
            return Result.failure(error)
        } finally {
            connection.disconnect()
        }
    }

    private fun sanitizeFileName(value: String): String {
        var name = value.trim()
            .replace(Regex("[\\\\/:*?\"<>|]"), "_")
            .replace(Regex("[\\u0000-\\u001f\\u007f]"), "_")
            .replace(Regex("\\s+"), " ")
            .replace(Regex("[. ]+$"), "")
        if (name.isEmpty()) name = "Floating_Download"
        if (Regex("^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\\..*)?$", RegexOption.IGNORE_CASE)
                .matches(name)) {
            name = "_$name"
        }
        return name.take(90)
    }
}
