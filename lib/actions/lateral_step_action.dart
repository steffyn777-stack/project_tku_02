// lib/actions/lateral_step_action.dart
//
// 側跨步訓練(LateralStep) — 下肢平衡 + 單側肌力
//
// 三個難度(膝彎深度):
//   easy   ≤ 140°(微跨)
//   medium ≤ 110°(半蹲側弓步)
//   hard   ≤ 90° + 撐住 2 秒(深側弓步)
//
// 重點防代償:留在原地的腳要伸直,不能跟著彎
//
// 🩺 2026-08-21 治療師回饋:
//   支撐腳(留在原地那隻)容錯值原本不分難度,一律 145°。
//   改成三階分級:初階更寬鬆(容許支撐腳稍微彎),高階更嚴格(要求完全打直)。

import 'dart:math' as math;
import 'package:flutter/painting.dart';
import '../models/body_frame.dart';
import 'body_rehab_action.dart';
//import 'wipe_body_action.dart' show RehabDifficulty;

enum _StepState { standing, steppingOut, holding, returning }

class LateralStepAction implements BodyRehabAction, LevelUpControllable {
  RehabDifficulty difficulty;
  int _successCount = 0;
  int _targetCount = 8;

  _StepState _state = _StepState.standing;
  String? _activeSide; // 'LEFT' / 'RIGHT' / null
  DateTime _lastSpeakTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _holdStartTime = DateTime.now();
  bool _pendingLevelUp = false;

  LateralStepAction({
    this.difficulty = RehabDifficulty.easy,
    int targetCount = 8,
  }) : _targetCount = targetCount;

  // ── BodyRehabAction 合約 ────────────────────────────

  @override
  String get title => '側跨步訓練';

  @override
  String get initialHint => '請扶穩支撐物,雙腳與肩同寬站立';

  @override
  String get difficultyLabel => switch (difficulty) {
        RehabDifficulty.easy => '初級',
        RehabDifficulty.medium => '中級',
        RehabDifficulty.hard => '高級',
      };

  // 🩺 支撐腳(留在原地那隻)防代償容忍度:初階寬鬆,高階嚴格
  double get _inactiveLegTolerance => switch (difficulty) {
        RehabDifficulty.easy => 138.0,
        RehabDifficulty.medium => 145.0,
        RehabDifficulty.hard => 152.0,
      };

  @override
  RehabFeedback update(BodyFrame frame) {
    if (_pendingLevelUp) return RehabFeedback.none;
    // 取下肢關節
    final lHip = frame.joints[RehabJoint.leftHip];
    final lKnee = frame.joints[RehabJoint.leftKnee];
    final lAnkle = frame.joints[RehabJoint.leftAnkle];
    final rHip = frame.joints[RehabJoint.rightHip];
    final rKnee = frame.joints[RehabJoint.rightKnee];
    final rAnkle = frame.joints[RehabJoint.rightAnkle];

    if (lHip == null || lKnee == null || lAnkle == null ||
        rHip == null || rKnee == null || rAnkle == null) {
      return const RehabFeedback();
    }

    final leftKneeAngle = _angle(lHip, lKnee, lAnkle);
    final rightKneeAngle = _angle(rHip, rKnee, rAnkle);

    const standingThreshold = 160.0;
    final targetBendAngle = switch (difficulty) {
      RehabDifficulty.easy => 140.0,
      RehabDifficulty.medium => 110.0,
      RehabDifficulty.hard => 90.0,
    };

    final now = DateTime.now();

    switch (_state) {
      case _StepState.standing:
        // 偵測哪隻腳開始彎曲 = 跨出腳
        if (leftKneeAngle < 150.0 && rightKneeAngle > standingThreshold) {
          _activeSide = 'LEFT';
          _state = _StepState.steppingOut;
          return RehabFeedback(prompt: _throttled('左腳跨出,重心慢慢轉移'));
        } else if (rightKneeAngle < 150.0 && leftKneeAngle > standingThreshold) {
          _activeSide = 'RIGHT';
          _state = _StepState.steppingOut;
          return RehabFeedback(prompt: _throttled('右腳跨出,重心慢慢轉移'));
        }
        break;

      case _StepState.steppingOut:
        final activeAngle =
            _activeSide == 'LEFT' ? leftKneeAngle : rightKneeAngle;
        final inactiveAngle =
            _activeSide == 'LEFT' ? rightKneeAngle : leftKneeAngle;

        // 防代償:留在原地的腳不能彎(容忍度依難度分級)
        if (inactiveAngle < _inactiveLegTolerance) {
          return RehabFeedback(
              prompt: _throttled('留在原地的腳請保持伸直,不要跟著彎'));
        }

        if (activeAngle <= targetBendAngle) {
          if (difficulty == RehabDifficulty.hard) {
            _state = _StepState.holding;
            _holdStartTime = now;
            return RehabFeedback(prompt: _throttled('很好,停在這個深度撐住兩秒'));
          } else {
            _state = _StepState.returning;
            return RehabFeedback(prompt: _throttled('深度足夠,請用力推回站姿'));
          }
        }
        break;

      case _StepState.holding:
        final activeAngle =
            _activeSide == 'LEFT' ? leftKneeAngle : rightKneeAngle;

        if (activeAngle > targetBendAngle + 15.0) {
          _state = _StepState.steppingOut;
          return RehabFeedback(prompt: _throttled('太早站起來了,請再蹲深一點'));
        }
        if (now.difference(_holdStartTime).inSeconds >= 2) {
          _state = _StepState.returning;
          return RehabFeedback(prompt: _throttled('完美,現在請用力推回站立'));
        }
        break;

      case _StepState.returning:
        // 兩腳都回站直 = 完成一次
        if (leftKneeAngle >= standingThreshold &&
            rightKneeAngle >= standingThreshold) {
          _successCount++;
          _state = _StepState.standing;
          _activeSide = null;

          if (_successCount >= _targetCount) {
            _pendingLevelUp = true; // 🆕
            return const RehabFeedback(
              scored: true,
              leveledUp: true,
              prompt: '下肢控制很棒!',
            );
          }
          return RehabFeedback(
            scored: true,
            prompt: '完成一次,請換腳或繼續跨步',
          );
        }
        break;
    }

    return const RehabFeedback();
  }

  // ── 私有 ────────────────────────────────────────────

  double _angle(Offset p1, Offset p2, Offset p3) {
    final a = math.sqrt(math.pow(p2.dx - p3.dx, 2) + math.pow(p2.dy - p3.dy, 2));
    final b = math.sqrt(math.pow(p1.dx - p3.dx, 2) + math.pow(p1.dy - p3.dy, 2));
    final c = math.sqrt(math.pow(p1.dx - p2.dx, 2) + math.pow(p1.dy - p2.dy, 2));
    if (a * c == 0) return 0.0;
    final cosB = (math.pow(a, 2) + math.pow(c, 2) - math.pow(b, 2)) / (2 * a * c);
    return math.acos(cosB.clamp(-1.0, 1.0)) * (180 / math.pi);
  }

  String? _throttled(String text) {
    final now = DateTime.now();
    if (now.difference(_lastSpeakTime).inMilliseconds > 2500) {
      _lastSpeakTime = now;
      return text;
    }
    return null;
  }

  bool _upgrade() {
    _successCount = 0;
    _state = _StepState.standing;
    _activeSide = null;
    if (difficulty == RehabDifficulty.easy) {
      difficulty = RehabDifficulty.medium;
      return true;
    } else if (difficulty == RehabDifficulty.medium) {
      difficulty = RehabDifficulty.hard;
      return true;
    }
    return false;
  }

  @override
  bool get isPendingLevelUp => _pendingLevelUp; // 🆕

  @override
  void confirmLevelUp({int? customTargetReps}) { // 🆕
    _pendingLevelUp = false;
    _upgrade();
    if (customTargetReps != null && customTargetReps > 0) {
      _targetCount = customTargetReps;
    }
  }

  @override
  void declineLevelUp() { // 🆕
    _pendingLevelUp = false;
    _successCount = 0;
    _state = _StepState.standing;
    _activeSide = null;
  }
}