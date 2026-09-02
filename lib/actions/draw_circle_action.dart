// lib/actions/draw_circle_action.dart
//
// 畫圓訓練 — 判定邏輯。implements BodyRehabAction,可直接丟進 body_training_screen。
//
// 🩺 2026-08-20 治療師回饋:
//   手在上半圓(高於肩膀)時,大拇指應朝上;下半圓自然下垂即可,不檢查。
//   新增 leftThumbTip/rightThumbTip 座標時才會啟用此檢查(防呆處理)。
//
// 🩺 2026-08-21 治療師回饋:
//   手臂伸直半徑要求原本中階與高階相同(0.35),沒有差異。
//   改成三階分級:初階最寬鬆,高階最嚴格。

import 'dart:math' as math;
import '../models/body_frame.dart';
import 'body_rehab_action.dart';
//import 'wipe_body_action.dart' show RehabDifficulty; // 共用同一個難度 enum

class DrawCircleAction implements BodyRehabAction, LevelUpControllable {
  RehabDifficulty difficulty;
  int successCount = 0;
  int targetCount;   // 拿掉 final

  double _sweptAngle = 0.0;
  double _lastAngle = double.nan;

  bool _pendingLevelUp = false; // 🆕

  RehabJoint? _activeWrist;
  RehabJoint? _activeShoulder;
  RehabJoint? _activeThumb; // 🆕

  DateTime _lastVoiceTime = DateTime.now();

  DrawCircleAction({
    this.difficulty = RehabDifficulty.easy,
    this.targetCount = 3,   // 用原本的預設值
  });

  // ── 合約要求 ──────────────────────────────────────────────
  @override
  String get title => '畫圓訓練';

  @override
  String get initialHint => '舉起一隻手,準備畫大圓,上半圓時大拇指朝上';

  @override
  String get difficultyLabel {
    switch (difficulty) {
      case RehabDifficulty.easy:
        return '初級';
      case RehabDifficulty.medium:
        return '中級';
      case RehabDifficulty.hard:
        return '高級';
    }
  }

  // 🩺 依難度分級的手臂伸直半徑要求(正規化座標)
  double get _requiredRadius => switch (difficulty) {
        RehabDifficulty.easy => 0.22,
        RehabDifficulty.medium => 0.30,
        RehabDifficulty.hard => 0.38,
      };

  // ── 合約核心:每幀判定 ────────────────────────────────────
  @override
  RehabFeedback update(BodyFrame frame) {
    if (_pendingLevelUp) return RehabFeedback.none; // 🆕 等待確認期間,暫停判定

    final leftShoulder = frame.joints[RehabJoint.leftShoulder];
    final rightShoulder = frame.joints[RehabJoint.rightShoulder];
    final leftWrist = frame.joints[RehabJoint.leftWrist];
    final rightWrist = frame.joints[RehabJoint.rightWrist];

    if (leftShoulder == null ||
        rightShoulder == null ||
        leftWrist == null ||
        rightWrist == null) {
      return RehabFeedback.none;
    }

    // 1. 自動偵測活躍手
    if (_activeWrist == null) {
      if (leftWrist.dy < leftShoulder.dy) {
        _activeWrist = RehabJoint.leftWrist;
        _activeShoulder = RehabJoint.leftShoulder;
        _activeThumb = RehabJoint.leftThumbTip; // 🆕
        return RehabFeedback(prompt: _speakThrottled('已鎖定左手,請開始畫大圓'));
      } else if (rightWrist.dy < rightShoulder.dy) {
        _activeWrist = RehabJoint.rightWrist;
        _activeShoulder = RehabJoint.rightShoulder;
        _activeThumb = RehabJoint.rightThumbTip; // 🆕
        return RehabFeedback(prompt: _speakThrottled('已鎖定右手,請開始畫大圓'));
      }
      return RehabFeedback.none;
    }

    // 2. 取活躍手座標
    final shoulder = frame.joints[_activeShoulder!];
    final wrist = frame.joints[_activeWrist!];
    if (shoulder == null || wrist == null) return RehabFeedback.none;

    // 3. 計算半徑 (防代償)
    final dx = wrist.dx - shoulder.dx;
    final dy = wrist.dy - shoulder.dy;
    final radius = math.sqrt(dx * dx + dy * dy);

    if (radius < _requiredRadius) {
      _lastAngle = double.nan;
      return RehabFeedback(prompt: _speakThrottled('手臂請伸直,畫大一點的圓'));
    }

    // 🩺 3.5 大拇指朝向檢查:只在手高於肩膀(上半圓)時檢查,
    //    下半圓(自然下垂)完全不檢查。資料源沒接上就跳過。
    if (wrist.dy < shoulder.dy) {
      final thumb = frame.joints[_activeThumb!];
      if (thumb != null) {
        const thumbUpMargin = 0.02;
        final isThumbUp = thumb.dy < wrist.dy - thumbUpMargin;
        if (!isThumbUp) {
          final prompt = _speakThrottled('上半圓請保持大拇指朝上');
          if (prompt != null) return RehabFeedback(prompt: prompt);
        }
      }
    }

    // 4. 累積角度
    final currentAngle = math.atan2(dy, dx) * (180 / math.pi);

    if (!_lastAngle.isNaN) {
      double deltaAngle = currentAngle - _lastAngle;
      if (deltaAngle > 180) deltaAngle -= 360;
      if (deltaAngle < -180) deltaAngle += 360;
      _sweptAngle += deltaAngle.abs();

      // 5. 完成一圈
      if (_sweptAngle >= 360.0) {
        _sweptAngle = 0.0;
        successCount++;

        if (successCount >= targetCount) {
          _pendingLevelUp = true; // 🆕 先不升級,等使用者確認
          //_upgradeDifficulty();
          return const RehabFeedback(
            prompt: '太棒了!解鎖下一個難度!',
            scored: true,
            leveledUp: true,
          );
        }
        _lastAngle = currentAngle;
        return const RehabFeedback(
          prompt: '完成一圈!請繼續畫',
          scored: true,
        );
      }
    }
    _lastAngle = currentAngle;

    return RehabFeedback.none;
  }

  // ── 私有 ──────────────────────────────────────────────────
  String? _speakThrottled(String text) {
    final now = DateTime.now();
    if (now.difference(_lastVoiceTime).inSeconds > 2) {
      _lastVoiceTime = now;
      return text;
    }
    return null;
  }

  void _upgradeDifficulty() {
    successCount = 0;
    _sweptAngle = 0.0;
    _lastAngle = double.nan;
    if (difficulty == RehabDifficulty.easy) {
      difficulty = RehabDifficulty.medium;
    } else if (difficulty == RehabDifficulty.medium) {
      difficulty = RehabDifficulty.hard;
    }
  }

  @override
  bool get isPendingLevelUp => _pendingLevelUp; // 🆕

  @override
  void confirmLevelUp({int? customTargetReps}) { // 🆕
    _pendingLevelUp = false;
    _upgradeDifficulty();
    if (customTargetReps != null && customTargetReps > 0) {
      targetCount = customTargetReps;
    }
  }

  @override
  void declineLevelUp() { // 🆕
    _pendingLevelUp = false;
    successCount = 0;
    _sweptAngle = 0.0;
    _lastAngle = double.nan;
  }
}