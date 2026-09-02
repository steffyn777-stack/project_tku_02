package com.example.flutter_body

import android.content.Context
import android.os.SystemClock
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarkerResult
import io.flutter.plugin.common.EventChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import android.util.Base64

class MediaPipeBridge(
    private val context: Context,
    private var useFrontCamera: Boolean,
    private val previewView: PreviewView?
) {
    var landmarkEventSink: EventChannel.EventSink? = null

    private var handLandmarker: HandLandmarker? = null
    private var cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private var cameraProvider: ProcessCameraProvider? = null

    private var isProcessing = false
    private var smoothedLandmarks = Array(21) { FloatArray(3) }
    private var isFirstFrame = true
    private val SMOOTHING_FACTOR = 0.65f
    private var lastEventSendTime = 0L
    private val reusableMatrix = android.graphics.Matrix()
    private var lastJpegSendTime = 0L
    private var currentJpegBase64: String? = null

    fun start() {
        setupMediaPipe()
        startCamera()
    }

    fun stop() {
        cameraProvider?.unbindAll()
        handLandmarker?.close()
        cameraExecutor.shutdown()
    }

    fun flipCamera() {
        useFrontCamera = !useFrontCamera
        isFirstFrame = true
        startCamera()
    }

    private fun setupMediaPipe() {
        try {
            val baseOptions = BaseOptions.builder()
                .setModelAssetPath("hand_landmarker.task")
                .build()
            val options = HandLandmarker.HandLandmarkerOptions.builder()
                .setBaseOptions(baseOptions)
                .setNumHands(1)
                .setMinHandDetectionConfidence(0.5f)
                .setMinHandPresenceConfidence(0.5f)
                .setMinTrackingConfidence(0.5f)
                .setRunningMode(RunningMode.LIVE_STREAM)
                .setResultListener { result, _ ->
                    processResult(result)
                    isProcessing = false
                }
                .setErrorListener { _ ->
                    isProcessing = false
                }
                .build()
            handLandmarker = HandLandmarker.createFromOptions(context, options)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun startCamera() {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
        cameraProviderFuture.addListener({
            cameraProvider = cameraProviderFuture.get()
            previewView?.scaleType = PreviewView.ScaleType.FIT_CENTER

            val preview = Preview.Builder()
                .setTargetAspectRatio(AspectRatio.RATIO_4_3)
                .build().also {
                    it.setSurfaceProvider(previewView?.surfaceProvider)
                }

            val imageAnalyzer = ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .setTargetAspectRatio(AspectRatio.RATIO_4_3)
                .build()
                .also { analysis ->
                    analysis.setAnalyzer(cameraExecutor) { imageProxy ->
                        if (isProcessing) {
                            imageProxy.close()
                            return@setAnalyzer
                        }
                        isProcessing = true
                        val rotation = imageProxy.imageInfo.rotationDegrees
                        val bitmap = imageProxy.toBitmap()
                        val rotated = rotateBitmap(bitmap, rotation)

                        // Always ensure the image is in Portrait orientation before sending
                        val portrait = if (rotated.width > rotated.height) {
                            rotateBitmap(rotated, 90)
                        } else {
                            rotated
                        }

                        val flipped = if (useFrontCamera) flipBitmap(portrait) else portrait

                        // Also send JPEG frame occasionally for mirroring
                        val now = SystemClock.uptimeMillis()
                        if (now - lastJpegSendTime > 100) { // 10 FPS
                            lastJpegSendTime = now
                            val baos = ByteArrayOutputStream()
                            flipped.compress(android.graphics.Bitmap.CompressFormat.JPEG, 75, baos)
                            val jpegBytes = baos.toByteArray()
                            currentJpegBase64 = Base64.encodeToString(jpegBytes, Base64.NO_WRAP)
                        }

                        val mpImage = BitmapImageBuilder(flipped).build()
                        handLandmarker?.detectAsync(mpImage, SystemClock.uptimeMillis())
                        imageProxy.close()
                    }
                }

            val lensFacing = if (useFrontCamera)
                CameraSelector.LENS_FACING_FRONT
            else
                CameraSelector.LENS_FACING_BACK

            val cameraSelector = CameraSelector.Builder()
                .requireLensFacing(lensFacing)
                .build()

            cameraProvider?.unbindAll()
            cameraProvider?.bindToLifecycle(
                context as LifecycleOwner,
                cameraSelector,
                preview,
                imageAnalyzer
            )
        }, ContextCompat.getMainExecutor(context))
    }

    private fun rotateBitmap(bitmap: android.graphics.Bitmap, degrees: Int): android.graphics.Bitmap {
        if (degrees == 0) return bitmap
        reusableMatrix.reset()
        reusableMatrix.postRotate(degrees.toFloat())
        return android.graphics.Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, reusableMatrix, true)
    }

    private fun flipBitmap(bitmap: android.graphics.Bitmap): android.graphics.Bitmap {
        reusableMatrix.reset()
        reusableMatrix.postScale(-1f, 1f, bitmap.width / 2f, bitmap.height / 2f)
        return android.graphics.Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, reusableMatrix, true)
    }

    private fun processResult(result: HandLandmarkerResult) {
        val isFront = useFrontCamera
        val landmarks = if (result.landmarks().isNotEmpty()) result.landmarks()[0] else null

        if (landmarks == null) {
            isFirstFrame = true
            val now = SystemClock.uptimeMillis()
            if (now - lastEventSendTime > 32) {
                lastEventSendTime = now
                val resMap = mutableMapOf<String, Any>(
                    "landmarks" to emptyList<Map<String, Float>>(),
                    "handDetected" to false
                )
                // Always try to include latest JPEG frame
                currentJpegBase64?.let {
                    resMap["imageBase64"] = it
                    currentJpegBase64 = null
                }
                (context as? android.app.Activity)?.runOnUiThread {
                    landmarkEventSink?.success(resMap)
                }
            }
            return
        }

        val landmarkList = mutableListOf<Map<String, Float>>()
        for (i in landmarks.indices) {
            val lm = landmarks[i]
            // We NO LONGER mirror the raw landmarks here.
            // We want raw 0..1 coordinates relative to the BITMAP passed to MediaPipe.
            val rawX = lm.x()
            val rawY = lm.y()
            val rawZ = lm.z()

            if (isFirstFrame) {
                smoothedLandmarks[i][0] = rawX
                smoothedLandmarks[i][1] = rawY
                smoothedLandmarks[i][2] = rawZ
            } else {
                smoothedLandmarks[i][0] = (SMOOTHING_FACTOR * rawX) + ((1 - SMOOTHING_FACTOR) * smoothedLandmarks[i][0])
                smoothedLandmarks[i][1] = (SMOOTHING_FACTOR * rawY) + ((1 - SMOOTHING_FACTOR) * smoothedLandmarks[i][1])
                smoothedLandmarks[i][2] = (SMOOTHING_FACTOR * rawZ) + ((1 - SMOOTHING_FACTOR) * smoothedLandmarks[i][2])
            }

            landmarkList.add(mapOf(
                "x" to smoothedLandmarks[i][0],
                "y" to smoothedLandmarks[i][1],
                "z" to smoothedLandmarks[i][2]
            ))
        }
        isFirstFrame = false

        val now = SystemClock.uptimeMillis()
        if (now - lastEventSendTime > 40) {
            lastEventSendTime = now
            val resMap = mutableMapOf<String, Any>(
                "landmarks" to landmarkList,
                "handDetected" to true
            )
            // Include JPEG frame if we have one
            currentJpegBase64?.let {
                resMap["imageBase64"] = it
                currentJpegBase64 = null // Clear after sending
            }

            (context as? android.app.Activity)?.runOnUiThread {
                landmarkEventSink?.success(resMap)
            }
        }
    }
}