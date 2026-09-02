package com.example.flutter_body

import android.app.*
import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaRecorder
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.IBinder
import android.util.DisplayMetrics
import androidx.core.app.NotificationCompat
import java.io.File
import java.text.SimpleDateFormat
import java.util.*

class ScreenRecordService : Service() {

    companion object {
        const val CHANNEL_ID = "screen_record_channel"
        const val NOTIFICATION_ID = 1001

        const val EXTRA_RESULT_CODE = "resultCode"
        const val EXTRA_DATA = "data"

        @Volatile var isRecording = false
        @Volatile var outputFilePath: String? = null

        private var instance: ScreenRecordService? = null

        fun startRecording(context: Context, resultCode: Int, data: Intent) {
            val intent = Intent(context, ScreenRecordService::class.java).apply {
                putExtra(EXTRA_RESULT_CODE, resultCode)
                putExtra(EXTRA_DATA, data)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stopRecording(context: Context): String? {
            val path = instance?.doStop()
            context.stopService(Intent(context, ScreenRecordService::class.java))
            return path
        }
    }

    private var mediaProjection: MediaProjection? = null
    private var mediaRecorder: MediaRecorder? = null
    private var virtualDisplay: VirtualDisplay? = null

    // ✅ 新增:MediaProjection.Callback,Android 14 (API 34) 開始必須註冊,
    // 否則 createVirtualDisplay() 會丟出:
    // "IllegalStateException: Must register a callback before starting capture."
    private val projectionCallback = object : MediaProjection.Callback() {
        override fun onStop() {
            // 使用者從系統通知列或系統本身中止投影時會觸發這裡。
            // 直接呼叫 doStop() 確保 MediaRecorder / VirtualDisplay 資源都被釋放,
            // 避免殘留的 recorder 佔用相機/編碼器資源導致下次錄影失敗。
            doStop()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val resultCode = intent?.getIntExtra(EXTRA_RESULT_CODE, Activity.RESULT_CANCELED)
            ?: Activity.RESULT_CANCELED
        val data = intent?.getParcelableExtra<Intent>(EXTRA_DATA)

        startForeground(NOTIFICATION_ID, buildNotification())

        if (data == null || resultCode != Activity.RESULT_OK) {
            stopSelf()
            return START_NOT_STICKY
        }

        val projectionManager =
            getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        mediaProjection = projectionManager.getMediaProjection(resultCode, data)

        // ✅ 必須在 createVirtualDisplay() 之前註冊 callback
        mediaProjection?.registerCallback(projectionCallback, null)

        try {
            startRecordingInternal()
        } catch (e: Exception) {
            e.printStackTrace()
            stopSelf()
        }

        return START_NOT_STICKY
    }

    private fun startRecordingInternal() {
        val metrics = DisplayMetrics()
        val windowManager = getSystemService(Context.WINDOW_SERVICE) as android.view.WindowManager
        @Suppress("DEPRECATION")
        windowManager.defaultDisplay.getRealMetrics(metrics)

        val width = metrics.widthPixels
        val height = metrics.heightPixels
        val density = metrics.densityDpi

        val dir = File(filesDir, "videos")
        if (!dir.exists()) dir.mkdirs()
        val fileName = "rehab_${SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())}.mp4"
        val outputFile = File(dir, fileName)
        outputFilePath = outputFile.absolutePath

        mediaRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(this)
        } else {
            @Suppress("DEPRECATION")
            MediaRecorder()
        }.apply {
            setVideoSource(MediaRecorder.VideoSource.SURFACE)
            setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            setVideoEncoder(MediaRecorder.VideoEncoder.H264)
            setVideoSize(width, height)
            setVideoFrameRate(30)
            setVideoEncodingBitRate(6_000_000)
            setOutputFile(outputFile.absolutePath)
            prepare()
        }

        virtualDisplay = mediaProjection?.createVirtualDisplay(
            "ScreenRecord",
            width, height, density,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            mediaRecorder?.surface,
            null, null
        )

        mediaRecorder?.start()
        isRecording = true
    }

    private fun doStop(): String? {
        if (!isRecording) return null
        return try {
            mediaRecorder?.apply {
                stop()
                reset()
                release()
            }
            virtualDisplay?.release()

            // ✅ 停止前先取消註冊 callback,避免 stop() 之後 callback 還被觸發
            try {
                mediaProjection?.unregisterCallback(projectionCallback)
            } catch (_: Exception) {
            }
            mediaProjection?.stop()

            isRecording = false
            outputFilePath
        } catch (e: Exception) {
            e.printStackTrace()
            isRecording = false
            null
        } finally {
            mediaRecorder = null
            virtualDisplay = null
            mediaProjection = null
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "訓練錄影",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("正在錄製訓練畫面")
            .setContentText("訓練結束後會自動停止")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setOngoing(true)
            .build()
    }

    override fun onDestroy() {
        doStop()
        instance = null
        super.onDestroy()
    }
}