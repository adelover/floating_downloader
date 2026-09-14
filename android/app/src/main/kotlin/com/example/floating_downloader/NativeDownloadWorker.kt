package com.example.floating_downloader

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import java.io.BufferedInputStream
import java.net.HttpURLConnection
import java.net.URL

class NativeDownloadWorker(
    appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {
    private val prefs = appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val downloadId = id.toString()
    private val notificationId = (downloadId.hashCode() and 0x7fffffff).coerceAtLeast(1)

    override suspend fun doWork(): Result {
        val urlText = inputData.getString(KEY_URL) ?: return fail("Missing URL")
        val fileName = sanitizeFileName(inputData.getString(KEY_NAME) ?: "Floating_Download")
        val mimeType = inputData.getString(KEY_MIME) ?: "application/octet-stream"
        if (!urlText.startsWith("http://") && !urlText.startsWith("https://")) {
            return fail("Only HTTP and HTTPS URLs are supported")
        }
        createNotificationChannel()
        setForeground(createForegroundInfo(0.0, fileName))
        writeStatus("running", 0.0, null)

        val connection = (URL(urlText).openConnection() as HttpURLConnection).apply {
            connectTimeout = 20_000
            readTimeout = 30_000
            instanceFollowRedirects = true
            setRequestProperty("Accept", "*/*")
            setRequestProperty("User-Agent", USER_AGENT)
        }
        var outputUri: Uri? = null
        try {
            connection.connect()
            require(connection.url.protocol == "http" || connection.url.protocol == "https") {
                "Redirected URL must use HTTP or HTTPS"
            }
            if (connection.responseCode !in 200..399) {
                return fail("Server returned HTTP ${connection.responseCode}")
            }
            val resolver = applicationContext.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, mimeType)
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            outputUri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: return fail("Could not create Downloads entry")
            val total = connection.contentLengthLong
            var received = 0L
            resolver.openOutputStream(outputUri!!)?.use { output ->
                BufferedInputStream(connection.inputStream).use { input ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    while (true) {
                        while (prefs.getBoolean("$downloadId:paused", false)) {
                            writeStatus("paused", progress(received, total), null)
                            setForeground(createForegroundInfo(progress(received, total), fileName))
                            delay(500)
                            if (isStopped) throw CancellationException("Work stopped")
                        }
                        if (isStopped) throw CancellationException("Work stopped")
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                        received += count
                        val value = progress(received, total)
                        setProgress(androidx.work.workDataOf(KEY_PROGRESS to value))
                        writeStatus("running", value, null)
                        setForeground(createForegroundInfo(value, fileName))
                    }
                }
            } ?: error("Could not open Downloads output")
            resolver.update(outputUri!!, ContentValues().apply {
                put(MediaStore.Downloads.IS_PENDING, 0)
            }, null, null)
            writeStatus("completed", 1.0, outputUri.toString())
            updateNotification(fileName, 100, false)
            return Result.success(androidx.work.workDataOf(KEY_URI to outputUri.toString()))
        } catch (error: Throwable) {
            outputUri?.let { applicationContext.contentResolver.delete(it, null, null) }
            if (isStopped) return Result.failure()
            return fail(error.message ?: "Download failed")
        } finally {
            connection.disconnect()
        }
    }

    private fun progress(received: Long, total: Long): Double =
        if (total > 0) (received.toDouble() / total).coerceIn(0.0, 1.0) else 0.0

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

    private fun fail(message: String): Result {
        writeStatus("failed", 0.0, message)
        updateNotification(inputData.getString(KEY_NAME) ?: "Download", 0, false)
        return Result.failure(androidx.work.workDataOf(KEY_ERROR to message))
    }

    private fun writeStatus(state: String, progress: Double, value: String?) {
        prefs.edit().putString("$downloadId:state", state)
            .putFloat("$downloadId:progress", progress.toFloat())
            .putString("$downloadId:value", value).apply()
    }

    private fun createForegroundInfo(progress: Double, name: String): ForegroundInfo {
        return ForegroundInfo(
            notificationId,
            NotificationCompat.Builder(applicationContext, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_sys_download)
                .setContentTitle(name)
                .setContentText(if (progress > 0) "${(progress * 100).toInt()}%" else "Downloading")
                .setProgress(100, (progress * 100).toInt(), progress <= 0)
                .setOngoing(true)
                .build()
        )
    }

    private fun updateNotification(name: String, progress: Int, ongoing: Boolean) {
        val manager = applicationContext.getSystemService(NotificationManager::class.java)
        manager.notify(notificationId, NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle(name)
            .setContentText(if (progress == 100) "Download complete" else "Download failed")
            .setProgress(100, progress, false)
            .setOngoing(ongoing)
            .build())
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            applicationContext.getSystemService(NotificationManager::class.java)
                .createNotificationChannel(NotificationChannel(
                    CHANNEL_ID, "Downloads", NotificationManager.IMPORTANCE_LOW
                ))
        }
    }

    companion object {
        const val KEY_URL = "url"
        const val KEY_NAME = "name"
        const val KEY_MIME = "mime"
        const val KEY_PROGRESS = "progress"
        const val KEY_URI = "uri"
        const val KEY_ERROR = "error"
        const val PREFS = "native_downloads"
        const val CHANNEL_ID = "native_downloads"
        const val USER_AGENT =
            "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 Chrome/131 Mobile Safari/537.36"
    }
}
