package com.example.flutter_body

import android.app.Activity
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.plugin.platform.PlatformView

class MainActivity : FlutterActivity() {

    private val METHOD_CHANNEL = "com.rehabassist/mediapipe"
    private val LANDMARK_CHANNEL = "com.rehabassist/landmarks"
    private val SCREEN_RECORDER_CHANNEL = "com.rehabassist/screen_recorder"
    private val NATIVE_NOTIFICATION_CHANNEL = "com.example.flutter_body/native_notification"
    private val SCREEN_RECORD_REQUEST_CODE = 9001

    private var mediaPipeBridge: MediaPipeBridge? = null
    private var cameraPreviewView: CameraPreviewView? = null
    private var landmarkEventSink: EventChannel.EventSink? = null

    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingProjectionIntent: Intent? = null

    // 🚀 樹莓派手部偵測新增:IMAGE 模式偵測器,獨立於 mediaPipeBridge
    private var piHandImageDetector: PiHandImageDetector? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        flutterEngine.platformViewsController.registry.registerViewFactory(
            "com.rehabassist/camera_preview",
            object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
                override fun create(
                    ctx: android.content.Context?,
                    viewId: Int,
                    args: Any?
                ): PlatformView {
                    cameraPreviewView = CameraPreviewView(this@MainActivity)
                    return cameraPreviewView!!
                }
            }
        )

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, LANDMARK_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink?) {
                    landmarkEventSink = events
                    mediaPipeBridge?.landmarkEventSink = events
                }
                override fun onCancel(args: Any?) {
                    landmarkEventSink = null
                    mediaPipeBridge?.landmarkEventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startDetection" -> {
                        val useFront = call.argument<Boolean>("useFrontCamera") ?: false
                        mediaPipeBridge = MediaPipeBridge(
                            context = this,
                            useFrontCamera = useFront,
                            previewView = cameraPreviewView?.previewView
                        )
                        mediaPipeBridge?.landmarkEventSink = landmarkEventSink
                        mediaPipeBridge?.start()
                        result.success(null)
                    }
                    "stopDetection" -> {
                        mediaPipeBridge?.stop()
                        mediaPipeBridge = null
                        result.success(null)
                    }
                    "flipCamera" -> {
                        mediaPipeBridge?.flipCamera()
                        result.success(null)
                    }
                    // 🚀 樹莓派手部偵測新增:單張 JPEG → 21 個 hand landmark
                    // 完全獨立於上面三個 case,不影響手機原生即時串流偵測
                    "detectHandInImage" -> {
                        val jpegBytes = call.argument<ByteArray>("jpegBytes")
                        val isMirror = call.argument<Boolean>("isMirror") ?: false
                        if (jpegBytes == null) {
                            result.success(null)
                        } else {
                            if (piHandImageDetector == null) {
                                piHandImageDetector = PiHandImageDetector(this)
                            }
                            piHandImageDetector?.detect(
                                jpegBytes,
                                isMirror,
                                onResult = { payload -> result.success(payload) },
                                onError = { _ -> result.success(null) }
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // ── 螢幕錄影 channel ─────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_RECORDER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermission" -> {
                        // 每次請求權限前先清掉舊的 intent,
                        // 確保一定是拿最新一次使用者同意的 token
                        pendingProjectionIntent = null
                        pendingPermissionResult = result
                        val projectionManager =
                            getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                        startActivityForResult(
                            projectionManager.createScreenCaptureIntent(),
                            SCREEN_RECORD_REQUEST_CODE
                        )
                    }
                    "startRecording" -> {
                        val intent = pendingProjectionIntent
                        if (intent != null) {
                            ScreenRecordService.startRecording(
                                this, Activity.RESULT_OK, intent
                            )
                            // ✅ MediaProjection token 在 Android 14+ 只能用一次,
                            // 用掉之後立刻清空,避免下次錄影誤用同一個已失效的 token。
                            // 下次錄影前 Dart 端會重新呼叫 requestPermission()。
                            pendingProjectionIntent = null
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }
                    "stopRecording" -> {
                        val path = ScreenRecordService.stopRecording(this)
                        result.success(path)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NATIVE_NOTIFICATION_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scheduleNotification" -> {
                        val id = call.argument<Int>("id") ?: 0
                        val title = call.argument<String>("title") ?: ""
                        val body = call.argument<String>("body") ?: ""
                        val triggerAtMillis =
                            (call.argument<Number>("triggerAtMillis") ?: 0).toLong()
                        scheduleAlarm(id, title, body, triggerAtMillis)
                        result.success(true)
                    }
                    "cancelNotification" -> {
                        val id = call.argument<Int>("id") ?: 0
                        cancelAlarm(id)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == SCREEN_RECORD_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                pendingProjectionIntent = data
                pendingPermissionResult?.success(true)
            } else {
                pendingProjectionIntent = null
                pendingPermissionResult?.success(false)
            }
            pendingPermissionResult = null
        }
    }

    private fun scheduleAlarm(id: Int, title: String, body: String, triggerAtMillis: Long) {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager

        val intent = Intent(this, AlarmReceiver::class.java).apply {
            putExtra("title", title)
            putExtra("body", body)
            putExtra("notificationId", id)
        }

        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val pendingIntent = PendingIntent.getBroadcast(this, id, intent, flags)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerAtMillis,
                pendingIntent
            )
        } else {
            alarmManager.setExact(
                AlarmManager.RTC_WAKEUP,
                triggerAtMillis,
                pendingIntent
            )
        }
    }

    private fun cancelAlarm(id: Int) {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, AlarmReceiver::class.java)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent = PendingIntent.getBroadcast(this, id, intent, flags)
        alarmManager.cancel(pendingIntent)
    }

    // 🚀 樹莓派手部偵測新增:App 結束時釋放 IMAGE 模式偵測器資源
    override fun onDestroy() {
        piHandImageDetector?.close()
        piHandImageDetector = null
        super.onDestroy()
    }
}