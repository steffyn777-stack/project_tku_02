// lib/actions/wrist_extension_action.dart
//
// 翹手腕式 — 中風復健跟著做 第11式
// 手腕背屈（往上翹）與掌屈（往下壓）的來回訓練
// 使用 MediaPipe Hand Landmarks → extends BaseRehabAction
//
// 偵測原理：
//   wrist(0) → middleMcp(9) 連線與水平軸的夾角
//   背屈（往上翹）: middleMcp.y < wrist.y，夾角為負（手背朝上）
//   掌屈（往下壓）: middleMcp.y > wrist.y，夾角為正（手心朝上）

import 'dart:async';
import 'dart:math' as math;
import '../services/mediapipe_service.dart';
import 'base_rehab_action.dart';
import 'rehab_action_callback.dart';
import '../services/hand_voice_service.dart';

class WristExtensionAction extends BaseRehabAction {
  int _repCount = 0;
  bool _isTransitioning = false;
  bool _countdownDone = false;
  final int targetReps;   // ← 新增

  final List<String> _stateBuffer = [];
  String _lastConfirmedState = '';

  double _smoothedAngle = 0.0;
  static const double _smoothingFactor = 0.2;

  // 動態基準（初始化時校準中立位）
  double? _baseAngleDeg;

  DateTime _lastRepTime = DateTime.now();
  DateTime _sessionStartTime = DateTime.now();
  final List<String> _mistakeLogs = [];

  DateTime _transitionStartTime = DateTime.now();
  int _lastCountdownSec = -1;
  Timer? _transitionTimer;

  WristExtensionAction({
    required RehabActionCallback callback,
    this.targetReps = 10,
  }) : super(callback) {
    _init();
  }

  // ── BaseRehabAction ──────────────────────────────────────

  @override
  bool get isReadyToReceiveUpdates => _countdownDone;

  @override
  String get initialFeedback => '手臂放桌上，手掌朝下，準備翹手腕';

  // ✅ 修正 #3：統一順序為「先下壓 → 再上翹」，跟 _init() 開始訓練時
  //    的語音提示一致，避免使用者看到兩種不同的順序說明。
  @override
  String get initialInstruction => '手腕先往下壓 → 再往上翹，算一次';

  @override
  void dispose() {
    _transitionTimer?.cancel();
  }

  // ── 主要邏輯 ─────────────────────────────────────────────

  @override
  void processLandmarks(List<Landmark> landmarks) {
    if (landmarks.length < 10) return;
    if (_isTransitioning) return;

    final wrist     = landmarks[0];   // 手腕
    final middleMcp = landmarks[9];   // 中指掌指關節

    // wrist → middleMcp 連線的仰角（度）
    // dy = middleMcp.y - wrist.y（影像座標，往下為正）
    // dx = middleMcp.x - wrist.x
    // atan2(dy, dx) → 往右水平為 0，往上（dy<0）為負
    final dx = middleMcp.x - wrist.x;
    final dy = middleMcp.y - wrist.y;
    final angleDeg = math.atan2(dy, dx) * (180 / math.pi);

    // 第一幀時校準基準角度（手掌放平時的角度）
    _baseAngleDeg ??= angleDeg;

    // 相對於基準的偏角：正值 = 下壓（掌屈），負值 = 上翹（背屈）
    double relAngle = angleDeg - _baseAngleDeg!;

    // 修正超過 ±180 的翻轉
    if (relAngle > 180) relAngle -= 360;
    if (relAngle < -180) relAngle += 360;

    // 低通濾波平滑化
    _smoothedAngle = (_smoothingFactor * relAngle) +
        ((1 - _smoothingFactor) * _smoothedAngle);

    // 將平滑後的角度回傳給 UI（正=下壓，負=上翹）
    callback.onStatsChanged(accuracy: _smoothedAngle);

    // 背屈（上翹）門檻：-20 度；掌屈（下壓）門檻：+20 度
    const extensionThreshold = 20.0; // 上翹（背屈）
    const flexionThreshold   = 20.0; // 下壓（掌屈）

    // 進度條：以當前方向的門檻為基準
    final rawProgress = (_smoothedAngle.abs() /
            (_smoothedAngle < 0 ? extensionThreshold : flexionThreshold))
        .clamp(0.0, 1.0);
    callback.onStatsChanged(progress: rawProgress, speedState: 0);

    // 狀態判定
    final String state;
    if (_smoothedAngle < -extensionThreshold) {
      state = 'EXTENSION'; // 背屈（往上翹）
    } else if (_smoothedAngle > flexionThreshold) {
      state = 'FLEXION';   // 掌屈（往下壓）
    } else if (_smoothedAngle.abs() < 8.0) {
      state = 'NEUTRAL';
    } else {
      state = 'MOVING';
    }

    // 狀態緩衝區去雜訊（5/8 幀穩定才確認）
    _stateBuffer.add(state);
    if (_stateBuffer.length > 8) _stateBuffer.removeAt(0);

    final isStableExtension =
        _stateBuffer.where((s) => s == 'EXTENSION').length >= 5;
    final isStableFlexion =
        _stateBuffer.where((s) => s == 'FLEXION').length >= 5;

    // ── 狀態機 ──────────────────────────────────────────────

    if (isStableExtension && _lastConfirmedState != 'EXTENSION') {
      if (_lastConfirmedState == 'FLEXION') {
        // 掌屈 → 背屈，完成一次來回
        final now = DateTime.now();
        final durationMs = now.difference(_lastRepTime).inMilliseconds;

        if (durationMs > 1200) {
          _repCount++;
          _lastRepTime = now;
          var score = 100;

          if (durationMs > 4000) {
            score -= 10;
            _mistakeLogs.add('第 $_repCount 次：節奏偏慢');
          }
          if (_smoothedAngle.abs() < extensionThreshold * 1.2) {
            score -= 10;
            _mistakeLogs.add('第 $_repCount 次：上翹幅度略小');
          }
          score = score < 60 ? 60 : score;

          callback.onFeedbackChanged(
            '✅ 往上翹到了！(本次: $score 分)',
            '很好，換往下壓',
          );
          callback.onStatsChanged(repCount: _repCount);

          if (_repCount >= targetReps) _finish();
        } else {
          _lastRepTime = DateTime.now();
          _mistakeLogs.add('未計入：動作太快');
          callback.onFeedbackChanged('⚠️ 動作太快', '請放慢，慢慢翹過去');
          HandVoiceService.speak('太快');
        }
      } else {
        // 從中立或開始直接翹上來，提示下一步
        callback.onFeedbackChanged('✅ 往上翹', '請換往下壓');
      }
      _lastConfirmedState = 'EXTENSION';

    } else if (isStableFlexion && _lastConfirmedState != 'FLEXION') {
      callback.onFeedbackChanged('✅ 往下壓', '請換往上翹');
      _lastConfirmedState = 'FLEXION';

    } else if (state == 'NEUTRAL' && _lastConfirmedState == '') {
      // 初始中立時自動校準基準
      _baseAngleDeg = angleDeg;
    }
  }

  // ── 私有邏輯 ─────────────────────────────────────────────

  void _init() {
    _isTransitioning = true;
    _countdownDone = false;
    _transitionStartTime = DateTime.now();
    _lastCountdownSec = -1;
    _sessionStartTime = DateTime.now();

    callback.onFeedbackChanged('翹手腕訓練', '準備進入關卡...');
    callback.onStatsChanged(repCount: 0);

    _transitionTimer?.cancel();
    _transitionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final elapsed =
          DateTime.now().difference(_transitionStartTime).inMilliseconds;

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
        _countdownDone = true;
        _lastRepTime = DateTime.now();
        callback.onCountdownChanged(
            isCountingDown: false, seconds: 0, isDone: true);
        // ✅ 修正 #3：跟 initialInstruction 統一，先下壓再上翹
        callback.onFeedbackChanged(
          '開始！手腕先往下壓',
          '往下壓 → 往上翹，算一次',
        );
      }
    });
  }

  void _finish() {
    final durationSeconds =
        DateTime.now().difference(_sessionStartTime).inSeconds;
    callback.onFeedbackChanged('🎉 完成 $targetReps 次！訓練結束', '辛苦了，做得很好！');
    HandVoiceService.speak('訓練結束');
    callback.onTrainingComplete(
      repCount: _repCount,
      durationSeconds: durationSeconds,
      mistakeLogs: List.from(_mistakeLogs),
    );
  }
}