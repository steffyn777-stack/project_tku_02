// lib/actions/raise_both_arms_action.dart
//
// 雙手抬舉式 — 中風復健「跟著做」第 3 式
// 好手交扣患手,雙手一起往上抬舉
//
// 改版重點:
//   1. 加入三難度梯度(原版只有「標準」)
//   2. 用「髖-肩-手腕」角度判定,身高/距離無關
//   3. 防代償整段流程都檢查(聳肩、後仰、左右不同步)
//   4. 升級門檻 5 次(原版 10 次太多)
//
// 🛠️ Bug 修正(2026-08-16):
//   spineAngle 計算原本用 atan2(spineDx, spineDy),
//   但畫面座標系 y 軸是「往下遞增」,肩膀在髖部正上方(坐正)時
//   spineDy 為負值,導致算出來的角度落在 ±180 度附近,而不是 0 度。
//   原本的 spineAngle.abs() > 20 判斷因此「坐正時也恆成立」,
//   使用者不管姿勢多標準都會一直卡在「請坐正,不要後仰借力」。
//   修正方式:atan2 的第二個參數取負號(-spineDy),
//   讓「坐正」正確對應到 spineAngle ≈ 0 度。
//
// 🩺 2026-08-20 治療師回饋(1):
//   舉到最高點時大拇指應該朝上,若朝後代表肩膀內轉代償。
//   新增 leftThumbTip/rightThumbTip 座標時才會啟用此檢查(防呆:
//   資料源尚未接上大拇指關鍵點前,這段直接跳過,不影響原本判定)。
//
// 🩺 2026-08-21 治療師回饋(2):
//   所有防代償容錯值(聳肩、後仰、雙手不同步、撐住掉落)原本不分難度,
//   一律用同一組偏嚴格的數字,導致初階也常被判定代償。
//   改成依難度分三階:初階最寬鬆,中階持平原本設定,高階最嚴格。

import 'dart:math' as math;
import 'package:flutter/painting.dart';
import '../models/body_frame.dart';
import 'body_rehab_action.dart';
//import 'wipe_body_action.dart' show RehabDifficulty;

enum _RaiseState { waitReady, raising, holding, lowering }

class RaiseBothArmsAction implements BodyRehabAction, LevelUpControllable {
  RehabDifficulty difficulty;
  int successCount = 0;
  int _targetCount = 5;

  // ── 角度門檻(髖-肩-手腕)─────────────────────────────────
  static const double _restAngle = 30.0;           // 雙手垂放
  static const double _easyTargetAngle = 90.0;     // 水平
  static const double _mediumTargetAngle = 130.0;  // 接近頭頂
  static const double _hardTargetAngle = 150.0;    // 過頭頂

  _RaiseState _state = _RaiseState.waitReady;
  DateTime _lastVoiceTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastRepTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _holdStartTime = DateTime.now();
  DateTime _lowerStartTime = DateTime.now();
  bool _pendingLevelUp = false;

  RaiseBothArmsAction({
    this.difficulty = RehabDifficulty.easy,
    int targetCount = 5,
  }) : _targetCount = targetCount;

  // ── 合約 ──────────────────────────────────────────────
  @override
  String get title => '雙手抬舉式';

  @override
  String get initialHint => '雙手交扣,自然垂放,準備往上抬舉,舉到最高時記得大拇指朝上';

  @override
  String get difficultyLabel => switch (difficulty) {
        RehabDifficulty.easy => '初級',
        RehabDifficulty.medium => '中級',
        RehabDifficulty.hard => '高級',
      };

  // 🩺 依難度分級的防代償容錯值(初階最寬鬆,高階最嚴格)
  double get _shoulderDiffThreshold => switch (difficulty) {
        RehabDifficulty.easy => 0.10,
        RehabDifficulty.medium => 0.07,
        RehabDifficulty.hard => 0.045,
      };

  double get _armSyncThreshold => switch (difficulty) {
        RehabDifficulty.easy => 28.0,
        RehabDifficulty.medium => 20.0,
        RehabDifficulty.hard => 12.0,
      };

  double get _spineAngleThreshold => switch (difficulty) {
        RehabDifficulty.easy => 26.0,
        RehabDifficulty.medium => 20.0,
        RehabDifficulty.hard => 14.0,
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
    final lWrist = frame.joints[RehabJoint.leftWrist];
    final rWrist = frame.joints[RehabJoint.rightWrist];
    final lHip = frame.joints[RehabJoint.leftHip];
    final rHip = frame.joints[RehabJoint.rightHip];

    if (lShoulder == null || rShoulder == null ||
        lWrist == null || rWrist == null ||
        lHip == null || rHip == null) {
      return RehabFeedback.none;
    }

    // 1. 防後仰借力
    final spineDx = lShoulder.dx - lHip.dx;
    final spineDy = lShoulder.dy - lHip.dy;
    // 🛠️ 修正:第二個參數取負號,讓「坐正」對應 spineAngle ≈ 0 度
    final spineAngle = math.atan2(spineDx, -spineDy) * (180 / math.pi);
    if (spineAngle.abs() > _spineAngleThreshold) {
      return RehabFeedback(prompt: _throttled('請坐正,不要後仰借力'));
    }

    // 2. 防聳肩(整段都檢查,不只 raising)
    final shoulderDiff = (lShoulder.dy - rShoulder.dy).abs();
    if (shoulderDiff > _shoulderDiffThreshold) {
      return RehabFeedback(prompt: _throttled('放鬆肩膀,不要聳肩'));
    }

    // 3. 算雙手角度
    final leftAngle = _armAngle(lHip, lShoulder, lWrist);
    final rightAngle = _armAngle(rHip, rShoulder, rWrist);

    // 4. 雙手同步檢查(差太多 = 患手沒被帶上)
    final armDiff = (leftAngle - rightAngle).abs();
    if (armDiff > _armSyncThreshold && _state == _RaiseState.raising) {
      return RehabFeedback(prompt: _throttled('雙手要一起抬,患手別落後'));
    }

    // 5. 取「較低的那隻手」當判定基準(防作弊:不能只舉好手)
    final activeAngle = math.min(leftAngle, rightAngle);

    // 6. 目標角度(依難度)
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

    // 🩺 6.5 大拇指朝向檢查(只在撐住/接近頂點時檢查,且資料源有給值才檢查)
    //    有大拇指座標時才啟用,尚未接上前 thumb 為 null 就直接跳過。
    if (activeAngle >= targetAngle - _dropTolerance) {
      final thumbPrompt = _checkThumbUp(frame, leftAngle, rightAngle);
      if (thumbPrompt != null) {
        return RehabFeedback(prompt: thumbPrompt);
      }
    }

    // 7. 狀態機
    switch (_state) {
      case _RaiseState.waitReady:
        if (activeAngle <= _restAngle) {
          _state = _RaiseState.raising;
          return RehabFeedback(prompt: _throttled('預備好了,雙手交扣往上抬'));
        }
        break;

      case _RaiseState.raising:
        if (activeAngle >= targetAngle) {
          if (holdSeconds > 0) {
            _state = _RaiseState.holding;
            _holdStartTime = now;
            return RehabFeedback(prompt: _throttled('很好,撐住 $holdSeconds 秒'));
          } else {
            _state = _RaiseState.lowering;
            _lowerStartTime = now;
            return RehabFeedback(prompt: _throttled('很好,慢慢放下'));
          }
        }
        break;

      case _RaiseState.holding:
        if (activeAngle < targetAngle - _dropTolerance) {
          _state = _RaiseState.raising;
          _holdStartTime = now;
          return RehabFeedback(prompt: _throttled('手掉下來了,再往上抬'));
        }
        if (now.difference(_holdStartTime).inSeconds >= holdSeconds) {
          _state = _RaiseState.lowering;
          _lowerStartTime = now;
          return RehabFeedback(prompt: _throttled('非常好,慢慢放下'));
        }
        break;

      case _RaiseState.lowering:
        if (activeAngle <= _restAngle) {
          final lowerMs = now.difference(_lowerStartTime).inMilliseconds;
          final repIntervalMs = now.difference(_lastRepTime).inMilliseconds;

          if (repIntervalMs > 1500) {
            // 放下太快 = 不算
            if (lowerMs < 800) {
              _lastRepTime = now;
              _state = _RaiseState.waitReady;
              return RehabFeedback(prompt: _throttled('放太快了,用肌肉控制慢慢放下'));
            }

            successCount++;
            _lastRepTime = now;
            _state = _RaiseState.waitReady;

            if (successCount >= _targetCount) {
              _pendingLevelUp = true; // 🆕
              return const RehabFeedback(
                prompt: '完美過關!',
                scored: true,
                leveledUp: true,
              );
            }
            return const RehabFeedback(
              prompt: '完成一次,繼續往上抬',
              scored: true,
            );
          }
        }
        break;
    }

    return RehabFeedback.none;
  }

  // 🆕 大拇指朝上檢查:取「舉得比較高的那隻手」判斷即可(通常是患手在努力跟上)
  //    thumbTip.dy 明顯小於 wrist.dy(影像座標往下為正)才算朝上;
  //    大拇指座標任一邊拿不到就直接跳過,不影響其他判定。
  String? _checkThumbUp(BodyFrame frame, double leftAngle, double rightAngle) {
    final useLeft = leftAngle <= rightAngle; // 取角度較小(較費力/較低)那隻手檢查
    final thumb = frame.joints[
        useLeft ? RehabJoint.leftThumbTip : RehabJoint.rightThumbTip];
    final wrist =
        frame.joints[useLeft ? RehabJoint.leftWrist : RehabJoint.rightWrist];
    if (thumb == null || wrist == null) return null; // 資料源還沒接上,跳過

    const thumbUpMargin = 0.02; // 正規化座標的容許誤差
    final isThumbUp = thumb.dy < wrist.dy - thumbUpMargin;
    if (!isThumbUp) {
      return _throttled('請記得大拇指朝上,不要讓手臂往內轉');
    }
    return null;
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
    _state = _RaiseState.waitReady;
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
    _state = _RaiseState.waitReady;
  }
}