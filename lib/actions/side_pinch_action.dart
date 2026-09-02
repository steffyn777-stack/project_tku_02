// lib/actions/side_pinch_action.dart
//
// 側捏訓練 — 完整判斷邏輯（從 Kotlin SidePinchAction.kt 搬移過來）
// 次數、feedback、完成判斷全部在 Dart 這裡處理，不再依賴 trainingStream

import 'dart:async';
import '../services/mediapipe_service.dart';
import 'base_rehab_action.dart';
import 'rehab_action_callback.dart';
import '../services/hand_voice_service.dart';

class SidePinchAction extends BaseRehabAction implements LevelUpControllable {
  final int difficulty; // 1=初階 2=中階 3=進階
  //final int targetReps;   // ← 新增
  int targetReps;

  final List<String> _mistakeLogs = [];
  DateTime _sessionStartTime = DateTime.now();

  double _smoothedPinchDistance = 0.0;
  final List<String> _pinchStateBuffer = [];
  String _lastConfirmedPinchState = '';

  int _currentLevel = 1;
  bool _isTransitioning = false;
  bool _pendingLevelUp = false; // 🆕
  DateTime _transitionStartTime = DateTime.now();
  int _lastCountdownSec = -1;
  Timer? _transitionTimer;

  double _repStartWristX = 0.0;
  double _repStartWristY = 0.0;

  int _repCount = 0;
  DateTime _lastRepTime = DateTime.now();

  static const double _smoothingFactor = 0.2;

  SidePinchAction({
    required RehabActionCallback callback,
    this.difficulty = 1,
    this.targetReps = 10,   // ← 新增
  }) : super(callback) {
    _startLevel(difficulty);
  }

  // ── BaseRehabAction ─────────────────────────────────────────────

  @override
  bool get isReadyToReceiveUpdates => true;

  @override
  String get initialFeedback => '請先將手指完全打開';

  @override
  String get initialInstruction => '準備開始側捏訓練';

  @override
  void dispose() {
    _transitionTimer?.cancel();
  }

  // ── 主要邏輯 ─────────────────────────────────────────────────────

  @override
  void processLandmarks(List<Landmark> landmarks) {
    if (_pendingLevelUp) return;
    if (landmarks.length < 18) return;

    if (_isTransitioning) {
      _handleTransition();
      return;
    }

    final thumbTip  = landmarks[4];
    final indexPip  = landmarks[6];
    final wrist     = landmarks[0];
    final middleMcp = landmarks[9];

    final palmLen   = _hypot(middleMcp.x - wrist.x, middleMcp.y - wrist.y);
    final pinchDist = _hypot(thumbTip.x - indexPip.x, thumbTip.y - indexPip.y);
    final ratio = (pinchDist / palmLen) * 100;

    _smoothedPinchDistance =
        (_smoothingFactor * ratio) + ((1 - _smoothingFactor) * _smoothedPinchDistance);

    callback.onStatsChanged(accuracy: _smoothedPinchDistance);

    final pinchThreshold = _currentLevel == 1 ? 55.0 : _currentLevel == 2 ? 45.0 : 40.0;
    final openThreshold  = _currentLevel == 1 ? 58.0 : 65.0;
    final totalRange     = openThreshold - pinchThreshold;
    final rawProgress    = 1.0 - ((_smoothedPinchDistance - pinchThreshold) / totalRange);
    final progress       = rawProgress.clamp(0.0, 1.0);

    callback.onStatsChanged(progress: progress, speedState: 0);

    final currentState = _smoothedPinchDistance < pinchThreshold
        ? 'PINCHED'
        : _smoothedPinchDistance > openThreshold
            ? 'OPENED'
            : 'MID';

    _pinchStateBuffer.add(currentState);
    if (_pinchStateBuffer.length > 8) _pinchStateBuffer.removeAt(0);

    final isStablePinch = _pinchStateBuffer.where((s) => s == 'PINCHED').length >= 5;
    final isStableOpen  = _pinchStateBuffer.where((s) => s == 'OPENED').length >= 5;

    if (isStablePinch && _lastConfirmedPinchState != 'PINCHED') {
      if (_lastConfirmedPinchState == 'OPENED') {
        final now = DateTime.now();
        final durationMs = now.difference(_lastRepTime).inMilliseconds;

        if (durationMs > 1200) {
          _repCount++;
          _lastRepTime = now;
          var score = 100;

          if (_currentLevel == 3) {
            final wristMove = _hypot(wrist.x - _repStartWristX, wrist.y - _repStartWristY);
            if (wristMove > 0.05) {
              score -= 20;
              _mistakeLogs.add('第 $_repCount 次：手腕晃動過大');
            }
            if (durationMs > 2000) {
              score -= 15;
              _mistakeLogs.add('第 $_repCount 次：側捏動作不夠流暢');
            }
          }
          score = score < 60 ? 60 : score;

          callback.onFeedbackChanged('✅ 捏緊了！(本次: $score 分)', '請將手指完全打開');
          callback.onStatsChanged(repCount: _repCount);
          HandVoiceService.speak('捏緊了');

          if (_repCount >= targetReps) _checkLevelUp();
        } else {
          _lastRepTime = DateTime.now();
          _mistakeLogs.add('未計入次數：開合動作過快');
          callback.onFeedbackChanged('⚠️ 動作太快', '請放慢速度，重新打開');
          HandVoiceService.speak('太快');
        }
      } else {
        callback.onFeedbackChanged('✅ 捏緊完成', '請將手指完全打開');
      }
      _lastConfirmedPinchState = 'PINCHED';

    } else if (isStableOpen && _lastConfirmedPinchState != 'OPENED') {
      callback.onFeedbackChanged('✅ 已張開', '請用力側捏');
      _repStartWristX = wrist.x;
      _repStartWristY = wrist.y;
      _lastConfirmedPinchState = 'OPENED';
    }
  }

  // ── 私有邏輯 ─────────────────────────────────────────────────────

  void _startLevel(int level) {
    _currentLevel = level;
    _repCount = 0;
    _pinchStateBuffer.clear();
    _lastConfirmedPinchState = '';
    _isTransitioning = true;
    _transitionStartTime = DateTime.now();
    _lastCountdownSec = -1;
    _mistakeLogs.clear();
    _sessionStartTime = DateTime.now();

    final levelName = level == 1
        ? '初階 (微幅動作)'
        : level == 2
            ? '中階 (標準側捏)'
            : '進階 (懸空連擊)';
    
    callback.onLevelUp(newLevel: level, levelLabel: 'Lv.$level - $levelName', newTargetReps: targetReps);

    callback.onFeedbackChanged('側捏訓練 Lv.$level - $levelName', '準備進入關卡...');
    callback.onStatsChanged(repCount: 0);

    // 倒數計時
    _transitionTimer?.cancel();
    _transitionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _handleTransition();
    });
  }

  void _handleTransition() {
    final elapsed = DateTime.now().difference(_transitionStartTime).inMilliseconds;

    if (elapsed < 3000) {
      final remain = 3 - (elapsed ~/ 1000);
      if (remain != _lastCountdownSec && remain > 0) {
        _lastCountdownSec = remain;
        callback.onCountdownChanged(
            isCountingDown: true, seconds: remain, isDone: false);
      }
    } else {
      _transitionTimer?.cancel();
      _isTransitioning = false;
      _lastRepTime = DateTime.now();
      _lastCountdownSec = -1;
      callback.onCountdownChanged(
          isCountingDown: false, seconds: 0, isDone: true);
      callback.onFeedbackChanged('開始！', '請先將手指完全打開');
      HandVoiceService.speak('開始');
    }
  }

  void _checkLevelUp() {
    final finalScore = _repCount > 0 ? 80 : 0; // 簡化：完成10次即80分
    if (_currentLevel < 3 && finalScore >= 80) {
      _pendingLevelUp = true; // 🆕 先不升級,等使用者確認
      final nextLevel = _currentLevel + 1;
      final nextLevelName = nextLevel == 2 ? '中階 (標準側捏)' : '進階 (懸空連擊)';
      callback.onLevelUpReady(
        nextLevel: nextLevel,
        nextLevelLabel: 'Lv.$nextLevel - $nextLevelName',
      ); // 🆕
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

  @override
  bool get isPendingLevelUp => _pendingLevelUp; // 🆕

  @override
  void confirmLevelUp({int? customTargetReps}) { // 🆕
    _pendingLevelUp = false;
    if (customTargetReps != null && customTargetReps > 0) {
      targetReps = customTargetReps;
    }
    _startLevel(_currentLevel + 1);
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

  double _hypot(double dx, double dy) {
    final n = dx * dx + dy * dy;
    if (n <= 0) return 0;
    double x = n;
    for (int i = 0; i < 20; i++) {
      x = (x + n / x) / 2;
    }
    return x;
  }
}