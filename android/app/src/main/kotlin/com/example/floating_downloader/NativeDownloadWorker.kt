package com.example.floating_downloader

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters

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

        val result = DownloadManagerRepository(applicationContext).download(
            id = downloadId,
            url = urlText,
            fileName = fileName,
            mimeType = mimeType,
            isPaused = { prefs.getBoolean("$downloadId:paused", false) },
            isCancelled = { isStopped },
            onProgress = { received, total ->
                val value = progress(received, total)
                setProgress(androidx.work.workDataOf(KEY_PROGRESS to value))
                writeStatus(
                    if (prefs.getBoolean("$downloadId:paused", false)) "paused" else "running",
                    value,
                    null
                )
                setForeground(createForegroundInfo(value, fileName))
            }
        )
        return result.fold(
            onSuccess = { uri ->
                writeStatus("completed", 1.0, uri.toString())
                updateNotification(fileName, 100, false)
                Result.success(androidx.work.workDataOf(KEY_URI to uri.toString()))
            },
            onFailure = { error ->
                if (isStopped) Result.failure()
                else fail(error.message ?: "Download failed")
            }
        )
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
