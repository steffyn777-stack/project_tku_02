// lib/services/mediapipe_model.dart
//
// ══════════════════════════════════════════════════════════════════
//  IPoseModel 的 MediaPipe 實作
//  改動：加入線性預測補幀，減少手部骨架視覺延遲
//  全身骨架（BodyPoseService）完全不受影響
// ══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert'; // 🚀 新增：解碼 Base64
import 'dart:typed_data'; // 🚀 新增：Uint8List
import 'mediapipe_service.dart';
import 'pose_model_interface.dart';

class MediaPipeModel implements IPoseModel {
  final MediaPipeService _svc = MediaPipeService();
  final StreamController<PoseFrame> _frameCtrl =
      StreamController<PoseFrame>.broadcast();

  StreamSubscription? _landmarkSub;

  // ── 預測補幀用的前一幀資料 ────────────────────────────────────────
  List<Landmark> _prevLandmarks = [];

  // ── IPoseModel ───────────────────────────────────────────────────

  @override
  Future<void> start(PoseModelConfig config) async {
    await _svc.startDetection(
      actionType: config.actionType,
      difficulty: config.difficulty,
      useFrontCamera: config.useFrontCamera,
    );

    _landmarkSub = _svc.landmarkStream.listen((result) {
      final predicted = _predictNext(result.landmarks);

      // 🚀 新增：影像資料轉成 bytes
      Uint8List? imgBytes;
      if (result.imageBase64 != null) {
        try {
          imgBytes = base64Decode(result.imageBase64!);
        } catch (_) {}
      }

      _frameCtrl.add(PoseFrame(
        handLandmarks: predicted,
        handDetected: result.handDetected,
        imageBytes: imgBytes, // 🚀 新增
      ));
    });
  }

  @override
  Future<void> stop() async {
    await _svc.stopDetection();
    _landmarkSub?.cancel();
    _prevLandmarks = [];
  }

  @override
  Future<void> flipCamera() async {
    _prevLandmarks = []; // 切換鏡頭時清除，避免預測方向錯誤
    await _svc.flipCamera();
  }

  @override
  Stream<PoseFrame> get frameStream => _frameCtrl.stream;

  @override
  Stream<TrainingUpdate> get trainingStream => _svc.trainingStream;

  @override
  void dispose() {
    _landmarkSub?.cancel();
    _frameCtrl.close();
    _svc.dispose();
  }

  // ── 線性預測補幀 ──────────────────────────────────────────────────
  // 原理：用當前幀與前一幀的位移，往前多推 0.4 幀
  // 效果：視覺上骨架比實際快半拍，抵消 channel 傳輸延遲
  // 重要：_prevLandmarks 存原始值不存預測值，避免誤差累積
  //       processLandmarks 邏輯判斷收到的仍是原始值，不受影響
  List<Landmark> _predictNext(List<Landmark> curr) {
    if (curr.isEmpty) {
      _prevLandmarks = [];
      return curr;
    }

    if (_prevLandmarks.isEmpty || _prevLandmarks.length != curr.length) {
      _prevLandmarks = curr;
      return curr;
    }

    const predictFactor = 0.4; // 往前預測的幀數比例，可調整 0.2~0.6
    final predicted = List.generate(curr.length, (i) {
      final dx = curr[i].x - _prevLandmarks[i].x;
      final dy = curr[i].y - _prevLandmarks[i].y;
      return Landmark(
        (curr[i].x + dx * predictFactor).clamp(0.0, 1.0),
        (curr[i].y + dy * predictFactor).clamp(0.0, 1.0),
        curr[i].z,
      );
    });

    _prevLandmarks = curr; // 存原始值
    return predicted;
  }
}
