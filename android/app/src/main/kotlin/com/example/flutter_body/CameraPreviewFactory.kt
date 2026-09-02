package com.example.flutter_body

import android.content.Context
import android.view.View
import androidx.camera.view.PreviewView
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class CameraPreviewFactory(private val context: Context) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(ctx: Context?, viewId: Int, args: Any?): PlatformView {
        return CameraPreviewView(context)
    }
}

class CameraPreviewView(private val context: Context) : PlatformView {
    val previewView = PreviewView(context).apply {
        implementationMode = PreviewView.ImplementationMode.COMPATIBLE // 🆕
    }

    override fun getView(): View = previewView
    override fun dispose() {}
}