// lib/models/body_frame.dart
//
// ══════════════════════════════════════════════════════════════════
//  全身復健專用的資料契約
//  - 全身偵測 (RTMPose) 與全身復健邏輯 (WipeBodyAction 等) 之間的橋樑
//  - 不依賴任何模型、不碰 mediapipe,完全獨立
// ══════════════════════════════════════════════════════════════════
//
// 🩺 2026-08-20 新增:大拇指指尖、腳掌關鍵點
//   來源依據 pose_to_bone_mapper.dart 裡的 RTMPose 133 點索引推算:
//   - 左手 21 點基準 index = 91,右手 = 112(COCO-WholeBody 標準排列)
//   - 大拇指指尖 = 手部基準 + 4(MediaPipe 手部 landmark 順序)
//   - 腳掌細節落在 17~22,實際對應順序需與底層模型輸出再次確認
//   這些新關節目前僅在 enum 中定義,實際座標填值需要在
//   PoseData → BodyFrame 的轉換層(rehab_session_controller 或
//   對應 service)一併補上,補上前這些欄位會是 null,
//   使用端(action)已做防呆,拿不到就略過該項判定。

import 'dart:ui';

// 全身復健統一關節命名 (與底層模型 index 無關)
enum RehabJoint {
  leftShoulder,
  rightShoulder,
  leftElbow,
  rightElbow,
  leftWrist,
  rightWrist,
  leftHip,
  rightHip,

  // 下肢(給坐站訓練等下肢動作用)
  leftKnee,
  rightKnee,
  leftAnkle,
  rightAnkle,

  // 🆕 手部方向(給舉手、畫圓等動作判斷大拇指朝向用)
  leftThumbTip,
  rightThumbTip,

  // 🆕 腳掌方向(給抬腳動作判斷腳掌是否平舉用)
  leftBigToe,
  rightBigToe,
  leftHeel,
  rightHeel,
}

// 一幀全身姿勢結果 — 全身復健邏輯只讀這個
class BodyFrame {
  // 標準化關節座標 (正規化 0~1)
  final Map<RehabJoint, Offset> joints;

  const BodyFrame({this.joints = const {}});

  factory BodyFrame.empty() => const BodyFrame();
}