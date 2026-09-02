package com.example.flutter_body

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * 樹莓派手部偵測專用:IMAGE 模式的 HandLandmarker
 *
 * ⚠️ 完全獨立於 MediaPipeBridge 的 LIVE_STREAM 偵測器:
 *    - 不同 RunningMode 的 HandLandmarker 不能共用同一個實例
 *    - 不碰手機原生相機那條路,不影響 startDetection/stopDetection/flipCamera
 *    - 純粹處理「單張 JPEG bytes → 21 個手部 landmark」,同步呼叫但跑在背景執行緒,
 *      避免卡住 UI thread
 *
 * 🚀 除錯新增:detect() 內加 Log.d,方便用
 *    `adb logcat | grep PiHand` 確認呼叫鏈是否真的跑到底、
 *    以及原生端是否真的偵測到手。
 */
class PiHandImageDetector(private val context: Context) {

    private var landmarker: HandLandmarker? = null
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    @Synchronized
    private fun ensureLandmarker(): HandLandmarker {
        var lm = landmarker
        if (lm == null) {
            val baseOptions = BaseOptions.builder()
                .setModelAssetPath("hand_landmarker.task")
                .build()
            val options = HandLandmarker.HandLandmarkerOptions.builder()
                .setBaseOptions(baseOptions)
                .setNumHands(1)
                .setMinHandDetectionConfidence(0.5f)
                .setMinHandPresenceConfidence(0.5f)
                .setMinTrackingConfidence(0.5f)
                .setRunningMode(RunningMode.IMAGE)
                .build()
            lm = HandLandmarker.createFromOptions(context, options)
            landmarker = lm
        }
        return lm
    }

    /**
     * jpegBytes: 樹莓派傳來的原始 JPEG bytes
     * isMirror: 是否需要左右鏡像(樹莓派固定架設一般不需要)
     * onResult: 在 main thread 呼叫,payload 直接對應 Dart 端 detectHandInImage 的回傳格式
     * onError: 在 main thread 呼叫
     */
    fun detect(
        jpegBytes: ByteArray,
        isMirror: Boolean,
        onResult: (Map<String, Any>) -> Unit,
        onError: (String) -> Unit
    ) {
        executor.execute {
            try {
                // 🚀 除錯新增:確認 Dart 端有沒有真的把 bytes 傳進來
                Log.d("PiHand", "detect() called, jpegBytes.size=${jpegBytes.size}, isMirror=$isMirror")

                val bitmap = BitmapFactory.decodeByteArray(jpegBytes, 0, jpegBytes.size)
                if (bitmap == null) {
                    Log.d("PiHand", "JPEG 解碼失敗")
                    mainHandler.post { onError("JPEG 解碼失敗") }
                    return@execute
                }

                // 🚀 除錯新增:確認解碼後的圖片尺寸是否正常
                Log.d("PiHand", "decoded bitmap: ${bitmap.width}x${bitmap.height}")

                val finalBitmap = if (isMirror) {
                    val matrix = Matrix().apply { postScale(-1f, 1f) }
                    Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
                } else {
                    bitmap
                }

                val mpImage = BitmapImageBuilder(finalBitmap).build()
                val result = ensureLandmarker().detect(mpImage)

                val handList = result.landmarks()
                val handDetected = handList.isNotEmpty()
                val landmarkList = mutableListOf<Map<String, Float>>()

                if (handDetected) {
                    for (lm in handList[0]) {
                        landmarkList.add(
                            mapOf(
                                "x" to lm.x(),
                                "y" to lm.y(),
                                "z" to lm.z()
                            )
                        )
                    }
                }

                // 🚀 除錯新增:確認原生偵測結果
                Log.d("PiHand", "handDetected=$handDetected handCount=${handList.size}")

                val payload = mapOf(
                    "landmarks" to landmarkList,
                    "handDetected" to handDetected
                )
                mainHandler.post { onResult(payload) }
            } catch (e: Exception) {
                Log.d("PiHand", "偵測例外: ${e.message}")
                mainHandler.post { onError(e.message ?: "手部偵測失敗") }
            }
        }
    }

    fun close() {
        executor.execute {
            try {
                landmarker?.close()
            } catch (_: Exception) {
            } finally {
                landmarker = null
            }
        }
    }
}