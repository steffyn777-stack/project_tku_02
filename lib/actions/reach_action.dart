// lib/actions/reach_action.dart
//
// 伸手舉高訓練 — 判定邏輯。implements BodyRehabAction。
//
// 改版重點:
//   1. 用「髖-肩-手腕」角度判定,身高/距離無影響
//   2. 三難度梯度合理:水平 → 頭頂 → 頭頂撐 3 秒
//   3. 起點統一為「手自然下垂」(角度 ≤ 30°)
//   4. 升級門檻 5 次
//   5. 訓練前透過 UI 按鈕選擇左手或右手
//
// 🩺 2026-08-21 治療師回饋:
//   脊椎歪斜容忍度、頂點撐住掉落容忍度原本不分難度,一律用同一組數字。
//   改成三階分級:初階最寬鬆,高階最嚴格。

import 'dart:math' as math;
import 'package:flutter/painting.dart';
import '../models/body_frame.dart';
import 'body_rehab_action.dart';
//import 'wipe_body_action.dart' show RehabDifficulty;

enum _ReachState { waitStart, reachingUp, holding, pullingDown }

class ReachAction implements BodyRehabAction, LevelUpControllable {
  RehabDifficulty difficulty;
  int successCount = 0;
  int _targetCount = 5;   // 升級門檻(可自訂)

  // ── 角度門檻(髖-肩-手腕)─────────────────────────────────
  static const double _restAngle = 30.0;         // 手垂下身側(寬鬆)
  static const double _horizontalAngle = 80.0;   // 水平(easy 終點)
  static const double _topAngle = 150.0;         // 頭頂(medium/hard 終點)

  _ReachState _currentState = _ReachState.waitStart;
  RehabJoint? _activeWrist;
  RehabJoint? _activeShoulder;
  RehabJoint? _activeHip;

  DateTime _lastVoiceTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _holdStartTime = DateTime.now();
  DateTime _lastRepTime = DateTime.fromMillisecondsSinceEpoch(0);
  bool _pendingLevelUp = false;

  ReachAction({
    this.difficulty = RehabDifficulty.easy,
    int targetCount = 5,
  }) : _targetCount = targetCount;

  // ── 按鈕呼叫:選擇左手或右手 ────────────────────────────
  bool get handSelected => _activeWrist != null;

  void selectLeftHand() {
    _activeWrist    = RehabJoint.leftWrist;
    _activeShoulder = RehabJoint.leftShoulder;
    _activeHip      = RehabJoint.leftHip;
  }

  void selectRightHand() {
    _activeWrist    = RehabJoint.rightWrist;
    _activeShoulder = RehabJoint.rightShoulder;
    _activeHip      = RehabJoint.rightHip;
  }

  // ── 合約 ──────────────────────────────────────────────
  @override
  String get title => '伸手舉高訓練';

  @override
  String get initialHint => '請選擇要訓練的手';

  @override
  String get difficultyLabel => switch (difficulty) {
        RehabDifficulty.easy => '初級',
        RehabDifficulty.medium => '中級',
        RehabDifficulty.hard => '高級',
      };

  // 🩺 依難度分級的防代償容錯值
  double get _spineAngleThreshold => switch (difficulty) {
        RehabDifficulty.easy => 26.0,
        RehabDifficulty.medium => 20.0,
        RehabDifficulty.hard => 14.0,
      };

  double get _topDropTolerance => switch (difficulty) {
        RehabDifficulty.easy => 22.0,
        RehabDifficulty.medium => 17.0,
        RehabDifficulty.hard => 12.0,
      };

  // ── 每幀判定 ──────────────────────────────────────────
  @override
  RehabFeedback update(BodyFrame frame) {
    // 尚未選手 → 等待 UI 按鈕,不做任何偵測
    if (!handSelected) return RehabFeedback.none;

    if (_pendingLevelUp) return RehabFeedback.none;

    final lShoulder = frame.joints[RehabJoint.leftShoulder];
    final rShoulder = frame.joints[RehabJoint.rightShoulder];
    final lHip      = frame.joints[RehabJoint.leftHip];
    final rHip      = frame.joints[RehabJoint.rightHip];
    final shoulder  = frame.joints[_activeShoulder!];
    final wrist     = frame.joints[_activeWrist!];
    final hip       = frame.joints[_activeHip!];

    if (lShoulder == null || rShoulder == null ||
        lHip == null      || rHip == null      ||
        shoulder == null  || wrist == null     || hip == null) {
      return RehabFeedback.none;
    }

    // 1. 防後仰借力(脊椎傾斜檢查,用左肩-左髖)
    final spineDx = lShoulder.dx - lHip.dx;
    final spineDy = lShoulder.dy - lHip.dy;
    final spineAngle = math.atan2(spineDx, spineDy) * (180 / math.pi);
    if (spineAngle.abs() > _spineAngleThreshold) {
      return RehabFeedback(prompt: _throttled('身體請保持挺直,不要後仰借力'));
    }

    // 2. 算當前手臂角度
    final armAngle = _armAngle(hip, shoulder, wrist);

    // 3. 目標角度(依難度)
    final targetAngle = switch (difficulty) {
      RehabDifficulty.easy   => _horizontalAngle,  // 80° 水平
      RehabDifficulty.medium => _topAngle,          // 150° 頭頂
      RehabDifficulty.hard   => _topAngle,          // 150° 頭頂(再要求撐 3 秒)
    };

    final now = DateTime.now();

    // 4. 狀態機
    switch (_currentState) {
      case _ReachState.waitStart:
        if (armAngle <= _restAngle) {
          _currentState = _ReachState.reachingUp;
          return RehabFeedback(prompt: _throttled('預備完成,請用力往上舉'));
        }
        break;

      case _ReachState.reachingUp:
        if (armAngle >= targetAngle) {
          if (difficulty == RehabDifficulty.hard) {
            _currentState = _ReachState.holding;
            _holdStartTime = now;
            return RehabFeedback(prompt: _throttled('撐住 3 秒'));
          } else {
            _currentState = _ReachState.pullingDown;
            return RehabFeedback(prompt: _throttled('很好,請慢慢放下'));
          }
        }
        break;

      case _ReachState.holding:
        if (armAngle < targetAngle - _topDropTolerance) {
          _currentState = _ReachState.reachingUp;
          return RehabFeedback(prompt: _throttled('手掉下來了,請再次舉高並撐住'));
        }
        if (now.difference(_holdStartTime).inSeconds >= 3) {
          _currentState = _ReachState.pullingDown;
          return RehabFeedback(prompt: _throttled('非常穩定,請慢慢放下'));
        }
        break;

      case _ReachState.pullingDown:
        if (armAngle <= _restAngle) {
          final durationMs = now.difference(_lastRepTime).inMilliseconds;

          if (durationMs > 1500) {
            successCount++;
            _lastRepTime = now;
            _currentState = _ReachState.waitStart;

            if (successCount >= _targetCount) {
              _pendingLevelUp = true; // 🆕
              return const RehabFeedback(
                prompt: '完美過關!',
                scored: true,
                leveledUp: true,
              );
            }
            return const RehabFeedback(prompt: '完成一次,請繼續', scored: true);
          } else {
            _lastRepTime = now;
            _currentState = _ReachState.waitStart;
            return RehabFeedback(prompt: _throttled('放下太快了,請用肌肉控制慢慢放下'));
          }
        }
        break;
    }

    return RehabFeedback.none;
  }

  // ── 算「髖-肩-手腕」夾角 ─────────────────────────────────
  double _armAngle(Offset hip, Offset shoulder, Offset wrist) {
    final ax = hip.dx - shoulder.dx;
    final ay = hip.dy - shoulder.dy;
    final bx = wrist.dx - shoulder.dx;
    final by = wrist.dy - shoulder.dy;

    final magA = math.sqrt(ax * ax + ay * ay);
    final magB = math.sqrt(bx * bx + by * by);
    if (magA == 0 || magB == 0) return 0.0;

    final cosTheta = (ax * bx + ay * by) / (magA * magB);
    return math.acos(cosTheta.clamp(-1.0, 1.0)) * (180 / math.pi);
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
    _currentState = _ReachState.waitStart;
    _activeWrist = null;
    _activeShoulder = null;
    _activeHip = null;
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
    _currentState = _ReachState.waitStart;
  }
}