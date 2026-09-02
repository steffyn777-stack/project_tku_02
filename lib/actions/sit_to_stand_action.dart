// lib/actions/sit_to_stand_action.dart
//
// 坐站訓練(SitToStand) — 下肢復健,第一個用到膝蓋/腳踝的動作
//
// 三個難度:
//   easy   膝角 ≤ 140°(微蹲)
//   medium 膝角 ≤ 115°(半蹲,較原本 100° 放寬)
//   hard   膝角 ≤ 95° + 撐住 3 秒(較原本更嚴格)
//
// 🩺 2026-08-21 治療師回饋:
//   原本 medium/hard 目標角度相同(都 100°),沒有差異,只靠撐住秒數分級。
//   改成三階都各自不同角度,並且膝內夾(代償)容忍度也依難度分級。

import 'dart:math' as math;
import 'package:flutter/painting.dart';
import '../models/body_frame.dart';
import 'body_rehab_action.dart';
//import 'wipe_body_action.dart' show RehabDifficulty;

enum _SquatState { standing, squattingDown, holding, standingUp }

class SitToStandAction implements BodyRehabAction, LevelUpControllable {
  RehabDifficulty difficulty;
  int _successCount = 0;
  int _targetCount = 8;

  _SquatState _state = _SquatState.standing;
  DateTime _lastSpeakTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _holdStartTime = DateTime.now();

  bool _pendingLevelUp = false;

  SitToStandAction({
    this.difficulty = RehabDifficulty.easy,
    int targetCount = 8,
  }) : _targetCount = targetCount;

  // ── BodyRehabAction 合約 ────────────────────────────

  @override
  String get title => '坐站訓練';

  @override
  String get initialHint => '請站在鏡頭前,雙腳與肩同寬';

  @override
  String get difficultyLabel => switch (difficulty) {
        RehabDifficulty.easy => '初級',
        RehabDifficulty.medium => '中級',
        RehabDifficulty.hard => '高級',
      };

  // 🩺 依難度分級的目標蹲角(初階最淺,高階最深)
  double get _targetSquatAngle => switch (difficulty) {
        RehabDifficulty.easy => 140.0,
        RehabDifficulty.medium => 115.0,
        RehabDifficulty.hard => 95.0,
      };

  // 🩺 膝內夾(代償)容忍度:初階寬鬆,高階嚴格
  double get _kneeValgusRatio => switch (difficulty) {
        RehabDifficulty.easy => 0.6,
        RehabDifficulty.medium => 0.7,
        RehabDifficulty.hard => 0.8,
      };

  @override
  RehabFeedback update(BodyFrame frame) {
    if (_pendingLevelUp) return RehabFeedback.none;
    // 1. 取下肢關節
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

    // 2. 防代償:膝蓋內夾(Knee Valgus)
    final kneeDistance = (lKnee.dx - rKnee.dx).abs();
    final ankleDistance = (lAnkle.dx - rAnkle.dx).abs();
    if (kneeDistance < ankleDistance * _kneeValgusRatio) {
      return RehabFeedback(prompt: _throttled('注意,膝蓋不要往內夾,請打開與肩同寬'));
    }

    // 3. 計算膝蓋平均角度
    final leftKneeAngle = _angle(lHip, lKnee, lAnkle);
    final rightKneeAngle = _angle(rHip, rKnee, rAnkle);
    final kneeAngle = (leftKneeAngle + rightKneeAngle) / 2;

    // 4. 難度參數
    const standingThreshold = 160.0;
    final targetSquatAngle = _targetSquatAngle;

    // 5. 狀態機
    final now = DateTime.now();

    switch (_state) {
      case _SquatState.standing:
        if (kneeAngle < 160.0) {
          _state = _SquatState.squattingDown;
          return RehabFeedback(prompt: _throttled('重心放在腳跟,慢慢坐下'));
        }
        break;

      case _SquatState.squattingDown:
        if (kneeAngle <= targetSquatAngle) {
          if (difficulty == RehabDifficulty.hard) {
            _state = _SquatState.holding;
            _holdStartTime = now;
            return RehabFeedback(prompt: _throttled('撐住,停在這邊三秒'));
          } else {
            _state = _SquatState.standingUp;
            return RehabFeedback(prompt: _throttled('很好,請用力站起來'));
          }
        }
        break;

      case _SquatState.holding:
        if (kneeAngle > targetSquatAngle + 10.0) {
          _state = _SquatState.squattingDown;
          return RehabFeedback(prompt: _throttled('太早站起來了,請再蹲下去撐住'));
        } else if (now.difference(_holdStartTime).inSeconds >= 3) {
          _state = _SquatState.standingUp;
          return RehabFeedback(prompt: _throttled('非常棒,現在請用力站直'));
        }
        break;

      case _SquatState.standingUp:
        if (kneeAngle >= standingThreshold) {
          _successCount++;
          _state = _SquatState.standing;

          // 達標 → 升級或結束(跟前三個動作一致)
          if (_successCount >= _targetCount) {
            _pendingLevelUp = true; // 🆕
            return const RehabFeedback(
              scored: true,
              leveledUp: true,
              prompt: '腿部表現很棒!',
            );
          }
          return RehabFeedback(
            scored: true,
            prompt: '完成一次,稍微休息再做下一回',
          );
        }
        break;
    }

    return const RehabFeedback();
  }

  // ── 私有 ────────────────────────────────────────────

  // 餘弦定理算三點夾角
  double _angle(Offset p1, Offset p2, Offset p3) {
    final a = math.sqrt(math.pow(p2.dx - p3.dx, 2) + math.pow(p2.dy - p3.dy, 2));
    final b = math.sqrt(math.pow(p1.dx - p3.dx, 2) + math.pow(p1.dy - p3.dy, 2));
    final c = math.sqrt(math.pow(p1.dx - p2.dx, 2) + math.pow(p1.dy - p2.dy, 2));
    if (a * c == 0) return 0.0;
    final cosB = (math.pow(a, 2) + math.pow(c, 2) - math.pow(b, 2)) / (2 * a * c);
    return math.acos(cosB.clamp(-1.0, 1.0)) * (180 / math.pi);
  }

  // 提示文字節流:2.5 秒內同種提示不重複,避免吵
  String? _throttled(String text) {
    final now = DateTime.now();
    if (now.difference(_lastSpeakTime).inMilliseconds > 2500) {
      _lastSpeakTime = now;
      return text;
    }
    return null;
  }

  // 升級:回傳是否真的升了(已到頂就不升)
  bool _upgrade() {
    _successCount = 0;
    _state = _SquatState.standing;
    if (difficulty == RehabDifficulty.easy) {
      difficulty = RehabDifficulty.medium;
      return true;
    } else if (difficulty == RehabDifficulty.medium) {
      difficulty = RehabDifficulty.hard;
      return true;
    }
    return false; // 已是 hard,不升
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
    _state = _SquatState.standing;
  }
}