// lib/features/rehab/training_screen.dart
//
// ══════════════════════════════════════════════════════════════════
//  重構後的主控畫面
//
//  改動：CompletionDialog 加入 onStartNew callback，
//        支援完成後直接選其他動作或切換難度。
//  ✅ 訓練開始/結束自動錄影,結束時詢問是否保留
//  ✅ 新增:按下停止鍵先跳「暫停選單」(繼續 / 結束),
//     選「繼續」時呼叫 controller.resume(),完全接續原本的次數與狀態;
//     只有選「結束」才會進入原本的完整結束流程(停止錄影、存紀錄、跳完成畫面)。
//  🚀 樹莓派新增:右上角加攝影機切換鈕,訓練中可切換手機鏡頭 / 樹莓派來源。
//     切換時整個 RehabSessionController 連同 model 一起換掉重建,
//     確保狀態機、動作判斷邏輯全部乾淨重來,不會有殘留狀態導致誤判。
//  🚀 修正:HandOverlayWidget 加上 sourceSize,讓骨架點位能跟
//     Image.memory(fit: BoxFit.cover) 的裁切/縮放對齊，
//     解決樹莓派鏡頭骨架貼不上手指的問題（詳見 hand_overlay_widget.dart）。
//  🖥️ 電視投放新增:比照 body_training_screen.dart 的做法，
//     控制端(手機)把手部 landmarks + 訓練狀態透過 Socket 傳給電視，
//     顯示端(電視)不開相機、不跑 RehabSessionController，
//     只讀遠端資料並用 HandOverlayWidget 畫出骨架。
//
//  🆕 手動升級(既有邏輯,維持不動):
//     controller 本身沒有 autoLevelUp 參數,也沒有 isPendingLevelUp /
//     pendingHasNextLevel 這兩個 getter。判斷邏輯完全在這個檔案的
//     _listenController() 裡處理:讀 state.pendingLevelUp 這個既有欄位,
//     依照 widget.autoLevelUp 決定要自動呼叫 controller.confirmLevelUp()
//     還是跳出詢問畫面(_showingLevelUpOverlay)。
//
//  🆕 換動作時把 autoLevelUp 一併帶到下一個畫面(對齊 body_training_screen.dart):
//     - CompletionDialog.onStartNew 簽名為 (action, difficulty, autoLevelUp)
//     - _navigateToAction 多一個 autoLevelUp 參數
//     - 補上 sitToStand / lateralStep 兩個 case(原本漏掉,選這兩個動作會
//       誤跑到 default 分支變成手部訓練畫面)
//     - BodyTrainingScreen 呼叫時補上 targetCount: difficulty.targetReps,
//       避免使用者在完成畫面選的目標次數被忽略
// ══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
// import 'package:flutter_webrtc/flutter_webrtc.dart'; // 🖥️ 不再使用 WebRTC 視訊

//import '../../services/pi_hand_source.dart';
import '../../services/pi_pose_model.dart';
import '../../widgets/pi_ip_dialog.dart';

import '../../controllers/rehab_session_controller.dart';
import '../../models/training_action.dart';
import '../../services/history_service.dart';
import '../../services/mediapipe_model.dart';
import '../../services/mediapipe_service.dart'; // 🖥️ 電視投放新增:拿 Landmark 型別
import '../../services/screen_recorder_service.dart';

import '../../widgets/hand_overlay_widget.dart';
import '../../widgets/completion_dialog.dart';
import '../../widgets/training_stats_panel.dart';
import '../../widgets/training_overlays.dart';
import '../../services/pose_model_interface.dart';

import 'body_training_screen.dart';
import '../../actions/standing_knee_raise_action.dart';
import '../../actions/draw_circle_action.dart';
import '../../actions/reach_action.dart';
import '../../actions/raise_both_arms_action.dart';
import '../../actions/elbow_forward_action.dart';
import '../../actions/sit_to_stand_action.dart'; // 🆕 補上,原本漏掉
import '../../actions/lateral_step_action.dart'; // 🆕 補上,原本漏掉

import '../../actions/body_rehab_action.dart';
import '../../features/plan/plan_repository.dart';

// 🖥️ 電視投放新增
import '../tv_cast/webrtc_service.dart';
import '../tv_cast/socket_server_service.dart';
import '../tv_cast/socket_client_service.dart';

class TrainingScreen extends StatefulWidget {
  final TrainingAction action;
  final DifficultyOption difficulty;
  final bool isDisplay; // 🖥️ 電視投放新增:true = 這台當電視顯示端
  final bool autoLevelUp;

  const TrainingScreen({
    super.key,
    required this.action,
    required this.difficulty,
    this.isDisplay = false, // 🖥️ 電視投放新增
    this.autoLevelUp = true,
  });

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

enum _PauseChoice { resume, end }

class _TrainingScreenState extends State<TrainingScreen>
    with TickerProviderStateMixin {
  late RehabSessionController _controller;

  // 🚀 樹莓派新增:是否使用外接來源、記住上次輸入的 IP
  bool _isExternalCamera = false;
  String? _lastPiIp;

  bool _isInitialized = false;
  bool _completionShown = false;

  // 是否正暫停中(暫停選單開啟期間為 true)
  bool _isPaused = false;

  bool _showingLevelUpOverlay = false; // 🆕
  bool _levelUpJustHandled = false; // 🆕 使用者剛按過按鈕,忽略接下來殘留的pending訊號
  final TextEditingController _levelUpRepsController =
      TextEditingController(); // 🆕

  // 停止錄影後、使用者尚未決定去留前的暫存路徑
  String? _pendingVideoPath;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  late AnimationController _slideCtrl;
  late Animation<Offset> _slideAnim;

  // 🖥️ 電視投放新增
  final _serverService = SocketServerService();
  final _clientService = SocketClientService();
  // final _rtcService = WebRtcService();
  // final _remoteRenderer = RTCVideoRenderer();
  StreamSubscription? _socketSub;
  final ValueNotifier<_RemoteHandState> _remoteState =
      ValueNotifier(const _RemoteHandState());

  bool get _showStickGuide => widget.action.type == ActionType.turnPalm;
  bool get _showPinchGuide => widget.action.type == ActionType.sidePinch;

  @override
  void initState() {
    super.initState();

    // 🖥️ 電視投放新增:顯示端不需要建立本機 controller / 相機資源。
    // 但為了盡量不動原本的建構流程與型別(late 欄位),仍建立一個
    // controller 物件,只是顯示端完全不會呼叫 _onSourceReady()/start()。
    _controller = _buildController(useExternal: false);

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));

    _listenController();

    // 🖥️ 電視投放新增:只有真的連了電視才初始化,沒連就完全跳過(省效能)
    final bool tvConnected =
        _clientService.isConnected || _serverService.isClientConnected;
    if (tvConnected) {
      // _initRtc();
      if (_clientService.isConnected) {
        _socketSub = _clientService.messages.listen(_handleRemoteCommand);
        // 🖥️ 接收端(電視)監聽影像 binary
        if (widget.isDisplay) {
          _clientService.binaryMessages.listen((data) {
            _remoteState.value = _remoteState.value.copyWith(imageBytes: data);
          });
        }
      } else if (_serverService.isClientConnected) {
        _socketSub = _serverService.messages.listen(_handleRemoteCommand);
        // 🖥️ 接收端(電視)監聽影像 binary
        if (widget.isDisplay) {
          _serverService.binaryMessages.listen((data) {
            _remoteState.value = _remoteState.value.copyWith(imageBytes: data);
          });
        }
      }
    }

    // 🖥️ 電視投放新增:控制端(手機)進訓練時,通知電視開對應的顯示端畫面
    if (!widget.isDisplay) {
      final startMsg = {
        'type': 'START_TRAINING',
        'actionName': widget.action.name,
        'difficultyLevel': widget.difficulty.level.name,
      };
      if (_clientService.isConnected) {
        _clientService.sendCommand(startMsg);
      } else if (_serverService.isClientConnected) {
        _serverService.sendMessage(startMsg);
      }
    }
  }

  // 🚀 樹莓派新增:依來源建立對應的 model + controller
  // ⚠️ 注意:RehabSessionController 建構子目前沒有 autoLevelUp 參數,
  // 手動/自動升級的判斷完全在下面 _listenController() 裡處理,
  // 這裡維持原樣,不要加 autoLevelUp: ... 進去(會編譯失敗)。
  RehabSessionController _buildController({
    required bool useExternal,
    String? ip,
  }) {
    final IPoseModel selectedModel =
        useExternal ? PiPoseModel(ip: ip!) : MediaPipeModel();

    return RehabSessionController(
      model: selectedModel,
      action: widget.action,
      difficulty: widget.difficulty,
    );
  }

  void _listenController() {
    _controller.stateStream.listen((state) {
      if (!mounted) return;
      setState(() {});

      // 🖥️ 電視投放新增:控制端把手部骨架 + 狀態傳給電視
      if (!widget.isDisplay &&
          (_clientService.isConnected || _serverService.isClientConnected)) {
        if (state.handLandmarks.isNotEmpty) {
          final poseMsg = {
            'type': 'HAND_POSE_UPDATE',
            'landmarks':
                state.handLandmarks.map((lm) => [lm.x, lm.y, lm.z]).toList(),
          };
          if (_clientService.isConnected) {
            _clientService.sendCommand(poseMsg);
          } else {
            _serverService.sendMessage(poseMsg);
          }
        }

        // 🖥️ 傳送影像資料 (JPEG)
        if (state.imageBytes != null) {
          if (_clientService.isConnected) {
            _clientService.sendBinary(state.imageBytes!);
          } else {
            _serverService.sendBinary(state.imageBytes!);
          }
        }

        final statusMsg = {
          'type': 'TRAINING_UPDATE',
          'repCount': state.repCount,
          'feedback': state.feedback,
          'instruction': state.instruction,
          'progress': state.progress,
          'speedState': state.speedState,
          'targetReps': state.targetReps,
          'isCountingDown': state.isCountingDown,
          'countdownSeconds': state.countdownSeconds,
        };
        if (_clientService.isConnected) {
          _clientService.sendCommand(statusMsg);
        } else {
          _serverService.sendMessage(statusMsg);
        }
      }

      if (state.pendingLevelUp &&
          !_showingLevelUpOverlay &&
          !_levelUpJustHandled) {
        if (widget.autoLevelUp) {
          _levelUpJustHandled = true; // 🆕 鎖住,避免同一次達標連續觸發好幾次confirmLevelUp
          _controller.confirmLevelUp();
          Future.delayed(const Duration(milliseconds: 500), () {
            _levelUpJustHandled = false; // 🆕 解鎖,讓下一次真正達標時能正常運作
          });
        } else {
          setState(() {
            _showingLevelUpOverlay = true;
            _levelUpRepsController.text = '${state.targetReps}';
          });
        }
      }

      if (state.isComplete && !_completionShown) {
        _completionShown = true;
        _handleCompletion(state);
      }
    });
  }

  // 🖥️ 電視投放新增:WebRTC 初始化(目前主要用於 signaling 通道,
  // 實際畫面/骨架資料走 Socket,跟 body_training_screen.dart 一致)
  Future<void> _initRtc() async {
    /* 🖥️ 改走 Socket JPEG 傳輸, 停用 WebRTC 視訊
    await _remoteRenderer.initialize();

    // 🖥️ 電視投放新增: 設置信令回傳,讓 WebRTC 能透過 Socket 完成連線握手
    _rtcService.onSignalingMessage = (signal) {
      final msg = {'type': 'RTC_SIGNAL', 'signal': signal};
      if (_clientService.isConnected) {
        _clientService.sendCommand(msg);
      } else if (_serverService.isClientConnected) {
        _serverService.sendMessage(msg);
      }
    };

    _rtcService.onRemoteStream.listen((stream) {
      if (mounted) setState(() => _remoteRenderer.srcObject = stream);
    });

    if (!widget.isDisplay) {
      // 控制端(手機): 開啟相機並傳輸串流 (captureVideo 改為 true)
      await _rtcService.init(isController: true, captureVideo: true);
    } else {
      // 顯示端(電視): 初始化為接收端
      await _rtcService.init(isController: false);
    }
    */
  }

  // 🖥️ 電視投放新增:顯示端收遠端指令
  void _handleRemoteCommand(Map<String, dynamic> msg) {
    if (!mounted || !widget.isDisplay) return;
    final type = msg['type'];

    if (type == 'HAND_POSE_UPDATE') {
      final rawLm = msg['landmarks'] as List;
      final landmarks = rawLm
          .map((e) => Landmark(
                (e[0] as num).toDouble(),
                (e[1] as num).toDouble(),
                (e[2] as num).toDouble(),
              ))
          .toList();
      _remoteState.value =
          _remoteState.value.copyWith(handLandmarks: landmarks);
    } else if (type == 'TRAINING_UPDATE') {
      final c = _remoteState.value;
      _remoteState.value = c.copyWith(
        repCount: msg['repCount'] ?? c.repCount,
        feedback: msg['feedback'] ?? c.feedback,
        instruction: msg['instruction'] ?? c.instruction,
        progress: (msg['progress'] as num?)?.toDouble() ?? c.progress,
        speedState: msg['speedState'] ?? c.speedState,
        targetReps: msg['targetReps'] ?? c.targetReps,
        isCountingDown: msg['isCountingDown'] ?? c.isCountingDown,
        countdownSeconds: msg['countdownSeconds'] ?? c.countdownSeconds,
      );
    } else if (type == 'RTC_SIGNAL') {
      // _rtcService.handleSignal(msg['signal']);
    } else if (type == 'STOP') {
      Navigator.of(context).pop();
    }
  }

  // 🚀 樹莓派新增:開啟外接鏡頭 → 詢問 IP → 換掉整個 controller
  Future<void> _enableExternalCamera() async {
    final ip = await showPiIpDialog(context, initialIp: _lastPiIp);
    if (ip == null || ip.isEmpty) return;
    _lastPiIp = ip;

    await _controller.disposeAsync();
    if (!mounted) return;

    setState(() {
      _isExternalCamera = true;
      _isInitialized = false;
      _controller = _buildController(useExternal: true, ip: ip);
    });
    _listenController();

    await _onSourceReady();
  }

  // 🚀 樹莓派新增:切回手機原生鏡頭 → 換掉整個 controller
  Future<void> _disableExternalCamera() async {
    await _controller.disposeAsync();
    if (!mounted) return;

    setState(() {
      _isExternalCamera = false;
      _isInitialized = false;
      _controller = _buildController(useExternal: false);
    });
    _listenController();

    await _onSourceReady();
  }

  // ── 切換畫面用:不做轉場動畫 ───────────────────────────────────
  void _pushReplacementNoAnimation(Widget screen) {
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) => screen,
    ));
  }

  Future<void> _onPlatformViewCreated() async {
    await _onSourceReady();
  }

  // 🚀 樹莓派新增:手機原生走 PlatformView callback 觸發,
  // 外接來源走 _enableExternalCamera/_disableExternalCamera 直接呼叫,
  // 統一走這個方法啟動 controller、標記 UI 就緒
  Future<void> _onSourceReady() async {
    await _controller.start();
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) setState(() => _isInitialized = true);

    if (!_isExternalCamera) {
      // 錄影是附加功能,失敗不應影響訓練本身;樹莓派模式暫不錄影
      ScreenRecorderService.startRecording();
    }
  }

  @override
  void dispose() {
    // 保險:如果畫面被意外關掉而沒有走到完整結束流程,錄影可能還在跑,
    // 這裡補一次停止並直接刪除暫存檔(視為不保留)。
    if (!widget.isDisplay && !_completionShown) {
      ScreenRecorderService.stopRecording().then((path) {
        if (path != null) {
          File(path).delete().catchError((e) => File(path));
        }
      });
    }
    // 🖥️ 電視投放新增
    _socketSub?.cancel();
    // _rtcService.dispose();
    // _remoteRenderer.dispose();
    _remoteState.dispose();

    _controller.dispose();
    _pulseCtrl.dispose();
    _slideCtrl.dispose();
    _levelUpRepsController.dispose(); // 🆕
    super.dispose();
  }

  Future<void> _flipCamera() async {
    // 🚀 樹莓派新增:外接來源時,這顆按鈕改為切回手機鏡頭
    if (_isExternalCamera) {
      await _disableExternalCamera();
      return;
    }
    await _controller.flipCamera();
    if (mounted) setState(() {});
  }

  Future<void> _handleCompletion(RehabSessionState state) async {
    _pendingVideoPath = await ScreenRecorderService.stopRecording();

    // ✅ 新增:用 currentLevel 去查出真正對應的 DifficultyOption
    final levelIdx = state.currentLevel - 1;
    final displayDifficulty =
        (levelIdx >= 0 && levelIdx < widget.action.difficulties.length)
            ? widget.action.difficulties[levelIdx]
            : widget.difficulty;

    final result = await showDialog<_CompletionResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => CompletionDialog(
        repCount: state.repCount,
        durationSeconds: state.durationSeconds,
        mistakeLogs: state.mistakeLogs,
        currentAction: widget.action,
        //currentDifficulty: widget.difficulty,
        currentDifficulty: displayDifficulty, // ✅ 改這行(原本是 widget.difficulty)
        hasVideo: _pendingVideoPath != null,
        onVideoDecision: _handleVideoDecision,
        onRetry: () => Navigator.of(dialogCtx).pop(_CompletionResult.retry()),
        onHome: () => Navigator.of(dialogCtx).pop(_CompletionResult.home()),
        onStartNew: (a, d, autoLvl) => // 🆕 3 參數,對齊 completion_dialog.dart
            Navigator.of(dialogCtx)
                .pop(_CompletionResult.startNew(a, d, autoLvl)),
      ),
    );

    // 儲存紀錄(此時 _pendingVideoPath 已經依照使用者的保留/不保留決定更新過)
    HistoryService().saveRecord(TrainingRecord(
      timestamp: DateTime.now().toString().substring(0, 16),
      actionName: widget.action.name,
      //difficulty: widget.action.difficulties.indexOf(widget.difficulty) + 1,
      difficulty: widget.action.difficulties
              .indexWhere((d) => d.level == widget.difficulty.level) +
          1,
      durationSeconds: state.durationSeconds,
      mistakeLogs: state.mistakeLogs,
      videoPath: _pendingVideoPath,
      targetReps: widget.difficulty.targetReps, // ✅ 新增這行，兩處都加
    ));

    // ✅ 新增:順便檢查今天計畫裡有沒有這個動作,有就標記完成
    await markPlanItemDoneByActionName(widget.action.name);

    if (!mounted || result == null) return;

    switch (result.kind) {
      case _CompletionKind.retry:
        _pushReplacementNoAnimation(TrainingScreen(
          action: widget.action,
          difficulty: widget.difficulty,
          autoLevelUp: widget.autoLevelUp, // 🆕 沿用原本畫面的設定
        ));
        break;
      case _CompletionKind.home:
        Navigator.of(context).pop();
        break;
      case _CompletionKind.startNew:
        _navigateToAction(
            result.action!, result.difficulty!, result.autoLevelUp!); // 🆕
        break;
    }
  }

  void _confirmLevelUp() {
    _levelUpJustHandled = true; // 🆕 鎖住,避免殘留訊號重新跳出視窗
    final customReps = int.tryParse(_levelUpRepsController.text);
    _controller.confirmLevelUp(
      customTargetReps:
          (customReps != null && customReps > 0) ? customReps : null,
    );
    setState(() => _showingLevelUpOverlay = false);

    // 短暫延遲後解鎖,讓下一次真正的達標訊號可以正常運作
    Future.delayed(const Duration(milliseconds: 500), () {
      _levelUpJustHandled = false;
    });
  }

  void _declineLevelUp() {
    _levelUpJustHandled = true; // 🆕
    _controller.declineLevelUp();
    setState(() => _showingLevelUpOverlay = false);

    Future.delayed(const Duration(milliseconds: 500), () {
      _levelUpJustHandled = false;
    });
  }

  // ─── 按停止鍵觸發:先跳「暫停選單」,不動任何狀態或錄影 ─────────
  Future<void> _handleStopButtonTap() async {
    if (_completionShown || !_isInitialized || _isPaused) return;

    setState(() => _isPaused = true);
    _controller.pause();

    final choice = await showDialog<_PauseChoice>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => _PauseMenuDialog(
        onResume: () => Navigator.of(dialogCtx).pop(_PauseChoice.resume),
        onEnd: () => Navigator.of(dialogCtx).pop(_PauseChoice.end),
      ),
    );

    if (!mounted) return;

    if (choice != _PauseChoice.end) {
      // 選「繼續」,或用其他方式關掉選單(一律視為繼續)
      _controller.resume();
      setState(() => _isPaused = false);
      return;
    }

    // 選「結束」→ 進入原本的完整結束流程
    await _handleRealEnd();
  }

  // ─── 真正的結束流程(停止錄影、存紀錄、跳完成 dialog)─────
  Future<void> _handleRealEnd() async {
    _completionShown = true;

    final state = _controller.currentState;
    _pendingVideoPath = await ScreenRecorderService.stopRecording();

    // ✅ 新增:算出真正要顯示的難度
    final levelIdx = state.currentLevel - 1;
    final displayDifficulty =
        (levelIdx >= 0 && levelIdx < widget.action.difficulties.length)
            ? widget.action.difficulties[levelIdx]
            : widget.difficulty;

    final result = await showDialog<_CompletionResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => CompletionDialog(
        isPaused: false,
        repCount: state.repCount,
        durationSeconds: state.durationSeconds,
        mistakeLogs: state.mistakeLogs,
        currentAction: widget.action,
        //currentDifficulty: widget.difficulty,
        currentDifficulty: displayDifficulty, // ✅ 改這行
        hasVideo: _pendingVideoPath != null,
        onVideoDecision: _handleVideoDecision,
        onRetry: () => Navigator.of(dialogCtx).pop(_CompletionResult.retry()),
        onHome: () => Navigator.of(dialogCtx).pop(_CompletionResult.home()),
        onStartNew: (a, d, autoLvl) => // 🆕 3 參數,對齊 completion_dialog.dart
            Navigator.of(dialogCtx)
                .pop(_CompletionResult.startNew(a, d, autoLvl)),
      ),
    );

    HistoryService().saveRecord(TrainingRecord(
      timestamp: DateTime.now().toString().substring(0, 16),
      actionName: widget.action.name,
      //difficulty: widget.action.difficulties.indexOf(widget.difficulty) + 1,
      difficulty: widget.action.difficulties
              .indexWhere((d) => d.level == widget.difficulty.level) +
          1,
      durationSeconds: state.durationSeconds,
      mistakeLogs: state.mistakeLogs,
      videoPath: _pendingVideoPath,
      targetReps: widget.difficulty.targetReps, // ✅ 新增這行，兩處都加
    ));

    // ✅ 新增:順便檢查今天計畫裡有沒有這個動作,有就標記完成
    await markPlanItemDoneByActionName(widget.action.name);

    if (!mounted || result == null) return;

    switch (result.kind) {
      case _CompletionKind.retry:
        _pushReplacementNoAnimation(TrainingScreen(
          action: widget.action,
          difficulty: widget.difficulty,
          autoLevelUp: widget.autoLevelUp, // 🆕 沿用原本畫面的設定
        ));
        break;
      case _CompletionKind.home:
        Navigator.of(context).pop();
        break;
      case _CompletionKind.startNew:
        _navigateToAction(
            result.action!, result.difficulty!, result.autoLevelUp!); // 🆕
        break;
    }
  }

  // dialog 裡使用者選「保留/不保留」時呼叫;不保留就把暫存檔刪掉
  void _handleVideoDecision(bool keep) {
    if (!keep && _pendingVideoPath != null) {
      final path = _pendingVideoPath!;
      _pendingVideoPath = null;
      File(path).delete().catchError((e) => File(path));
    }
  }

  /// 根據動作類型導航到對應畫面
  /// 🆕 加上 autoLevelUp 參數,把使用者換動作時選的升級模式一併帶過去
  Future<void> _navigateToAction(TrainingAction action,
      DifficultyOption difficulty, bool autoLevelUp) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    await _controller.disposeAsync();
    if (!mounted) return;

    Widget screen;
    final diff = _mapDifficulty(difficulty.level);
    switch (action.type) {
      case ActionType.wipeBody:
        screen = BodyTrainingScreen(
          action: StandingKneeRaiseAction(
              difficulty: diff, targetCount: difficulty.targetReps),
          trainingActionMeta: action,
          difficultyMeta: difficulty,
          autoLevelUp: autoLevelUp, // 🆕
        );
      case ActionType.drawCircle:
        screen = BodyTrainingScreen(
          action: DrawCircleAction(
              difficulty: diff, targetCount: difficulty.targetReps),
          trainingActionMeta: action,
          difficultyMeta: difficulty,
          autoLevelUp: autoLevelUp, // 🆕
        );
      case ActionType.reach:
        screen = BodyTrainingScreen(
          action:
              ReachAction(difficulty: diff, targetCount: difficulty.targetReps),
          trainingActionMeta: action,
          difficultyMeta: difficulty,
          autoLevelUp: autoLevelUp, // 🆕
        );
      case ActionType.raiseBothArms:
        screen = BodyTrainingScreen(
          action: RaiseBothArmsAction(
              difficulty: diff, targetCount: difficulty.targetReps),
          trainingActionMeta: action,
          difficultyMeta: difficulty,
          autoLevelUp: autoLevelUp, // 🆕
        );
      case ActionType.elbowForward:
        screen = BodyTrainingScreen(
          action: ElbowForwardAction(
              difficulty: diff, targetCount: difficulty.targetReps),
          trainingActionMeta: action,
          difficultyMeta: difficulty,
          autoLevelUp: autoLevelUp, // 🆕
        );
      case ActionType.sitToStand: // 🆕 補上,原本漏掉
        screen = BodyTrainingScreen(
          action: SitToStandAction(
              difficulty: diff, targetCount: difficulty.targetReps),
          trainingActionMeta: action,
          difficultyMeta: difficulty,
          autoLevelUp: autoLevelUp,
        );
      case ActionType.lateralStep: // 🆕 補上,原本漏掉
        screen = BodyTrainingScreen(
          action: LateralStepAction(
              difficulty: diff, targetCount: difficulty.targetReps),
          trainingActionMeta: action,
          difficultyMeta: difficulty,
          autoLevelUp: autoLevelUp,
        );
      default:
        screen = TrainingScreen(
          action: action,
          difficulty: difficulty,
          autoLevelUp: autoLevelUp, // 🆕
        );
    }

    if (!mounted) return;
    _pushReplacementNoAnimation(screen);
  }

  RehabDifficulty _mapDifficulty(DifficultyLevel level) {
    switch (level) {
      case DifficultyLevel.level1:
        return RehabDifficulty.easy;
      case DifficultyLevel.level2:
        return RehabDifficulty.medium;
      case DifficultyLevel.level3:
        return RehabDifficulty.hard;
    }
  }

  // 🚀 新增:取得樹莓派來源目前這一幀的原始尺寸,給 HandOverlayWidget
  // 用來算 BoxFit.cover 的縮放/裁切偏移。手機鏡頭模式回傳 null,
  // HandOverlayPainter 收到 null 時會維持原本(未受影響)的行為。
  Size? _currentPiSourceSize() {
    if (!_isExternalCamera) return null;
    final model = _controller.currentModel;
    if (model is! PiPoseModel) return null;
    return model.debugSource?.frameSize.value;
  }

  @override
  Widget build(BuildContext context) {
    // 🖥️ 電視投放新增:顯示端走完全不同的簡化畫面,
    // 不開相機、不跑 controller,只讀遠端資料。
    if (widget.isDisplay) {
      return _buildDisplayScaffold();
    }

    final s = _controller.currentState;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFFFFFFF),
          body: SafeArea(
            child: Column(
              children: [
                _TrainingTopBarWithPi(
                  actionName: widget.action.name,
                  difficultyDesc: s.currentLevelLabel.isNotEmpty
                      ? s.currentLevelLabel
                      : widget.difficulty.description,
                  onBack: () => Navigator.of(context).pop(),
                  onFlipCamera: _flipCamera,
                  isExternalCamera: _isExternalCamera,
                  onTogglePi: _isExternalCamera
                      ? _disableExternalCamera
                      : _enableExternalCamera,
                ),
                AspectRatio(
                  aspectRatio: 3 / 4,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // 🚀 樹莓派新增:外接來源時顯示 Pi 傳來的 JPEG 畫面
                          if (_isExternalCamera)
                            _PiHandVideoView(controller: _controller)
                          else
                            PlatformViewLink(
                              viewType: 'com.rehabassist/camera_preview',
                              surfaceFactory: (context, controller) {
                                return AndroidViewSurface(
                                  controller:
                                      controller as AndroidViewController,
                                  gestureRecognizers: const {},
                                  hitTestBehavior:
                                      PlatformViewHitTestBehavior.opaque,
                                );
                              },
                              onCreatePlatformView: (params) {
                                final ctrl = PlatformViewsService
                                    .initExpensiveAndroidView(
                                  id: params.id,
                                  viewType: 'com.rehabassist/camera_preview',
                                  layoutDirection: TextDirection.ltr,
                                  onFocus: () => params.onFocusChanged(true),
                                );
                                ctrl.addOnPlatformViewCreatedListener(
                                    params.onPlatformViewCreated);
                                ctrl.addOnPlatformViewCreatedListener(
                                    (_) => _onPlatformViewCreated());
                                ctrl.create();
                                return ctrl;
                              },
                            ),
                          if (s.handLandmarks.isNotEmpty)
                            HandOverlayWidget(
                              landmarks: s.handLandmarks,
                              isMirrored: false,
                              showStickGuide: _showStickGuide && !s.isComplete,
                              showPinchGuide: _showPinchGuide && !s.isComplete,
                              progress: s.progress,
                              speedState: s.speedState,
                              // 🚀 新增:樹莓派模式下傳入原始 JPEG 尺寸,
                              // 讓骨架點位跟 Image.memory(fit: BoxFit.cover)
                              // 的裁切/縮放對齊。手機鏡頭維持 null 不受影響。
                              sourceSize: _currentPiSourceSize(),
                            ),
                          if (!_isInitialized) const LoadingOverlay(),
                          if (_isInitialized &&
                              !s.handDetected &&
                              s.handLandmarks.isEmpty)
                            NoHandOverlay(pulseAnim: _pulseAnim),
                          if (s.isCountingDown && !s.countdownDone)
                            CountdownOverlay(seconds: s.countdownSeconds),
                          if (_isPaused)
                            Container(
                              color: Colors.black.withOpacity(0.4),
                              child: const Center(
                                child: Text(
                                  '⏸ 已暫停',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    shadows: [
                                      Shadow(blurRadius: 8, color: Colors.black)
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                CoachCard(
                  feedback: s.feedback,
                  instruction: s.instruction,
                ),
                SlideTransition(
                  position: _slideAnim,
                  child: TrainingStatsPanel(
                    isCountingDown: s.isCountingDown,
                    countdownDone: s.countdownDone,
                    countdownSeconds: s.countdownSeconds,
                    actionType: widget.action.type,
                    repCount: s.repCount,
                    targetReps: s.targetReps, // ← 新增
                    accuracy: s.accuracy,
                    onStopPressed: _handleStopButtonTap,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_showingLevelUpOverlay) _buildLevelUpOverlay(), // 🆕
      ],
    );
  }

  Widget _buildLevelUpOverlay() {
    final s = _controller.currentState;
    return Material(
      color: Colors.transparent,
      child: Positioned.fill(
        child: Container(
          color: Colors.black54,
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🎉', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 10),
                  const Text(
                    '動作做得很棒！',
                    style: TextStyle(
                      color: Color(0xFF1A1D2E),
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '要挑戰下一階「${s.pendingNextLevelLabel}」嗎？',
                    style:
                        const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        '下一階要做幾下',
                        style: TextStyle(
                            color: Color(0xFF374151),
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 56,
                        child: TextField(
                          controller: _levelUpRepsController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1A1D2E)),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 8),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: Color(0xFFDDE0F0)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: Color(0xFF4A65FF)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text('下',
                          style: TextStyle(
                              color: Color(0xFF6B7280), fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _confirmLevelUp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4A65FF),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text(
                        '💪 挑戰下一階',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      onPressed: _declineLevelUp,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFDDE0F0)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text(
                        '結束訓練',
                        style: TextStyle(
                            color: Color(0xFF374151),
                            fontSize: 15,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 🖥️ 電視投放新增:顯示端(電視)畫面。
  // 不開相機、不跑 RehabSessionController,只讀 _remoteState
  // 並用 HandOverlayWidget 畫出手部骨架(黑底,無真人畫面)。
  Widget _buildDisplayScaffold() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: ValueListenableBuilder<_RemoteHandState>(
          valueListenable: _remoteState,
          builder: (_, remote, __) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.action.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: Colors.green.withOpacity(0.4)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.link, color: Colors.green, size: 14),
                            SizedBox(width: 4),
                            Text(
                              '正在接收',
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        color: const Color(0xFF161824),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // 🖥️ 顯示遠端手機鏡頭畫面 (Socket JPEG 模式)
                            if (remote.imageBytes != null)
                              Image.memory(
                                remote.imageBytes!,
                                gaplessPlayback: true,
                                fit: BoxFit.cover,
                              )
                            else if (remote.handLandmarks.isNotEmpty)
                              const Center(
                                child: CircularProgressIndicator(
                                    color: Color(0xFF4A65FF)),
                              ),
                            if (remote.handLandmarks.isNotEmpty)
                              HandOverlayWidget(
                                landmarks: remote.handLandmarks,
                                progress: remote.progress,
                                speedState: remote.speedState,
                              )
                            else
                              const Center(
                                child: CircularProgressIndicator(
                                    color: Color(0xFF4A65FF)),
                              ),
                            if (remote.isCountingDown)
                              CountdownOverlay(
                                  seconds: remote.countdownSeconds),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                CoachCard(
                  feedback: remote.feedback,
                  instruction: remote.instruction,
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '${remote.repCount} / ${remote.targetReps}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// 🖥️ 電視投放新增:顯示端用來裝遠端手部狀態的容器
class _RemoteHandState {
  final List<Landmark> handLandmarks;
  final Uint8List? imageBytes; // 🚀 新增
  final String feedback;
  final String instruction;
  final int repCount;
  final int targetReps;
  final double progress;
  final int speedState;
  final bool isCountingDown;
  final int countdownSeconds;

  const _RemoteHandState({
    this.handLandmarks = const [],
    this.imageBytes, // 🚀 新增
    this.feedback = '等待連線中...',
    this.instruction = '',
    this.repCount = 0,
    this.targetReps = 10,
    this.progress = 0,
    this.speedState = 0,
    this.isCountingDown = false,
    this.countdownSeconds = 0,
  });

  _RemoteHandState copyWith({
    List<Landmark>? handLandmarks,
    Uint8List? imageBytes, // 🚀 新增
    String? feedback,
    String? instruction,
    int? repCount,
    int? targetReps,
    double? progress,
    int? speedState,
    bool? isCountingDown,
    int? countdownSeconds,
  }) {
    return _RemoteHandState(
      handLandmarks: handLandmarks ?? this.handLandmarks,
      imageBytes: imageBytes ?? this.imageBytes, // 🚀 新增
      feedback: feedback ?? this.feedback,
      instruction: instruction ?? this.instruction,
      repCount: repCount ?? this.repCount,
      targetReps: targetReps ?? this.targetReps,
      progress: progress ?? this.progress,
      speedState: speedState ?? this.speedState,
      isCountingDown: isCountingDown ?? this.isCountingDown,
      countdownSeconds: countdownSeconds ?? this.countdownSeconds,
    );
  }
}

// 🚀 樹莓派新增:外接來源時顯示的畫面 widget
// 直接從 controller 目前的 model 拿 PiPoseModel 底層的 latestJpeg,
// 需要向下轉型,只有在 _isExternalCamera 為 true 時才會被 build,
// 此時 model 一定是 PiPoseModel,轉型安全
class _PiHandVideoView extends StatelessWidget {
  final RehabSessionController controller;
  const _PiHandVideoView({required this.controller});

  @override
  Widget build(BuildContext context) {
    final model = controller.currentModel;
    if (model is! PiPoseModel) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: CircularProgressIndicator(
              color: Color(0xFF00BCD4), strokeWidth: 3),
        ),
      );
    }
    final source = model.debugSource;
    if (source == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: CircularProgressIndicator(
              color: Color(0xFF00BCD4), strokeWidth: 3),
        ),
      );
    }
    return ValueListenableBuilder<Uint8List?>(
      valueListenable: source.latestJpeg,
      builder: (_, jpeg, __) {
        if (jpeg == null) {
          return const ColoredBox(
            color: Colors.black,
            child: Center(
              child: CircularProgressIndicator(
                  color: Color(0xFF00BCD4), strokeWidth: 3),
            ),
          );
        }
        return Image.memory(jpeg, fit: BoxFit.cover, gaplessPlayback: true);
      },
    );
  }
}

// 🚀 樹莓派新增:包一層 TrainingTopBar,額外加攝影機切換鈕(跟身體畫面一致的位置/樣式)
class _TrainingTopBarWithPi extends StatelessWidget {
  final String actionName;
  final String difficultyDesc;
  final VoidCallback onBack;
  final VoidCallback onFlipCamera;
  final bool isExternalCamera;
  final VoidCallback onTogglePi;

  const _TrainingTopBarWithPi({
    required this.actionName,
    required this.difficultyDesc,
    required this.onBack,
    required this.onFlipCamera,
    required this.isExternalCamera,
    required this.onTogglePi,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F6FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDDE0F0)),
              ),
              child: const Icon(Icons.arrow_back_ios_new,
                  color: Color(0xFF374151), size: 16),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  actionName,
                  style: const TextStyle(
                    color: Color(0xFF1A1D2E),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  difficultyDesc,
                  style:
                      const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
                ),
              ],
            ),
          ),
          // 🚀 樹莓派新增:外接鏡頭開關按鈕
          GestureDetector(
            onTap: onTogglePi,
            child: Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: isExternalCamera
                    ? const Color(0xFF4A65FF)
                    : const Color(0xFFF5F6FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDDE0F0)),
              ),
              child: Icon(
                Icons.videocam,
                color:
                    isExternalCamera ? Colors.white : const Color(0xFF374151),
                size: 20,
              ),
            ),
          ),
          GestureDetector(
            onTap: onFlipCamera,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F6FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDDE0F0)),
              ),
              child: const Icon(Icons.flip_camera_ios,
                  color: Color(0xFF374151), size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 暫停選單 dialog:只有「繼續」跟「結束」兩個選項 ──────────────
class _PauseMenuDialog extends StatelessWidget {
  final VoidCallback onResume;
  final VoidCallback onEnd;

  const _PauseMenuDialog({
    required this.onResume,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('⏸️', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 10),
            const Text(
              '訓練已暫停',
              style: TextStyle(
                color: Color(0xFF1A1D2E),
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '要接續剛剛的訓練,還是結束呢?',
              style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: onResume,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A65FF),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text(
                  '▶️ 繼續訓練',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: onEnd,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFDDE0F0)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text(
                  '結束訓練',
                  style: TextStyle(
                      color: Color(0xFFFF4B4B),
                      fontSize: 15,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _CompletionKind { retry, home, startNew }

class _CompletionResult {
  final _CompletionKind kind;
  final TrainingAction? action;
  final DifficultyOption? difficulty;
  final bool? autoLevelUp; // 🆕
  const _CompletionResult._(
      this.kind, this.action, this.difficulty, this.autoLevelUp);
  factory _CompletionResult.retry() =>
      const _CompletionResult._(_CompletionKind.retry, null, null, null);
  factory _CompletionResult.home() =>
      const _CompletionResult._(_CompletionKind.home, null, null, null);
  factory _CompletionResult.startNew(
          TrainingAction a, DifficultyOption d, bool autoLevelUp) => // 🆕
      _CompletionResult._(_CompletionKind.startNew, a, d, autoLevelUp);
}
