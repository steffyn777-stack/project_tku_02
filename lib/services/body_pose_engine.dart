// lib/services/body_pose_engine.dart
//
// ══════════════════════════════════════════════════════════════════
//  全身姿勢偵測引擎 (RTMPose 133 點)
//
//  ⚠️ 全 App 唯一含 ONNX 推論的檔案。
//     要換模型 / 改推論邏輯,只改這一個檔案。
//
//  邏輯來源:原封不動搬自 body_test_screen.dart 那套已驗證成功的方案。
//  (convertYUV / ONNX 推論 / EMA 平滑,參數完全相同)
//
//  🚀 修正:樹莓派/外部畫面來源不應套用手機鏡頭的旋轉翻轉公式,
//     否則骨架會上下顛倒。改用獨立欄位區分「手機相機幀」與
//     「外部畫面幀(樹莓派/影片分析)」,兩條路徑互不影響。
//
//  用法:
//    final engine = BodyPoseEngine();
//    await engine.init();
//    // 監聽骨架更新 → 畫骨架
//    engine.poseNotifier.addListener(...)
//    // 啟動相機串流
//    engine.startCamera();
//    // 結束
//    engine.dispose();
// ══════════════════════════════════════════════════════════════════

import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime_v2/onnxruntime_v2.dart';
import '../models/pose_data.dart';

import 'package:image/image.dart' as img;

// ── 推論輸入封裝 ──────────────────────────────────────────────────
class InferenceInput {
  final Uint8List yPlane;
  final Uint8List uPlane;
  final Uint8List vPlane;
  final int imgW;
  final int imgH;
  final int yRowStride;
  final int uvRowStride;
  final int uvPixelStride;
  final bool isFrontCamera;

  InferenceInput({
    required this.yPlane,
    required this.uPlane,
    required this.vPlane,
    required this.imgW,
    required this.imgH,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixelStride,
    required this.isFrontCamera,
  });
}

// ── YUV → Float32 轉換 (搬自 body_test_screen,參數完全相同) ───────
final Float32List _sharedYuvBuffer = Float32List(3 * 256 * 192);

Float32List convertYUV(InferenceInput input) {
  const int inputH = 256;
  const int inputW = 192;
  const int area = inputH * inputW;

  final double ratioX = input.imgW / inputH;
  final double ratioY = input.imgH / inputW;

  int idx = 0;
  for (int y = 0; y < inputH; y++) {
    final int srcX =
        ((inputH - 1 - y) * ratioX).toInt().clamp(0, input.imgW - 1);
    final int halfSrcX = srcX >> 1;

    for (int x = 0; x < inputW; x++) {
      final int srcY = (x * ratioY).toInt().clamp(0, input.imgH - 1);

      final int yIdx = srcY * input.yRowStride + srcX;
      final int uvIdx =
          (srcY >> 1) * input.uvRowStride + halfSrcX * input.uvPixelStride;

      final int yVal = input.yPlane[yIdx];
      final int uVal = input.uPlane[uvIdx] - 128;
      final int vVal = input.vPlane[uvIdx] - 128;

      final double r = yVal + 1.402 * vVal;
      final double g = yVal - 0.344 * uVal - 0.714 * vVal;
      final double b = yVal + 1.772 * uVal;

      _sharedYuvBuffer[idx] = (r - 123.675) / 58.395;
      _sharedYuvBuffer[area + idx] = (g - 116.28) / 57.12;
      _sharedYuvBuffer[2 * area + idx] = (b - 103.53) / 57.375;
      idx++;
    }
  }
  return _sharedYuvBuffer;
}

// ── RGB → Float32 轉換(供影片分析 / 樹莓派畫面用) ─────────────────
// needsRotation:
//   true  (預設) → 來源畫面是「橫躺」的原始感光元件資料(手機錄影抽幀用),
//                  需要跟 convertYUV 一樣做 90 度校正映射
//   false         → 來源畫面本身已經是正的(樹莓派 JPEG 畫面),
//                  用一般等比縮放映射即可,不能套用旋轉映射,
//                  不然骨架點位會整個歪掉(x/y 被錯誤交換)
Float32List convertRGB(
  Uint8List rgb,
  int srcW,
  int srcH, {
  bool isFrontCamera = false,
  bool needsRotation = true,
}) {
  const int inputH = 256;
  const int inputW = 192;
  const int area = inputH * inputW;

  final Float32List out = Float32List(3 * area);

  if (needsRotation) {
    // ── 90 度校正映射(手機感光元件原始畫面 / 手機錄影抽幀用) ──
    final double ratioX = srcW / inputH;
    final double ratioY = srcH / inputW;

    int idx = 0;
    for (int y = 0; y < inputH; y++) {
      final int srcX = ((inputH - 1 - y) * ratioX).toInt().clamp(0, srcW - 1);
      for (int x = 0; x < inputW; x++) {
        final int srcY = (x * ratioY).toInt().clamp(0, srcH - 1);
        final int pixelIdx = (srcY * srcW + srcX) * 3;

        final int r = rgb[pixelIdx];
        final int g = rgb[pixelIdx + 1];
        final int b = rgb[pixelIdx + 2];

        out[idx] = (r - 123.675) / 58.395;
        out[area + idx] = (g - 116.28) / 57.12;
        out[2 * area + idx] = (b - 103.53) / 57.375;
        idx++;
      }
    }
  } else {
    // ── 一般等比縮放,不做旋轉(樹莓派畫面用) ──
    final double ratioX = srcW / inputW;
    final double ratioY = srcH / inputH;

    int idx = 0;
    for (int y = 0; y < inputH; y++) {
      final int srcY = (y * ratioY).toInt().clamp(0, srcH - 1);
      for (int x = 0; x < inputW; x++) {
        final int srcX = (x * ratioX).toInt().clamp(0, srcW - 1);
        final int pixelIdx = (srcY * srcW + srcX) * 3;

        final int r = rgb[pixelIdx];
        final int g = rgb[pixelIdx + 1];
        final int b = rgb[pixelIdx + 2];

        out[idx] = (r - 123.675) / 58.395;
        out[area + idx] = (g - 116.28) / 57.12;
        out[2 * area + idx] = (b - 103.53) / 57.375;
        idx++;
      }
    }
  }

  return out;
}

// ══════════════════════════════════════════════════════════════════
//  BodyPoseEngine — 相機 + ONNX + 133 點,全包
// ══════════════════════════════════════════════════════════════════
class BodyPoseEngine {
  static const int numKpts = 133;
  static const double scoreThreshold = 0.3;

  CameraController? _cam;
  OrtSession? _poseSession;
  OrtRunOptions? _runOpts;
  bool _processing = false;
  bool _isFrontCamera = true;

  // 🚀 修正新增:區分「手機相機幀」與「外部畫面幀(樹莓派/影片分析)」,
  // 兩者座標映射公式完全不同,不能共用 _isFrontCamera 這個欄位判斷。
  bool _isExternalFrame = false;
  bool _externalMirror = false;

  List<Offset> _smoothedKeypoints = [];
  bool _disposed = false;

  // 目前正在跑的那一次推論(runAsync 還沒回來前不能 release session/runOpts)
  // dispose() 必須先等這個 Future 完成,才能釋放 ONNX 資源,
  // 不然背景執行緒還在用 mutex 時被 release/destroy,就會炸 native crash
  // (FORTIFY: pthread_mutex_lock called on a destroyed mutex)。
  Future<void>? _pendingInference;

  // 對外:骨架資料 (畫骨架的人監聽這個)
  final ValueNotifier<PoseData> poseNotifier =
      ValueNotifier(PoseData.empty());

  // 對外:相機是否就緒
  final ValueNotifier<bool> cameraReady = ValueNotifier(false);

  // ── 電視投放新增 ──────────────────────────────────────────
  // 對外:JPEG 影像 (電視投放時,控制端把畫面傳給顯示端用)
  final ValueNotifier<Uint8List?> imageNotifier = ValueNotifier(null);

  // 電視顯示端旗標:true = 純顯示端,不開相機、不載模型,只吃 updateFromRemote
  bool _isReceiver = false;
  // JPEG 生成節流(限制 ~30fps,避免每幀都轉太吃資源)
  bool _jpegProcessing = false;
  // 🖥️ 投放開關:只有真的在投放電視時才生成 JPEG,平常訓練不生成(省效能)
  bool castEnabled = false;

  bool get isReceiver => _isReceiver;

  CameraController? get cameraController => _cam;
  bool get isFrontCamera => _isFrontCamera;

  // ── 初始化:相機 + 模型 ──────────────────────────────────────────
  Future<void> init({bool asReceiver = false}) async {
    _isReceiver = asReceiver;
    if (_isReceiver) {
      // 電視顯示端:不開相機、不載模型,直接標記就緒
      cameraReady.value = true;
      return;
    }
    await _initCamera();
    await _initOnnx();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    final cam = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    _isFrontCamera = cam.lensDirection == CameraLensDirection.front;

    final ctrl = CameraController(
      cam,
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await ctrl.initialize();
    _cam = ctrl;
  }

  Future<void> _initOnnx() async {
    final opts = OrtSessionOptions()
      ..setIntraOpNumThreads(4)
      ..setInterOpNumThreads(1)
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);

    try {
      opts.appendXnnpackProvider();
    } catch (_) {
      debugPrint('XNNPACK 啟動失敗,退回預設 CPU 模式');
    }

    final bytes = (await rootBundle.load('assets/rtmpose_wholebody.onnx'))
        .buffer
        .asUint8List();
    _poseSession = OrtSession.fromBuffer(bytes, opts);
    _runOpts = OrtRunOptions();

    cameraReady.value = true;
  }

  // ── 電視投放新增:接收遠端算好的骨架,直接顯示(不推論) ──────────
  void updateFromRemote(List<Offset> keypoints, List<double> scores) {
    if (!_isReceiver) return;
    poseNotifier.value = PoseData(keypoints, scores);
  }

  // ── 啟動相機串流 ──────────────────────────────────────────────────
  Future<void> startCamera() async {
    if (_cam == null) return;
    await _cam!.startImageStream(_onFrame);
  }

  // ── 切換鏡頭 ──────────────────────────────────────────────────────
  Future<void> switchCamera() async {
    if (_cam == null) return;
    await _cam!.stopImageStream();
    await _cam!.dispose();

    final cameras = await availableCameras();
    final next = cameras.firstWhere(
      (c) =>
          c.lensDirection !=
          (_isFrontCamera
              ? CameraLensDirection.front
              : CameraLensDirection.back),
      orElse: () => cameras.first,
    );
    _isFrontCamera = next.lensDirection == CameraLensDirection.front;

    final ctrl = CameraController(
      next,
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await ctrl.initialize();
    _cam = ctrl;
    await _cam!.startImageStream(_onFrame);
  }

  // ── 每幀進入點 ────────────────────────────────────────────────────
  void _onFrame(CameraImage image) {
    //if (_processing || _poseSession == null) return;
    if (_disposed || _processing || _poseSession == null) return;
    _processing = true;

    // 🚀 修正新增:確保從外部畫面(樹莓派)切回手機鏡頭時,
    // 座標映射邏輯正確切回手機那一套,不會殘留外部畫面的旗標。
    _isExternalFrame = false;

    final input = InferenceInput(
      yPlane: image.planes[0].bytes,
      uPlane: image.planes[1].bytes,
      vPlane: image.planes[2].bytes,
      imgW: image.width,
      imgH: image.height,
      yRowStride: image.planes[0].bytesPerRow,
      uvRowStride: image.planes[1].bytesPerRow,
      uvPixelStride: image.planes[1].bytesPerPixel ?? 1,
      isFrontCamera: _isFrontCamera,
    );

    final converted = convertYUV(input);
    _pendingInference = _runInference(converted);

    // ── 電視投放新增:限制 ~30fps 生成 JPEG,給顯示端串流用 ──
    // ── 電視投放新增:只有投放時才生成 JPEG(castEnabled),平常訓練跳過省效能 ──
    if (castEnabled && !_jpegProcessing) {
      _jpegProcessing = true;
      _generateJpeg(image).then((_) {
        Future.delayed(const Duration(milliseconds: 33), () {
          if (!_disposed) _jpegProcessing = false;
        });
      });
    }
  }

  // ── 電視投放新增:把相機幀轉成 JPEG,丟到 imageNotifier ──────────
  Future<void> _generateJpeg(CameraImage image) async {
    try {
      final img.Image? processed = _convertCameraImage(image);
      if (processed != null) {
        final jpeg = Uint8List.fromList(img.encodeJpg(processed, quality: 50));
        imageNotifier.value = jpeg;
      }
    } catch (e) {
      debugPrint('Error generating JPEG: $e');
    }
  }

  img.Image? _convertCameraImage(CameraImage image) {
    try {
      final int width = image.width;
      final int height = image.height;
      final img.Image result = img.Image(width: height, height: width);

      final Uint8List yPlane = image.planes[0].bytes;
      final Uint8List uPlane = image.planes[1].bytes;
      final Uint8List vPlane = image.planes[2].bytes;

      final int yRowStride = image.planes[0].bytesPerRow;
      final int uvRowStride = image.planes[1].bytesPerRow;
      final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int yIdx = y * yRowStride + x;
          final int uvIdx = (y >> 1) * uvRowStride + (x >> 1) * uvPixelStride;

          final int yVal = yPlane[yIdx];
          final int uVal = uPlane[uvIdx] - 128;
          final int vVal = vPlane[uvIdx] - 128;

          int r = (yVal + 1.402 * vVal).toInt().clamp(0, 255);
          int g =
              (yVal - 0.344136 * uVal - 0.714136 * vVal).toInt().clamp(0, 255);
          int b = (yVal + 1.772 * uVal).toInt().clamp(0, 255);

          // 順時針轉 90 度:(x, y) -> (y, width - 1 - x)
          result.setPixelRgb(y, width - 1 - x, r, g, b);
        }
      }

      if (_isFrontCamera) {
        return img.flipHorizontal(result);
      }
      return result;
    } catch (e) {
      debugPrint("Error converting CameraImage: $e");
    }
    return null;
  }

  // ── 供影片分析用的外部入口 ──────────────────────────────────────────
  // 傳「解碼後的 RGB bytes」進來,回傳一次推論結果(不用相機)
  //
  // 用法:
  //   1. 用 video_thumbnail 抽出一幀 JPEG bytes
  //   2. 用 `image` 套件解碼成 RGB
  //   3. 呼叫這個方法 → poseNotifier 會 emit 該幀的 landmarks
  //
  // isMirror:
  //   影片分析(手機錄影抽幀,needsRotation:true)沿用原本語意,
  //   代表是否鏡像。
  //   樹莓派畫面(needsRotation:false)時代表畫面是否需要左右鏡像,
  //   一般固定架設鏡頭不需要,傳 false 即可。
  Future<void> processExternalFrame(
    Uint8List rgbBytes,
    int width,
    int height, {
    bool isMirror = false,
    bool needsRotation = true,
  }) async {
    if (_disposed || _poseSession == null) return;

    // 等目前正在跑的推論結束(避免衝突)
    if (_processing) {
      if (_pendingInference != null) {
        try {
          await _pendingInference!.timeout(const Duration(seconds: 3));
        } catch (_) {}
      }
    }

    _processing = true;

    // 🚀 修正:外部畫面(樹莓派/影片分析)走獨立旗標,
    // 不再覆蓋 _isFrontCamera,避免跟手機鏡頭的座標映射邏輯互相污染。
    _isExternalFrame = true;
    _externalMirror = isMirror;

    final converted = convertRGB(
      rgbBytes,
      width,
      height,
      isFrontCamera: isMirror,
      needsRotation: needsRotation,
    );
    _pendingInference = _runInference(converted);
    await _pendingInference;
  }

  // ── ONNX 推論 + 解碼 + EMA (搬自 body_test_screen,邏輯相同) ──────
  Future<void> _runInference(Float32List converted) async {
    OrtValueTensor? tensor;
    List<OrtValue?>? outputs;

    try {
      const inputH = 256, inputW = 192;
      tensor = OrtValueTensor.createTensorWithDataList(
          converted, [1, 3, inputH, inputW]);

      outputs = await _poseSession!.runAsync(_runOpts!, {'input': tensor});
      if (outputs == null || outputs.length < 2) return;

      final xBatch = (outputs[0]!.value as List)[0] as List;
      final yBatch = (outputs[1]!.value as List)[0] as List;

      final keypoints = <Offset>[];
      final scores = <double>[];

      for (int i = 0; i < numKpts; i++) {
        final xArr = xBatch[i] as List;
        final yArr = yBatch[i] as List;
        if (xArr.isEmpty || yArr.isEmpty) continue;

        double maxX = -double.infinity, maxY = -double.infinity;
        int xi = 0, yi = 0;
        for (int j = 0; j < xArr.length; j++) {
          final v = (xArr[j] as num).toDouble();
          if (v > maxX) {
            maxX = v;
            xi = j;
          }
        }
        for (int j = 0; j < yArr.length; j++) {
          final v = (yArr[j] as num).toDouble();
          if (v > maxY) {
            maxY = v;
            yi = j;
          }
        }

        scores.add((maxX + maxY) / 2);
        final rawX = xi / xArr.length.toDouble();
        final rawY = yi / yArr.length.toDouble();

        if (_isExternalFrame) {
          // 🚀 樹莓派/外部畫面專用映射:
          // 畫面本身已經是正的(needsRotation:false 沒做任何旋轉),
          // 不套用手機鏡頭那套旋轉校正的翻轉公式,
          // 否則骨架會上下顛倒。只有需要鏡像時才翻 x 軸。
          if (_externalMirror) {
            keypoints.add(Offset(1.0 - rawX, rawY));
          } else {
            keypoints.add(Offset(rawX, rawY));
          }
        } else if (_isFrontCamera) {
          keypoints.add(Offset(1.0 - rawX, rawY));
        } else {
          keypoints.add(Offset(1.0 - rawX, 1.0 - rawY));
        }
      }

      // EMA 動態平滑 (參數與 body_test_screen 相同:dist*40, clamp 0.15~1.0)
      if (_smoothedKeypoints.isEmpty ||
          _smoothedKeypoints.length != keypoints.length) {
        _smoothedKeypoints = List.from(keypoints);
      } else {
        for (int i = 0; i < keypoints.length; i++) {
          if (i >= scores.length || scores[i] < scoreThreshold) continue;
          final cur = keypoints[i];
          final prev = _smoothedKeypoints[i];
          final dx = cur.dx - prev.dx;
          final dy = cur.dy - prev.dy;
          final dist = math.sqrt(dx * dx + dy * dy);
          final alpha = (dist * 40).clamp(0.15, 1.0);
          _smoothedKeypoints[i] = Offset(
            alpha * cur.dx + (1 - alpha) * prev.dx,
            alpha * cur.dy + (1 - alpha) * prev.dy,
          );
        }
      }

      poseNotifier.value =
          PoseData(List.from(_smoothedKeypoints), scores);
    } catch (e) {
      debugPrint('BodyPoseEngine 推論錯誤: $e');
    } finally {
      tensor?.release();
      if (outputs != null) {
        for (final out in outputs) {
          out?.release();
        }
      }
      // 散熱節能鎖 (與 body_test_screen 相同:休息 20ms)
      Future.delayed(const Duration(milliseconds: 20), () {
        _processing = false;
      });
    }
  }

  // ── 釋放 ──────────────────────────────────────────────────────────
  Future<void> dispose() async {
    if (_disposed) return;       // 防重複 dispose
    _disposed = true;            // 先擋住 _onFrame,不會再啟動新的推論

    try {
      if (_cam?.value.isStreamingImages == true) {
        await _cam!.stopImageStream();
      }
    } catch (_) {}
    
    try {
      await _cam?.dispose();
    } catch (_) {}
    _cam = null;

    // 關鍵修正:等目前「正在跑」的那一次推論真的跑完,
    // 才可以 release session / runOpts。
    // 不等的話,runAsync() 還在背景執行緒跑,session 卻被 release 掉,
    // ONNX Runtime 內部 mutex 被銷毀時還在被使用 → native SIGABRT 閃退。
    // 加 timeout 是保險,避免極端情況卡住 dispose 不回傳。
    if (_pendingInference != null) {
      try {
        await _pendingInference!.timeout(const Duration(seconds: 3));
      } catch (_) {}
    }

    try {
      _runOpts?.release();
    } catch (_) {}
    try {
      _poseSession?.release();
    } catch (_) {}
    
    poseNotifier.dispose();
    imageNotifier.dispose();   // ← 電視投放新增
    cameraReady.dispose();
  }
}