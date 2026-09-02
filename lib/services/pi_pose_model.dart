// lib/services/pi_pose_model.dart
//
// ══════════════════════════════════════════════════════════════════
//  IPoseModel 的樹莓派實作
//  - 透過 PiHandSource 連線樹莓派畫面,呼叫原生 detectHandInImage
//    (IMAGE 單張模式),把結果轉成 PoseFrame 吐進 frameStream
//  - 完全不影響 MediaPipeModel(手機原生即時串流)那條路
//  - trainingStream 目前沒有樹莓派對應的來源,回傳空 stream 即可,
//    因為動作判斷邏輯(base_rehab_action 等)吃的是 frameStream,
//    不依賴這個
// ══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'mediapipe_service.dart';
import 'pi_hand_source.dart';
import 'pose_model_interface.dart';

class PiPoseModel implements IPoseModel {
  final String ip;
  final int port;

  final MediaPipeService _svc = MediaPipeService();
  PiHandSource? _source;

  final StreamController<PoseFrame> _frameCtrl =
      StreamController<PoseFrame>.broadcast();
  final StreamController<TrainingUpdate> _trainingCtrl =
      StreamController<TrainingUpdate>.broadcast();

  VoidCallback? _resultListener;

  PiPoseModel({required this.ip, this.port = 8765});

  // 🚀 樹莓派新增:讓 UI 層(training_screen.dart)拿到底層 PiHandSource,
  // 用來顯示 latestJpeg 畫面。只在外接來源模式下會被用到。
  PiHandSource? get debugSource => _source;

  @override
  Future<void> start(PoseModelConfig config) async {
    _source = PiHandSource(service: _svc, ip: ip, port: port);

    void listener() {
      final result = _source!.handResult.value;
      _frameCtrl.add(PoseFrame(
        handLandmarks: result.landmarks,
        handDetected: result.handDetected,
        imageBytes: _source!.latestJpeg.value, // 🚀 新增
      ));
    }

    _resultListener = listener;
    _source!.handResult.addListener(listener);

    await _source!.start();
  }

  @override
  Future<void> stop() async {
    if (_resultListener != null) {
      _source?.handResult.removeListener(_resultListener!);
      _resultListener = null;
    }
    await _source?.stop();
  }

  @override
  Future<void> flipCamera() async {
    // 樹莓派固定架設,沒有翻轉鏡頭的概念,忽略即可
  }

  @override
  Stream<PoseFrame> get frameStream => _frameCtrl.stream;

  @override
  Stream<TrainingUpdate> get trainingStream => _trainingCtrl.stream;

  @override
  void dispose() {
    if (_resultListener != null) {
      _source?.handResult.removeListener(_resultListener!);
      _resultListener = null;
    }
    _source?.dispose();
    _svc.dispose();
    _frameCtrl.close();
    _trainingCtrl.close();
  }
}

typedef VoidCallback = void Function();
