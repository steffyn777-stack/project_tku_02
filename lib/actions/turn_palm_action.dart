// lib/actions/turn_palm_action.dart
//
// 翻掌訓練 — 完整判斷邏輯（從 Kotlin TurnPalmAction.kt 搬移過來）
// 階段一：偵測棍子垂直並穩定 5 秒
// 階段二：偵測內外翻轉次數
// 全部在 Dart 這裡處理，不再依賴 trainingStream

import 'dart:async';
import '../services/mediapipe_service.dart';
import 'base_rehab_action.dart';
import 'rehab_action_callback.dart';
import '../services/hand_voice_service.dart';

enum _Stage { stage1, transitioning, stage2 }

class TurnPalmAction extends BaseRehabAction implements LevelUpControllable {
  final bool overlayMirrored;
  final int startingLevel;
  //final int targetReps;   // ← 新增
  int targetReps;   // ← 新增(拿掉 final,支援自訂次數覆蓋)

  int _currentLevel = 1;
  bool _pendingLevelUp = false;
  _Stage _currentStage = _Stage.stage1;

  // 階段一
  double _smoothedAngleStage1 = 0.0;
  bool _isCurrentlyStable = false;
  DateTime _holdStartTime = DateTime.now();

  // 倒數
  bool _isCountingDown = false;
  bool _countdownDone = false;
  int _countdownSeconds = 5;
  Timer? _countdownTimer;

  // 階段二
  final List<String> _palmStateBuffer = [];
  String _lastConfirmedState = '';
  int _repCount = 0;
  DateTime _lastRepTime = DateTime.now();
  double _currentRepMaxWobble = 0.0;

  // 完成紀錄
  final List<String> _mistakeLogs = [];
  DateTime _sessionStartTime = DateTime.now();

  // 倒數轉場
// ignore: unused_field
  bool _isTransitioning = false;
  DateTime _transitionStartTime = DateTime.now();
  int _lastCountdownSec = -1;
  Timer? _transitionTimer;

  static const double _smoothingFactor = 0.2;

  TurnPalmAction({
    required RehabActionCallback callback,
    this.overlayMirrored = false,
    this.startingLevel = 1,
    this.targetReps = 10,   // ← 新增
  }) : super(callback) {
    _startLevel(startingLevel);
  }

  // ── BaseRehabAction ─────────────────────────────────────────────

  @override
  bool get isReadyToReceiveUpdates => _countdownDone;

  @override
  String get initialFeedback => '請握住短棍，對齊虛線保持直立 5 秒';

  @override
  String get initialInstruction => '對齊後保持5秒，才開始計算次數';

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _transitionTimer?.cancel();
  }

  void resetForCameraFlip() {
    if (_countdownDone) return;
    _resetCountdown();
  }

  // ── 主要邏輯 ─────────────────────────────────────────────────────

  @override
  void processLandmarks(List<Landmark> landmarks) {
    if (_pendingLevelUp) return; // 🆕
    if (landmarks.length < 18) return;

    switch (_currentStage) {
      case _Stage.stage1:
        _detectStage1(landmarks);
        break;
      case _Stage.transitioning:
        // 等 timer 處理
        break;
      case _Stage.stage2:
        _detectStage2(landmarks);
        break;
    }
  }

  // ── 階段一：偵測棍子垂直 ─────────────────────────────────────────

  void _detectStage1(List<Landmark> landmarks) {
    final indexMcp = landmarks[5];
    final pinkyMcp = landmarks[17];

    final indexX = overlayMirrored ? (1.0 - indexMcp.x) : indexMcp.x;
    final pinkyX = overlayMirrored ? (1.0 - pinkyMcp.x) : pinkyMcp.x;

    final dx = indexX - pinkyX;
    final dy = indexMcp.y - pinkyMcp.y;
    final angle = _atan2(dy, dx) * (180 / 3.14159265);
    final deviation = (angle - (-90)).abs();
    final rawDev = deviation > 180 ? 360 - deviation : deviation;

    _smoothedAngleStage1 =
        (_smoothingFactor * rawDev) + ((1 - _smoothingFactor) * _smoothedAngleStage1);
    final displayAngle = _smoothedAngleStage1.toInt();

    callback.onStatsChanged(accuracy: displayAngle.toDouble());

    final wobbleTolerance = _currentLevel == 1 ? 25 : 15;

    if (displayAngle < wobbleTolerance) {
      if (!_isCurrentlyStable) {
        _isCurrentlyStable = true;
        _holdStartTime = DateTime.now();
        callback.onFeedbackChanged('✅ 很好！穩住棍子', '請出點力，保持直立不要晃動');
        _startCountdown();
      } else {
        final duration = DateTime.now().difference(_holdStartTime).inMilliseconds;
        callback.onStatsChanged(
            repCount: 0,
            accuracy: displayAngle.toDouble());

        if (duration >= 5000) {
          _isCurrentlyStable = false;
          _currentStage = _Stage.transitioning;
          _isTransitioning = true;
          _transitionStartTime = DateTime.now();
          _lastCountdownSec = -1;
          callback.onFeedbackChanged('🎉 穩定度測試通過！', '準備進入翻轉訓練');
          _countdownTimer?.cancel();
          _startTransitionCountdown();
        }
      }
    } else {
      if (_isCurrentlyStable) {
        _isCurrentlyStable = false;
        _resetCountdown();
      }
      callback.onFeedbackChanged('⚠️ 棍子歪了！', '請拉正短棍，對齊虛線');
      HandVoiceService.speak('歪了');
    }
  }

  // ── 倒數（階段一等待） ────────────────────────────────────────────

  void _startCountdown() {
    if (_isCountingDown) return;
    _isCountingDown = true;
    _countdownSeconds = 5;

    callback.onCountdownChanged(
        isCountingDown: true, seconds: _countdownSeconds, isDone: false);

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _countdownSeconds--;
      if (_countdownSeconds <= 0) {
        timer.cancel();
        _isCountingDown = false;
        // 倒數完成由 _detectStage1 的 5000ms 判斷觸發
        callback.onCountdownChanged(
            isCountingDown: false, seconds: 0, isDone: false);
      } else {
        callback.onCountdownChanged(
            isCountingDown: true, seconds: _countdownSeconds, isDone: false);
      }
    });
  }

  void _resetCountdown() {
    _countdownTimer?.cancel();
    _isCountingDown = false;
    _countdownSeconds = 5;
    callback.onCountdownChanged(
        isCountingDown: false, seconds: 5, isDone: false);
    callback.onFeedbackChanged('棍子歪掉了，重新對齊', '將棍子保持垂直，再次倒數5秒');
  }

  // ── 轉場倒數（階段一→階段二） ────────────────────────────────────

  void _startTransitionCountdown() {
    _transitionTimer?.cancel();
    _transitionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final elapsed =
          DateTime.now().difference(_transitionStartTime).inMilliseconds;

      if (elapsed >= 3000) {
        _transitionTimer?.cancel();
        _isTransitioning = false;
        _currentStage = _Stage.stage2;
        _lastRepTime = DateTime.now();
        _countdownDone = true;
        callback.onCountdownChanged(
            isCountingDown: false, seconds: 0, isDone: true);
        callback.onFeedbackChanged('開始翻掌！', '請握住短棍，輕輕向內轉');
        HandVoiceService.speak('開始');
        callback.onStatsChanged(repCount: 0);
      } else {
        final remain = 3 - (elapsed ~/ 1000);
        if (remain != _lastCountdownSec && remain > 0) {
          _lastCountdownSec = remain;
          callback.onCountdownChanged(
              isCountingDown: true, seconds: remain, isDone: false);
          callback.onFeedbackChanged('⏳ 準備進入階段二', '請在 $remain 秒後開始練習內外轉');
        }
      }
    });
  }

  // ── 階段二：偵測內外翻轉 ─────────────────────────────────────────

  void _detectStage2(List<Landmark> landmarks) {
    final wrist     = landmarks[0];
    final middleMcp = landmarks[9];
    final indexMcp  = landmarks[5];
    final pinkyMcp  = landmarks[17];

    // 晃動偵測
    final wobbleDx = middleMcp.x - wrist.x;
    final wobbleDy = middleMcp.y - wrist.y;
    final wobbleAngle = (_atan2(wobbleDy, wobbleDx) * (180 / 3.14159265) - (-90)).abs();
    final rawWobble = wobbleAngle > 180 ? 360 - wobbleAngle : wobbleAngle;
    if (rawWobble > _currentRepMaxWobble) _currentRepMaxWobble = rawWobble;

    final targetDx = _currentLevel == 1 ? 0.04 : 0.08;
    final dx = pinkyMcp.x - indexMcp.x;

    final rawProgress = dx.abs() / targetDx;
    final progress = rawProgress < 1.0 ? rawProgress : 1.0;
    final now = DateTime.now();
    final durationMs = now.difference(_lastRepTime).inMilliseconds;
    final speedState = progress > 0.5 && durationMs < 600 ? 1 : 0;
    callback.onStatsChanged(progress: progress, speedState: speedState);

    final state = dx > targetDx
        ? 'OUTWARD'
        : dx < -targetDx
            ? 'INWARD'
            : 'NEUTRAL';

    _palmStateBuffer.add(state);
    if (_palmStateBuffer.length > 8) _palmStateBuffer.removeAt(0);

    final isStableInward =
        _palmStateBuffer.where((s) => s == 'INWARD').length >= 5;
    final isStableOutward =
        _palmStateBuffer.where((s) => s == 'OUTWARD').length >= 5;

    if (isStableInward && _lastConfirmedState != 'INWARD') {
      if (_lastConfirmedState == 'OUTWARD') {
        if (durationMs > 1200) {
          _repCount++;
          _lastRepTime = now;
          var score = 100;

          if (_currentRepMaxWobble > 25.0) {
            score -= 20;
            _mistakeLogs.add('第 $_repCount 次：嚴重晃動 (偏移 ${_currentRepMaxWobble.toInt()} 度)');
          } else if (_currentRepMaxWobble > 15.0) {
            score -= 10;
            _mistakeLogs.add('第 $_repCount 次：輕微晃動');
          }
          if (durationMs < 2000) {
            score -= 10;
            _mistakeLogs.add('第 $_repCount 次：動作略快');
          }
          score = score < 60 ? 60 : score;
          _currentRepMaxWobble = 0.0;

          callback.onFeedbackChanged('✅ 完成一次！(本次: $score 分)', '很好，現在請向外轉');
          HandVoiceService.speak('完成一次');
          callback.onStatsChanged(repCount: _repCount);
          callback.onStatsChanged(progress: 0, speedState: 0);

          if (_repCount >= targetReps) {
            if (_currentLevel == 1 && score >= 80) {
              _pendingLevelUp = true; // 🆕 先不升級,等使用者確認
              callback.onLevelUpReady(nextLevel: 2, nextLevelLabel: '中階 (幅度加大)'); // 🆕
            } else {
              final durationSeconds =
                  DateTime.now().difference(_sessionStartTime).inSeconds;
              callback.onFeedbackChanged('🎉 訓練結束！', '辛苦了');
              HandVoiceService.speak('訓練結束');
              callback.onTrainingComplete(
                repCount: _repCount,
                durationSeconds: durationSeconds,
                mistakeLogs: List.from(_mistakeLogs),
              );
            }
          }
        } else {
          _lastRepTime = now;
          _mistakeLogs.add('未計入次數：動作過快');
          callback.onFeedbackChanged('⚠️ 動作太快', '請慢慢轉動');
          HandVoiceService.speak('太快');
        }
      } else {
        callback.onFeedbackChanged('✅ 已向內轉', '很好，請向外轉');
      }
      _lastConfirmedState = 'INWARD';

    } else if (isStableOutward && _lastConfirmedState != 'OUTWARD') {
      callback.onFeedbackChanged('✅ 已向外轉', '很好，請向內轉');
      _lastConfirmedState = 'OUTWARD';
      callback.onStatsChanged(progress: 0, speedState: 0);
    }

    callback.onStatsChanged(accuracy: dx);
  }

  // ── 關卡切換 ─────────────────────────────────────────────────────

  void _startLevel(int level) {
    _currentLevel = level;
    _repCount = 0;
    _palmStateBuffer.clear();
    _lastConfirmedState = '';
    _currentStage = _Stage.stage1;
    _mistakeLogs.clear();
    _sessionStartTime = DateTime.now();
    _countdownDone = false;
    _isCurrentlyStable = false;
    _smoothedAngleStage1 = 0.0;

    final diffText = level == 1 ? '初階' : '中階 (幅度加大)';
    callback.onLevelUp(newLevel: level, levelLabel: diffText, newTargetReps: targetReps);
    callback.onFeedbackChanged('$diffText 翻掌', '請握住短棍，對齊虛線保持直立 5 秒');
    callback.onStatsChanged(repCount: 0);
    callback.onCountdownChanged(isCountingDown: false, seconds: 5, isDone: false);
  }

  @override
  bool get isPendingLevelUp => _pendingLevelUp; // 🆕

  @override
  void confirmLevelUp({int? customTargetReps}) { // 🆕
    _pendingLevelUp = false;
    if (customTargetReps != null && customTargetReps > 0) {
      targetReps = customTargetReps;
    }
    _startLevel(2);
  }

  @override
  void declineLevelUp() { // 🆕 選不要升級 → 直接結束訓練
    _pendingLevelUp = false;
    final durationSeconds =
        DateTime.now().difference(_sessionStartTime).inSeconds;
    callback.onFeedbackChanged('🎉 訓練結束！', '辛苦了');
    HandVoiceService.speak('訓練結束');
    callback.onTrainingComplete(
      repCount: _repCount,
      durationSeconds: durationSeconds,
      mistakeLogs: List.from(_mistakeLogs),
    );
  }

  // ── 數學工具 ─────────────────────────────────────────────────────

  double _atan2(double y, double x) {
    if (x > 0) return _atan(y / x);
    if (x < 0 && y >= 0) return _atan(y / x) + 3.14159265;
    if (x < 0 && y < 0) return _atan(y / x) - 3.14159265;
    if (x == 0 && y > 0) return 3.14159265 / 2;
    if (x == 0 && y < 0) return -3.14159265 / 2;
    return 0;
  }

  double _atan(double x) {
    const pi4 = 3.14159265 / 4;
    const pi2 = 3.14159265 / 2;
    if (x.abs() <= 1) {
      return pi4 * x - x * (x.abs() - 1) * (0.2447 + 0.0663 * x.abs());
    }
    return pi2 -
        (1 / x) * (pi4 - (1 / x) * ((1 / x).abs() - 1) * (0.2447 + 0.0663 * (1 / x).abs()));
  }
}