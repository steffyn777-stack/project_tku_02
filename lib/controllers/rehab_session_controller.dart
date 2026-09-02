// lib/controllers/rehab_session_controller.dart
//
// 動作判斷邏輯已全部移至 Dart（side_pinch_action / turn_palm_action）
// trainingStream 不再使用，KT 只負責送 landmark
//
// ✅ pause()/resume(),支援「暫停選單」真正的接續(不重建、不歸零)
// 🚀 樹莓派新增:currentModel getter,讓 training_screen.dart 判斷
//    目前用的是 MediaPipeModel 還是 PiPoseModel,以顯示對應畫面
// 🚀 修正:TurnPalmAction 的 overlayMirrored 必須依「目前來源是手機還是
//    樹莓派」動態決定,兩者座標鏡像方向相反,共用同一個 false 會導致
//    樹莓派模式角度算反(偏差顯示接近 180 度)。

import 'dart:async';
import 'dart:typed_data'; // 🚀 新增
import 'package:flutter/material.dart';

import '../actions/base_rehab_action.dart';
import '../actions/rehab_action_callback.dart';
import '../actions/side_pinch_action.dart';
import '../actions/turn_palm_action.dart';
import '../actions/wrist_extension_action.dart';
import '../actions/wrist_side_bend_action.dart';
import '../models/training_action.dart';
import '../services/mediapipe_service.dart';
import '../services/pose_model_interface.dart';
import '../services/pi_pose_model.dart'; // 🚀 新增:判斷是否為樹莓派來源

// ── Session 狀態快照 ──────────────────────────────────────────────
class RehabSessionState {
  final List<Landmark> handLandmarks;
  final bool handDetected;
  final List<Offset> bodyLandmarks;
  final Uint8List? imageBytes; // 🚀 新增

  final String feedback;
  final String instruction;
  final int repCount;
  final double accuracy;
  final double progress;
  final int speedState;
  final bool isComplete;

  final bool isCountingDown;
  final int countdownSeconds;
  final bool countdownDone;

  final int durationSeconds;
  final List<String> mistakeLogs;
  final int targetReps; // ← 新增
  final String currentLevelLabel; // ✅ 加這行(欄位宣告)
  final int currentLevel; // ✅ 新增
  final bool pendingLevelUp; // 🆕 是否正等待使用者確認升級
  final int pendingNextLevel; // 🆕 等待確認的下一階是第幾階
  final String pendingNextLevelLabel; // 🆕 等待確認的下一階標籤文字

  const RehabSessionState({
    this.handLandmarks = const [],
    this.handDetected = false,
    this.bodyLandmarks = const [],
    this.imageBytes, // 🚀 新增
    this.feedback = '請將手放入鏡頭範圍內',
    this.instruction = '等待偵測中...',
    this.repCount = 0,
    this.accuracy = 0,
    this.progress = 0,
    this.speedState = 0,
    this.isComplete = false,
    this.isCountingDown = false,
    this.countdownSeconds = 5,
    this.countdownDone = false,
    this.durationSeconds = 0,
    this.mistakeLogs = const [],
    this.targetReps = 10, // ← 新增
    this.currentLevelLabel = '', // ✅ 加這行(預設值)
    this.currentLevel = 1, // ✅ 新增
    this.pendingLevelUp = false, // 🆕
    this.pendingNextLevel = 1, // 🆕
    this.pendingNextLevelLabel = '', // 🆕
  });

  RehabSessionState copyWith({
    List<Landmark>? handLandmarks,
    bool? handDetected,
    List<Offset>? bodyLandmarks,
    Uint8List? imageBytes, // 🚀 新增
    String? feedback,
    String? instruction,
    int? repCount,
    double? accuracy,
    double? progress,
    int? speedState,
    bool? isComplete,
    bool? isCountingDown,
    int? countdownSeconds,
    bool? countdownDone,
    int? durationSeconds,
    List<String>? mistakeLogs,
    int? targetReps, // ← 新增
    String? currentLevelLabel, // ✅ 加這行(copyWith 參數)
    int? currentLevel, // ✅ 新增
    bool? pendingLevelUp, // 🆕
    int? pendingNextLevel, // 🆕
    String? pendingNextLevelLabel, // 🆕
  }) {
    return RehabSessionState(
      handLandmarks: handLandmarks ?? this.handLandmarks,
      handDetected: handDetected ?? this.handDetected,
      bodyLandmarks: bodyLandmarks ?? this.bodyLandmarks,
      imageBytes: imageBytes ?? this.imageBytes, // 🚀 新增
      feedback: feedback ?? this.feedback,
      instruction: instruction ?? this.instruction,
      repCount: repCount ?? this.repCount,
      accuracy: accuracy ?? this.accuracy,
      progress: progress ?? this.progress,
      speedState: speedState ?? this.speedState,
      isComplete: isComplete ?? this.isComplete,
      isCountingDown: isCountingDown ?? this.isCountingDown,
      countdownSeconds: countdownSeconds ?? this.countdownSeconds,
      countdownDone: countdownDone ?? this.countdownDone,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      mistakeLogs: mistakeLogs ?? this.mistakeLogs,
      targetReps: targetReps ?? this.targetReps, // ← 新增
      currentLevelLabel:
          currentLevelLabel ?? this.currentLevelLabel, // ✅ 加這行(組裝新物件)
      currentLevel: currentLevel ?? this.currentLevel, // ✅ 新增
      pendingLevelUp: pendingLevelUp ?? this.pendingLevelUp, // 🆕
      pendingNextLevel: pendingNextLevel ?? this.pendingNextLevel, // 🆕
      pendingNextLevelLabel:
          pendingNextLevelLabel ?? this.pendingNextLevelLabel, // 🆕
    );
  }
}

// ── Controller ────────────────────────────────────────────────────
class RehabSessionController implements RehabActionCallback {
  final IPoseModel model;
  final TrainingAction action;
  final DifficultyOption difficulty;

  late final BaseRehabAction _actionLogic;

  StreamSubscription? _frameSub;

  final _stateCtrl = StreamController<RehabSessionState>.broadcast();
  Stream<RehabSessionState> get stateStream => _stateCtrl.stream;

  RehabSessionState _state = const RehabSessionState();
  RehabSessionState get currentState => _state;

  // 🚀 樹莓派新增:讓 UI 層(training_screen.dart)拿到目前用的 model,
  // 用來判斷是不是 PiPoseModel、進而取得底層 PiHandSource 顯示畫面
  IPoseModel get currentModel => model;

  // 暫停中:frame 監聽會直接忽略新的一幀,凍結畫面與計次
  bool _isPaused = false;

  RehabSessionController({
    required this.model,
    required this.action,
    required this.difficulty,
  }) {
    //final diffIdx = action.difficulties.indexOf(difficulty) + 1;
    final diffIdx =
        action.difficulties.indexWhere((d) => d.level == difficulty.level) + 1;
    _state = _state.copyWith(
      targetReps: difficulty.targetReps,
      currentLevel: diffIdx, // ✅ 新增
    ); // ← 新加這行

    // 🚀 修正:樹莓派來源跟手機來源的 landmark 座標左右鏡像方向相反,
    // TurnPalmAction 的角度計算公式是針對手機原生鏡像後的座標調校的,
    // 樹莓派模式必須把 overlayMirrored 反過來,角度才會算對,
    // 不然會出現偏差角度接近 180 度(方向算反)的情況。
    final bool isExternalSource = model is PiPoseModel;

    switch (action.type) {
      case ActionType.turnPalm:
        _actionLogic = TurnPalmAction(
          callback: this,
          targetReps: difficulty.targetReps, // ← 新增
          overlayMirrored: isExternalSource, // 🚀 新增:依來源動態決定鏡像方向
        );

      case ActionType.wristExtension:
        _actionLogic = WristExtensionAction(
          callback: this,
          targetReps: difficulty.targetReps, // ← 新增
        );
      // 有 3 秒倒數，countdownDone 由 action 自己透過 onCountdownChanged 設定

      case ActionType.wristSideBend:
        _actionLogic = WristSideBendAction(
          callback: this,
          targetReps: difficulty.targetReps, // ← 新增
        );
      // 有 3 秒倒數，countdownDone 由 action 自己透過 onCountdownChanged 設定

      default:
        // sidePinch 及其他手部動作
        _actionLogic = SidePinchAction(
          callback: this,
          difficulty: diffIdx,
          targetReps: difficulty.targetReps, // ← 新增
        );
        _state = _state.copyWith(countdownDone: true);
    }
  }

  // ── 生命週期 ──────────────────────────────────────────────────────

  Future<void> start() async {
    //final diffIdx = action.difficulties.indexOf(difficulty) + 1;
    final diffIdx =
        action.difficulties.indexWhere((d) => d.level == difficulty.level) + 1;

    String actionCode = 'SECOND_ACTION';
    if (action.type == ActionType.turnPalm) actionCode = 'TURN_PALM';

    await model.start(PoseModelConfig(
      actionType: actionCode,
      difficulty: diffIdx,
      useFrontCamera: true,
    ));

    // 只訂閱 frameStream，不再訂閱 trainingStream
    _frameSub = model.frameStream.listen((frame) {
      if (_isPaused) return; // 暫停中:忽略這一幀,不更新畫面、不計次

      _emit(_state.copyWith(
        handLandmarks: frame.handLandmarks,
        handDetected: frame.handDetected,
        bodyLandmarks: frame.standardJoints.values.toList(),
        imageBytes: frame.imageBytes, // 🚀 新增
      ));

      // 動作判斷全部交給 Dart action
      _actionLogic.processLandmarks(frame.handLandmarks);
    });

    _emit(_state.copyWith(
      feedback: _actionLogic.initialFeedback,
      instruction: _actionLogic.initialInstruction,
    ));
  }

  // ─── 暫停 / 繼續 ─────────────────────────────────────────────────
  // 暫停時相機/原生偵測仍在背景運作,但這裡直接忽略每一幀的結果,
  // 不更新畫面、不餵進動作判斷邏輯,達到「凍結進度」的效果。
  // 繼續時單純把旗標關掉,下一幀開始就會照原本邏輯接續處理,
  // 不需要重新 start()、不會遺失或錯亂目前的 rep 數與狀態。
  void pause() {
    _isPaused = true;
  }

  void resume() {
    _isPaused = false;
  }

  // 🆕 使用者確認要升級
  void confirmLevelUp({int? customTargetReps}) {
    final logic = _actionLogic;
    if (logic is LevelUpControllable) {
      (logic as LevelUpControllable)
          .confirmLevelUp(customTargetReps: customTargetReps);
    }
    _emit(_state.copyWith(pendingLevelUp: false));
  }

  // 🆕 使用者選擇不升級 → 結束訓練
  void declineLevelUp() {
    final logic = _actionLogic;
    if (logic is LevelUpControllable) {
      (logic as LevelUpControllable).declineLevelUp();
    }
    _emit(_state.copyWith(pendingLevelUp: false));
  }

  Future<void> flipCamera() async {
    _emit(_state.copyWith(
        handLandmarks: [], handDetected: false, bodyLandmarks: []));
    if (_actionLogic is TurnPalmAction) {
      (_actionLogic as TurnPalmAction).resetForCameraFlip();
    }
    await model.flipCamera();
  }

  // 等資源真的釋放完才返回,給切換動作時用
  Future<void> disposeAsync() async {
    _actionLogic.dispose();
    await _frameSub?.cancel();

    try {
      await model.stop();
    } catch (_) {
      // 即使原生端拋錯也不要卡住流程,確保一定會往下走
    }

    // 給 Kotlin 端時間完整清理相機 / MediaPipe 資源
    await Future.delayed(const Duration(milliseconds: 350));

    try {
      model.dispose();
    } catch (_) {}

    if (!_stateCtrl.isClosed) await _stateCtrl.close();
  }

  void dispose() {
    _actionLogic.dispose();
    _frameSub?.cancel();
    model.stop();
    model.dispose();
    _stateCtrl.close();
  }

  // ── RehabActionCallback 實作 ──────────────────────────────────────

  @override
  void onFeedbackChanged(String feedback, String instruction) {
    _emit(_state.copyWith(feedback: feedback, instruction: instruction));
  }

  @override
  void onStatsChanged({
    int? repCount,
    double? accuracy,
    double? progress,
    int? speedState,
  }) {
    _emit(_state.copyWith(
      repCount: repCount ?? _state.repCount,
      accuracy: accuracy ?? _state.accuracy,
      progress: progress ?? _state.progress,
      speedState: speedState ?? _state.speedState,
    ));
  }

  @override
  void onCountdownChanged({
    required bool isCountingDown,
    required int seconds,
    required bool isDone,
  }) {
    _emit(_state.copyWith(
      isCountingDown: isCountingDown,
      countdownSeconds: seconds,
      countdownDone: isDone,
    ));
  }

  @override
  void onLevelUp({
    required int newLevel,
    required String levelLabel,
    required int newTargetReps,
  }) {
    _emit(_state.copyWith(
      currentLevelLabel: levelLabel,
      currentLevel: newLevel, // ✅ 補上這行,之前漏加了
    ));
  }

  @override
  void onLevelUpReady({
    required int nextLevel,
    required String nextLevelLabel,
  }) {
    _emit(_state.copyWith(
      pendingLevelUp: true,
      pendingNextLevel: nextLevel,
      pendingNextLevelLabel: nextLevelLabel,
    ));
  }

  @override
  void onTrainingComplete({
    required int repCount,
    required int durationSeconds,
    required List<String> mistakeLogs,
  }) {
    _emit(_state.copyWith(
      isComplete: true,
      repCount: repCount,
      durationSeconds: durationSeconds,
      mistakeLogs: mistakeLogs,
    ));
  }

  void _emit(RehabSessionState next) {
    _state = next;
    if (!_stateCtrl.isClosed) _stateCtrl.add(_state);
  }
}
