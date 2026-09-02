// lib/actions/elbow_forward_action.dart
//
// 手肘屈伸訓練 — 訓練手肘關節活動度
// 雙手十指交扣,手肘從彎到直再從直到彎
//
// 改版重點:
//   1. 動作從「前伸」(2D 鏡頭判不準)改為「屈伸」(角度判定可靠)
//   2. 加入三難度梯度(130°/150°/165° + 撐 0/2/3 秒)
//   3. 取雙手較低的肘角(防作弊:不能只伸好手)
//   4. 升級門檻 5 次
//
// 🩺 2026-08-21 治療師回饋:
//   防代償容錯值(聳肩、後仰、雙手不同步、撐住掉落)原本不分難度,
//   一律用同一組偏嚴格的數字。改成依難度分三階:初階最寬鬆,高階最嚴格。

import 'dart:math' as math;
import 'package:flutter/painting.dart';
import '../models/body_frame.dart';
import 'body_rehab_action.dart';
//import 'wipe_body_action.dart' show RehabDifficulty;

enum _ElbowState { waitReady, extending, holding, retracting }

class ElbowForwardAction implements BodyRehabAction, LevelUpControllable {
  RehabDifficulty difficulty;
  int successCount = 0;
  int _targetCount = 5;

  // ── 角度門檻(肩-肘-腕)─────────────────────────────────
  static const double _retractAngle = 90.0;        // 起點:手肘彎曲
  static const double _easyTargetAngle = 130.0;    // 微伸
  static const double _mediumTargetAngle = 150.0;  // 接近全直
  static const double _hardTargetAngle = 165.0;    // 完全伸直

  _ElbowState _state = _ElbowState.waitReady;
  DateTime _lastVoiceTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastRepTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _holdStartTime = DateTime.now();
  DateTime _retractStartTime = DateTime.now();

  bool _pendingLevelUp = false; // 🆕

  ElbowForwardAction({
    this.difficulty = RehabDifficulty.easy,
    int targetCount = 5,
  }) : _targetCount = targetCount;

  // ── 合約 ──────────────────────────────────────────────
  @override
  String get title => '手肘屈伸訓練';

  @override
  String get initialHint => '雙手十指交扣放在胸前,準備伸直手肘';

  @override
  String get difficultyLabel => switch (difficulty) {
        RehabDifficulty.easy => '初級',
        RehabDifficulty.medium => '中級',
        RehabDifficulty.hard => '高級',
      };

  // 🩺 依難度分級的防代償容錯值
  double get _shoulderDiffThreshold => switch (difficulty) {
        RehabDifficulty.easy => 0.10,
        RehabDifficulty.medium => 0.07,
        RehabDifficulty.hard => 0.045,
      };

  double get _spineAngleThreshold => switch (difficulty) {
        RehabDifficulty.easy => 26.0,
        RehabDifficulty.medium => 20.0,
        RehabDifficulty.hard => 14.0,
      };

  double get _armSyncThreshold => switch (difficulty) {
        RehabDifficulty.easy => 32.0,
        RehabDifficulty.medium => 25.0,
        RehabDifficulty.hard => 16.0,
      };

  double get _dropTolerance => switch (difficulty) {
        RehabDifficulty.easy => 22.0,
        RehabDifficulty.medium => 15.0,
        RehabDifficulty.hard => 8.0,
      };

  // ── 每幀判定 ──────────────────────────────────────────
  @override
  RehabFeedback update(BodyFrame frame) {
    if (_pendingLevelUp) return RehabFeedback.none;
    final lShoulder = frame.joints[RehabJoint.leftShoulder];
    final rShoulder = frame.joints[RehabJoint.rightShoulder];
    final lElbow = frame.joints[RehabJoint.leftElbow];
    final rElbow = frame.joints[RehabJoint.rightElbow];
    final lWrist = frame.joints[RehabJoint.leftWrist];
    final rWrist = frame.joints[RehabJoint.rightWrist];
    final lHip = frame.joints[RehabJoint.leftHip];

    if (lShoulder == null || rShoulder == null ||
        lElbow == null || rElbow == null ||
        lWrist == null || rWrist == null ||
        lHip == null) {
      return RehabFeedback.none;
    }

    // 1. 防後仰
    final spineDx = lShoulder.dx - lHip.dx;
    final spineDy = lShoulder.dy - lHip.dy;
    final spineAngle = math.atan2(spineDx, spineDy) * (180 / math.pi);
    if (spineAngle < -_spineAngleThreshold) {
      return RehabFeedback(prompt: _throttled('坐直一點,不要往後靠'));
    }

    // 2. 防聳肩(整段都檢查)
    final shoulderDiff = (lShoulder.dy - rShoulder.dy).abs();
    if (shoulderDiff > _shoulderDiffThreshold) {
      return RehabFeedback(prompt: _throttled('放鬆肩膀,不要聳肩'));
    }

    // 3. 算雙手肘角度
    final leftElbowAngle = _angle(lShoulder, lElbow, lWrist);
    final rightElbowAngle = _angle(rShoulder, rElbow, rWrist);

    // 4. 雙手同步檢查
    final armDiff = (leftElbowAngle - rightElbowAngle).abs();
    if (armDiff > _armSyncThreshold && _state == _ElbowState.extending) {
      return RehabFeedback(prompt: _throttled('雙手要一起伸,患手別落後'));
    }

    // 5. 取較低的肘角當基準(防作弊)
    final activeAngle = math.min(leftElbowAngle, rightElbowAngle);

    // 6. 目標角度
    final targetAngle = switch (difficulty) {
      RehabDifficulty.easy => _easyTargetAngle,
      RehabDifficulty.medium => _mediumTargetAngle,
      RehabDifficulty.hard => _hardTargetAngle,
    };

    final holdSeconds = difficulty == RehabDifficulty.easy
        ? 0
        : difficulty == RehabDifficulty.medium
            ? 2
            : 3;

    final now = DateTime.now();

    // 7. 狀態機
    switch (_state) {
      case _ElbowState.waitReady:
        // 手肘要先回到彎曲(< 90°)才能開始
        if (activeAngle <= _retractAngle) {
          final readyMs = now.difference(_lastRepTime).inMilliseconds;
          if (readyMs > 500) {
            _state = _ElbowState.extending;
            return RehabFeedback(prompt: _throttled('預備好,雙手交扣慢慢伸直'));
          }
        }
        break;

      case _ElbowState.extending:
        if (activeAngle >= targetAngle) {
          if (holdSeconds > 0) {
            _state = _ElbowState.holding;
            _holdStartTime = now;
            return RehabFeedback(prompt: _throttled('很好,撐住 $holdSeconds 秒'));
          } else {
            _state = _ElbowState.retracting;
            _retractStartTime = now;
            return RehabFeedback(prompt: _throttled('很好,慢慢收回胸前'));
          }
        }
        break;

      case _ElbowState.holding:
        if (activeAngle < targetAngle - _dropTolerance) {
          _state = _ElbowState.extending;
          _holdStartTime = now;
          return RehabFeedback(prompt: _throttled('手肘彎回來了,再伸直'));
        }
        if (now.difference(_holdStartTime).inSeconds >= holdSeconds) {
          _state = _ElbowState.retracting;
          _retractStartTime = now;
          return RehabFeedback(prompt: _throttled('非常好,慢慢收回胸前'));
        }
        break;

      case _ElbowState.retracting:
        if (activeAngle <= _retractAngle) {
          final retractMs = now.difference(_retractStartTime).inMilliseconds;
          final repIntervalMs = now.difference(_lastRepTime).inMilliseconds;

          if (repIntervalMs > 1500) {
            // 收回太快
            if (retractMs < 600) {
              _lastRepTime = now;
              _state = _ElbowState.waitReady;
              return RehabFeedback(prompt: _throttled('收太快了,慢慢控制收回'));
            }

            successCount++;
            _lastRepTime = now;
            _state = _ElbowState.waitReady;

            if (successCount >= _targetCount) {
              _pendingLevelUp = true; // 🆕
              return const RehabFeedback(
                prompt: '完美過關!',
                scored: true,
                leveledUp: true,
              );
            }
            return const RehabFeedback(
              prompt: '完成一次,繼續',
              scored: true,
            );
          }
        }
        break;
    }

    return RehabFeedback.none;
  }

  // ── 算「肩-肘-腕」夾角(餘弦定理)──────────────────────
  double _angle(Offset p1, Offset p2, Offset p3) {
    final a = math.sqrt(math.pow(p2.dx - p3.dx, 2) + math.pow(p2.dy - p3.dy, 2));
    final b = math.sqrt(math.pow(p1.dx - p3.dx, 2) + math.pow(p1.dy - p3.dy, 2));
    final c = math.sqrt(math.pow(p1.dx - p2.dx, 2) + math.pow(p1.dy - p2.dy, 2));
    if (a * c == 0) return 0.0;
    final cosB =
        (math.pow(a, 2) + math.pow(c, 2) - math.pow(b, 2)) / (2 * a * c);
    return math.acos(cosB.clamp(-1.0, 1.0)) * (180 / math.pi);
  }

  String? _throttled(String text) {
    final now = DateTime.now();
    if (now.difference(_lastVoiceTime).inMilliseconds > 2000) {
      _lastVoiceTime = now;
      return text;
    }
    return null;
  }

  bool _upgrade() {
    successCount = 0;
    _state = _ElbowState.waitReady;
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
    successCount = 0;
    _state = _ElbowState.waitReady;
  }
}