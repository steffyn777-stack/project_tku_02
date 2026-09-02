// lib/services/pose_model_interface.dart
// ══════════════════════════════════════════════════════════════════
//  模型抽象層
//  - 定義所有模型必須實作的介面
//  - 換模型（MediaPipe → RTMPose 等）只需換實作，不動邏輯或主控
// ══════════════════════════════════════════════════════════════════

import 'dart:typed_data'; // 🚀 新增：為了使用 Uint8List
import 'package:flutter/material.dart'; // 🚀 新增：為了使用 Offset
import 'mediapipe_service.dart';

// 🚀 新增：全系統統一的復健關關節名稱 (寫在介面層，當作標準規格)
enum RehabJoint {
  leftShoulder,
  rightShoulder,
  leftElbow,
  rightElbow,
  leftWrist,
  rightWrist,
  leftHip,
  rightHip,
}

// ── 通用骨架資料（與模型無關）────────────────────────────────────────
class PoseFrame {
  final List<Landmark> handLandmarks;
  final List<Landmark> bodyLandmarks;
  final bool handDetected;
  final Uint8List? imageBytes; // 🚀 新增：原始影像 JPEG bytes

  // 🚀 新增：標準化關節座標映射表！
  // 復健邏輯以後「只讀這個 Map」，徹底與模型的 index (5, 6, 7) 解耦！
  final Map<RehabJoint, Offset> standardJoints;

  const PoseFrame({
    this.handLandmarks = const [],
    this.bodyLandmarks = const [],
    this.handDetected = false,
    this.imageBytes, // 🚀 新增
    this.standardJoints = const {}, // 🚀 預設為空
  });

  factory PoseFrame.empty() => const PoseFrame();
}

// ── 模型設定（啟動時傳入）────────────────────────────────────────────
class PoseModelConfig {
  final String actionType;
  final int difficulty;
  final bool useFrontCamera;

  const PoseModelConfig({
    required this.actionType,
    required this.difficulty,
    this.useFrontCamera = false,
  });
}

// ── 模型介面（所有推論後端都必須實作這個）───────────────────────────
abstract class IPoseModel {
  Future<void> start(PoseModelConfig config);
  Future<void> stop();
  Future<void> flipCamera();
  Stream<PoseFrame> get frameStream;
  Stream<TrainingUpdate> get trainingStream;
  void dispose();
}
