// lib/features/rehab/body_training_screen.dart
//
// ══════════════════════════════════════════════════════════════════
//  全身復健「共用畫面殼」
//  🚀 支援切換鏡頭來源(手機內建 / 樹莓派外接)
//  🚀 樹莓派模式下,手部骨架改走樹莓派偵測(PiHandSource),
//     與身體骨架共用同一套座標映射方式,確保兩者貼合對齊
//  🚀 修正:_SkeletonPainter / _PiHandSkeletonPainter 加上 sourceSize,
//     讓骨架點位能跟 Image.memory(fit: BoxFit.cover) 的裁切/縮放對齊。
//     原本座標是 landmark 的 0~1 正規化值直接乘容器尺寸,但畫面顯示時
//     用 BoxFit.cover 把原始 JPEG(長寬比通常跟容器不同)裁切填滿容器,
//     兩套邏輯沒有對齊,骨架才會貼不上身體/手指。
//     手機鏡頭(CameraPreview)路徑完全不傳 sourceSize,行為不受影響。
//
//  🆕 2026-08-22:換動作時把 autoLevelUp 一併帶到下一個畫面
//     - CompletionDialog 的 onStartNew 簽名擴充為 (action, difficulty, autoLevelUp)
//     - retry / startNew 都改用「當時使用者選的」autoLevelUp,
//       不再一律沿用 widget.autoLevelUp
//     - _navigateToAction 多一個 autoLevelUp 參數,並把方法內所有
//       widget.autoLevelUp 改成新參數 autoLevelUp
// ══════════════════════════════════════════════════════════════════

import 'dart:io';
import 'dart:typed_data'; // 用到 Uint8List
import 'dart:ui' show Size; // 🚀 新增:骨架對齊用
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../models/pose_data.dart';
import '../../models/body_frame.dart';
import '../../models/training_action.dart';
import '../../services/body_pose_engine.dart';
import '../../services/history_service.dart';
import '../../services/screen_recorder_service.dart';
import '../../services/pi_camera_source.dart'; // 🚀 樹莓派新增
import '../../services/pi_hand_source.dart'; // 🚀 樹莓派手部新增
import '../../services/mediapipe_service.dart'; // 🚀 樹莓派手部新增(Landmark/DetectionResult/MediaPipeService)
import '../../widgets/pi_ip_dialog.dart'; // 🚀 樹莓派新增
import '../../actions/body_rehab_action.dart';
import '../../actions/standing_knee_raise_action.dart';
import '../../actions/draw_circle_action.dart';
import '../../actions/reach_action.dart';
import '../../widgets/completion_dialog.dart';
import 'training_screen.dart';

import '../../services/voice_service.dart';
import '../../actions/raise_both_arms_action.dart';
import '../../actions/elbow_forward_action.dart';
import '../../actions/sit_to_stand_action.dart';
import '../../actions/lateral_step_action.dart';
import '../../features/plan/plan_repository.dart';

// 🖥️ 電視投放新增
import 'dart:async';
//import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../features/tv_cast/webrtc_service.dart';
import '../../features/tv_cast/socket_server_service.dart';
import '../../features/tv_cast/socket_client_service.dart';
import '../../controllers/rehab_session_controller.dart';

// 達標下限:當前難度做 ≥ 3 下,按結束才會存紀錄
const int _kMinRepsToSave = 3;

// RTMPose 133 點 → RehabJoint 對應表
const Map<RehabJoint, int> _kJointIndex = {
  RehabJoint.leftShoulder: 5,
  RehabJoint.rightShoulder: 6,
  RehabJoint.leftElbow: 7,
  RehabJoint.rightElbow: 8,
  RehabJoint.leftWrist: 9,
  RehabJoint.rightWrist: 10,
  RehabJoint.leftHip: 11,
  RehabJoint.rightHip: 12,
  RehabJoint.leftKnee: 13,
  RehabJoint.rightKnee: 14,
  RehabJoint.leftAnkle: 15,
  RehabJoint.rightAnkle: 16,
};

const _skeletonConnections = [
  [0, 1], [0, 2], [1, 3], [2, 4],
  [5, 6], [5, 7], [7, 9], [6, 8], [8, 10],
  [5, 11], [6, 12], [11, 12],
  [11, 13], [13, 15], [12, 14], [14, 16],
];

class BodyTrainingScreen extends StatefulWidget {
  final BodyRehabAction action;

  final TrainingAction? trainingActionMeta;
  final DifficultyOption? difficultyMeta;

  final bool isDisplay; // 🖥️ 電視投放新增:true = 這台當電視顯示端
  final bool autoLevelUp; // 🆕 true=自動升級(舊行為), false=跳出詢問讓使用者決定

  const BodyTrainingScreen({
    super.key,
    required this.action,
    this.trainingActionMeta,
    this.difficultyMeta,
    this.isDisplay = false, // 🖥️ 電視投放新增
    this.autoLevelUp = true, // 🆕 預設 true,不影響現在其他呼叫這個畫面的地方
  });

  @override
  State<BodyTrainingScreen> createState() => _BodyTrainingScreenState();
}

enum _PauseChoice { resume, end }

class _BodyTrainingScreenState extends State<BodyTrainingScreen> {
  final BodyPoseEngine _engine = BodyPoseEngine();
  static const double _scoreThreshold = BodyPoseEngine.scoreThreshold;

  // 🚀 樹莓派新增:外接鏡頭來源(null = 尚未連線)
  PiCameraSource? _piCamera;
  bool _isExternalCamera = false;
  String? _lastPiIp;

  // 🚀 樹莓派手部偵測新增:另開一條連線拿手部 landmarks
  final MediaPipeService _handService = MediaPipeService();
  PiHandSource? _piHand;

  // 🖥️ 電視投放新增
  final _serverService = SocketServerService();
  final _clientService = SocketClientService();
  final _rtcService = WebRtcService();
  final _remoteRenderer = RTCVideoRenderer();
  StreamSubscription? _socketSub;
  final ValueNotifier<RehabSessionState> _remoteState =
      ValueNotifier(const RehabSessionState());

  int _repCount = 0;
  String _feedback = '請將身體放入鏡頭範圍內';
  late String _instruction;
  bool _bodyVisible = false;

  final DateTime _sessionStart = DateTime.now();
  bool _completionShown = false;

  bool _isPaused = false;

  int _recordsSavedThisSession = 0;

  bool _recordingStarted = false;
  
  bool _levelUpDialogShowing = false;
  bool _hasNextLevel = false;          // 🆕
  String _nextLevelLabel = '';         // 🆕
  final TextEditingController _levelUpRepsController = TextEditingController();         // 🆕

  DateTime _currentLevelStart = DateTime.now();
  int _currentLevelReps = 0;
  RehabDifficulty _previousLevel = RehabDifficulty.easy;

  bool get _waitingHandSelect =>
      widget.action is ReachAction &&
      !(widget.action as ReachAction).handSelected;

  @override
  void initState() {
    super.initState();
    _instruction = widget.action.initialHint;
    _previousLevel = _mapDifficulty(
      widget.difficultyMeta?.level ?? DifficultyLevel.level1,
    );
    VoiceService.init();
    _start();

    // 🖥️ 電視投放:只有真的連了電視才初始化,沒連就完全跳過(省效能)
    final bool _tvConnected =
        _clientService.isConnected || _serverService.isClientConnected;
    if (_tvConnected) {
      _initRtc();
      if (_clientService.isConnected) {
        _socketSub = _clientService.messages.listen(_handleRemoteCommand);
      } else if (_serverService.isClientConnected) {
        _socketSub = _serverService.messages.listen(_handleRemoteCommand);
      }
    }

    // 🖥️ 電視投放新增:控制端進訓練時,通知電視開對應的顯示端畫面
    if (!widget.isDisplay) {
      final startMsg = {
        'type': 'START_TRAINING',
        'actionName': widget.trainingActionMeta?.name ?? widget.action.title,
        'difficultyLevel': widget.difficultyMeta?.level.name ?? 'level1',
      };
      if (_clientService.isConnected) {
        _clientService.sendCommand(startMsg);
      } else if (_serverService.isClientConnected) {
        _serverService.sendMessage(startMsg);
      }
    }
  }

  /*Future<void> _start() async {
    await _engine.init();
    if (!mounted) return;
    setState(() {});
    await _engine.startCamera();
    _engine.poseNotifier.addListener(_onPoseUpdate);

    if (!_recordingStarted) {
      _recordingStarted = true;
      ScreenRecorderService.startRecording();
    }
  }*/

  Future<void> _start() async {
    // 🖥️ 電視投放新增:顯示端不開相機、不載模型,只吃遠端資料
    await _engine.init(asReceiver: widget.isDisplay);
    if (!mounted) return;
    setState(() {});
    if (widget.isDisplay) return; // 🖥️ 顯示端到此為止

    await _engine.startCamera();
    _engine.poseNotifier.addListener(_onPoseUpdate); // ← 偵測核心,補回來
    // 🖥️ 電視投放:只有連了電視的控制端才傳畫面,沒連不生成 JPEG(省效能)
    if (_clientService.isConnected || _serverService.isClientConnected) {
      _engine.imageNotifier.addListener(_onImageUpdate);
      _engine.castEnabled = true;
    }

    if (!_recordingStarted) {
      _recordingStarted = true;
      ScreenRecorderService.startRecording();
    }
  }

  void _onPoseUpdate() {
    if (_isPaused) return;

    final data = _engine.poseNotifier.value;
    if (data.keypoints.length < BodyPoseEngine.numKpts) return;

    final joints = <RehabJoint, Offset>{};
    _kJointIndex.forEach((joint, idx) {
      joints[joint] = data.keypoints[idx];
    });
    final frame = BodyFrame(joints: joints);

    final visible = data.scores[5] > _scoreThreshold &&
        data.scores[6] > _scoreThreshold;

    final fb = widget.action.update(frame);

    bool justReachedLevelUp = false;

    if (mounted) {
      setState(() {
        _bodyVisible = visible;
        if (fb.scored) {
          _repCount++;
          _currentLevelReps++;
        }
        if (fb.prompt != null) _feedback = fb.prompt!;

        if (fb.leveledUp) {
          justReachedLevelUp = true;
        }
      });

      // 🆕 達標了 → 依照 autoLevelUp 開關決定「自動升級」還是「跳出詢問」
      if (justReachedLevelUp) {
        final action = widget.action;
        final controllable =
            action is LevelUpControllable ? action as LevelUpControllable : null;

                if (widget.autoLevelUp) {
          // 先判斷目前這階之後還有沒有下一階(跟手動模式同一套算法)
          final currentMeta = widget.trainingActionMeta ??
              kTrainingActions.firstWhere(
                (a) => a.name == widget.action.title,
                orElse: () => kTrainingActions.first,
              );
          final currentLevelIdx = _levelToInt(_previousLevel) - 1;
          final hasNextLevel = currentLevelIdx >= 0 &&
              currentLevelIdx + 1 < currentMeta.difficulties.length;

          if (hasNextLevel) {
            // 還有下一階 → 自動升級(原本的行為)
            controllable?.confirmLevelUp(); // 真正解凍並套用新難度
            setState(() {
              _saveCurrentLevelRecord();
              _previousLevel = _nextLevel(_previousLevel);
              _currentLevelStart = DateTime.now();
              _currentLevelReps = 0;
              _instruction = '難度提升,請繼續保持';
            });
          } else {
            // 已經是最高難度 → 自動結束整場訓練
            // (最後這階的紀錄會由 _handleRealEnd 內的 _saveCurrentLevelRecord 存)
            setState(() => _isPaused = true); // 擋掉後續 pose frame,避免重複進結束流程
            _handleRealEnd();
          }
        } else if (!_levelUpDialogShowing) {
          _handleLevelUpDetected();
        }
      }

      // 🖥️ 電視投放新增:控制端把骨架+狀態傳給電視
      if (_clientService.isConnected || _serverService.isClientConnected) {
        final poseMsg = {
          'type': 'POSE_UPDATE',
          'keypoints': data.keypoints.map((e) => [e.dx, e.dy]).toList(),
          'scores': data.scores,
        };
        final statusMsg = {
          'type': 'TRAINING_UPDATE',
          'repCount': _repCount,
          'feedback': _feedback,
          'instruction': _instruction,
        };
        if (_clientService.isConnected) {
          _clientService.sendCommand(poseMsg);
          _clientService.sendCommand(statusMsg);
        } else {
          _serverService.sendMessage(poseMsg);
          _serverService.sendMessage(statusMsg);
        }
      }

      if (fb.prompt != null) {
        VoiceService.speak(fb.prompt!);
      }
    }
  }

  // 🖥️ 電視投放新增:WebRTC + binary(JPEG)接收
  Future<void> _initRtc() async {
    await _remoteRenderer.initialize();
    _rtcService.onRemoteStream.listen((stream) {
      if (mounted) setState(() => _remoteRenderer.srcObject = stream);
    });

    if (_clientService.isConnected) {
      _clientService.binaryMessages.listen((data) {
        if (mounted && widget.isDisplay) _engine.imageNotifier.value = data;
      });
    } else if (_serverService.isClientConnected) {
      _serverService.binaryMessages.listen((data) {
        if (mounted && widget.isDisplay) _engine.imageNotifier.value = data;
      });
    }

    if (!widget.isDisplay) {
      await _rtcService.init(isController: true);
    }
  }

  // 🖥️ 電視投放新增:控制端把手機畫面 JPEG 傳給電視
  void _onImageUpdate() {
    if (widget.isDisplay) return;
    final jpeg = _engine.imageNotifier.value;
    if (jpeg == null) return;
    if (_clientService.isConnected) {
      _clientService.sendBinary(jpeg);
    } else if (_serverService.isClientConnected) {
      _serverService.sendBinary(jpeg);
    }
  }

  // 🖥️ 電視投放新增:顯示端收遠端指令
  void _handleRemoteCommand(Map<String, dynamic> msg) {
    if (!mounted || !widget.isDisplay) return;
    final type = msg['type'];
    if (type == 'POSE_UPDATE') {
      final kp = (msg['keypoints'] as List)
          .map((e) => Offset(e[0].toDouble(), e[1].toDouble()))
          .toList();
      final sc = (msg['scores'] as List).map((e) => e.toDouble()).toList();
      _engine.updateFromRemote(kp, List<double>.from(sc));
    } else if (type == 'TRAINING_UPDATE') {
      final c = _remoteState.value;
      _remoteState.value = c.copyWith(
        repCount: msg['repCount'] ?? c.repCount,
        feedback: msg['feedback'] ?? c.feedback,
        instruction: msg['instruction'] ?? c.instruction,
      );
    } else if (type == 'RTC_SIGNAL') {
      _rtcService.handleSignal(msg['signal']);
    } else if (type == 'STOP') {
      Navigator.of(context).pop();
    }
  }

  // 🆕 達標時呼叫:跳出「要不要升級」詢問視窗
  void _handleLevelUpDetected() {
    if (_levelUpDialogShowing) return;

    final currentMeta = widget.trainingActionMeta ??
        kTrainingActions.firstWhere(
          (a) => a.name == widget.action.title,
          orElse: () => kTrainingActions.first,
        );

    final currentLevelIdx = _levelToInt(_previousLevel) - 1;
    final nextLevelIdx = currentLevelIdx + 1;
    final hasNextLevel =
        currentLevelIdx >= 0 && nextLevelIdx < currentMeta.difficulties.length;
    final nextDifficulty =
        hasNextLevel ? currentMeta.difficulties[nextLevelIdx] : null;

    setState(() {
      _isPaused = true;
      _levelUpDialogShowing = true;
      _hasNextLevel = hasNextLevel;
      _nextLevelLabel = nextDifficulty?.label ?? '';
      _levelUpRepsController.text = '${nextDifficulty?.targetReps ?? 10}';
    });
    VoiceService.stop();
  }

  void _confirmLevelUp() {
    //final currentMeta = widget.trainingActionMeta ??
        kTrainingActions.firstWhere(
          (a) => a.name == widget.action.title,
          orElse: () => kTrainingActions.first,
        );
    //final currentLevelIdx = _levelToInt(_previousLevel) - 1;
    //final nextLevelIdx = currentLevelIdx + 1;
    //final nextDifficulty = currentMeta.difficulties[nextLevelIdx];

    final action = widget.action;
    final controllable =
        action is LevelUpControllable ? action as LevelUpControllable : null;

    _saveCurrentLevelRecord();
    final customReps = int.tryParse(_levelUpRepsController.text);
    controllable?.confirmLevelUp(
      customTargetReps: (customReps != null && customReps > 0) ? customReps : null,
    );

    setState(() {
      _levelUpDialogShowing = false;
      _previousLevel = _nextLevel(_previousLevel);
      _currentLevelStart = DateTime.now();
      _currentLevelReps = 0;
      _instruction = '難度提升,請繼續保持';
      _isPaused = false;
    });
  }

  void _declineLevelUp() {
    setState(() {
      _levelUpDialogShowing = false;
    });
    _handleRealEnd(); // 🆕 不繼續練,直接進入結束流程(存紀錄、跳完成畫面)
  }

  void _saveCurrentLevelRecord() {
    if (widget.trainingActionMeta == null) return;

    final durationSec =
        DateTime.now().difference(_currentLevelStart).inSeconds;

    HistoryService().saveRecord(TrainingRecord(
      timestamp: DateTime.now().toString().substring(0, 16),
      actionName: widget.trainingActionMeta!.name,
      difficulty: _levelToInt(_previousLevel),
      durationSeconds: durationSec,
      mistakeLogs: const [],
      targetReps: widget.difficultyMeta?.targetReps ?? 10,
    ));

    _recordsSavedThisSession++;
  }

  RehabDifficulty _nextLevel(RehabDifficulty current) {
    switch (current) {
      case RehabDifficulty.easy:
        return RehabDifficulty.medium;
      case RehabDifficulty.medium:
        return RehabDifficulty.hard;
      case RehabDifficulty.hard:
        return RehabDifficulty.hard;
    }
  }

  int _levelToInt(RehabDifficulty d) {
    switch (d) {
      case RehabDifficulty.easy:
        return 1;
      case RehabDifficulty.medium:
        return 2;
      case RehabDifficulty.hard:
        return 3;
    }
  }

  Future<void> _switchCamera() async {
    // 🚀 樹莓派新增:如果目前是外接來源,「翻轉鏡頭」按鈕改為切回手機鏡頭
    if (_isExternalCamera) {
      await _disableExternalCamera();
      return;
    }
    await _engine.switchCamera();
    if (mounted) setState(() {});
  }

  // 🚀 樹莓派新增:開啟外接鏡頭來源(身體 + 手部)
  Future<void> _enableExternalCamera() async {
    final ip = await showPiIpDialog(context, initialIp: _lastPiIp);
    if (ip == null || ip.isEmpty) return;
    _lastPiIp = ip;

    // 手機鏡頭串流先停掉,避免兩邊同時餵畫面給同一個 engine
    try {
      final cam = _engine.cameraController;
      if (cam != null && cam.value.isStreamingImages) {
        await cam.stopImageStream();
      }
    } catch (_) {}

    _piCamera?.dispose();
    _piCamera = PiCameraSource(engine: _engine, ip: ip);
    await _piCamera!.start();

    // 🚀 手部偵測:另開一條連線接同一台樹莓派,拿手部 landmarks
    _piHand?.dispose();
    _piHand = PiHandSource(service: _handService, ip: ip);
    await _piHand!.start();

    if (!mounted) return;
    setState(() => _isExternalCamera = true);
  }

  // 🚀 樹莓派新增:切回手機內建鏡頭
  Future<void> _disableExternalCamera() async {
    await _piCamera?.stop();
    _piCamera?.dispose();
    _piCamera = null;

    // 🚀 手部偵測:一併關閉
    await _piHand?.stop();
    _piHand?.dispose();
    _piHand = null;

    try {
      final cam = _engine.cameraController;
      if (cam != null && !cam.value.isStreamingImages) {
        await cam.startImageStream((image) {});
        // startImageStream 需要透過 engine 內部方法才會接上推論,
        // 這裡改呼叫 engine 自己的 startCamera() 更安全:
      }
    } catch (_) {}
    await _engine.startCamera();

    if (!mounted) return;
    setState(() => _isExternalCamera = false);
  }

  Future<void> _handleStopButtonTap() async {
    if (_completionShown || _isPaused) return;

    setState(() => _isPaused = true);
    VoiceService.stop();

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
      setState(() => _isPaused = false);
      return;
    }

    await _handleRealEnd();
  }

  Future<void> _handleRealEnd() async {
    _completionShown = true;

    final videoPath = await ScreenRecorderService.stopRecording();

    if (_currentLevelReps >= _kMinRepsToSave) {
      _saveCurrentLevelRecord();
    }

    // ✅ 新增
    await markPlanItemDoneByActionName(widget.trainingActionMeta?.name ?? widget.action.title);

    final durationSeconds =
        DateTime.now().difference(_sessionStart).inSeconds;

    final currentMeta = widget.trainingActionMeta ??
        kTrainingActions.firstWhere(
          (a) => a.name == widget.action.title,
          orElse: () => kTrainingActions.first,
        );
    final levelIdx = _levelToInt(_previousLevel) - 1;
    final currentDiff = (levelIdx >= 0 && levelIdx < currentMeta.difficulties.length)
        ? currentMeta.difficulties[levelIdx]
        : (widget.difficultyMeta ?? currentMeta.difficulties.first);

    bool? keepVideo;

    final result = await showDialog<_CompletionResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => CompletionDialog(
        isPaused: false,
        repCount: _repCount,
        durationSeconds: durationSeconds,
        mistakeLogs: const [],
        currentAction: currentMeta,
        currentDifficulty: currentDiff,
        hasVideo: videoPath != null,
        onVideoDecision: (keep) => keepVideo = keep,
        onRetry: () =>
            Navigator.of(dialogCtx).pop(_CompletionResult.retry()),
        onHome: () =>
            Navigator.of(dialogCtx).pop(_CompletionResult.home()),
        onStartNew: (a, d, autoLvl) =>
            Navigator.of(dialogCtx).pop(_CompletionResult.startNew(a, d, autoLvl)), // 🆕
      ),
    );

    if (videoPath != null) {
      if (keepVideo == true) {
        await HistoryService()
            .updateLastRecordsVideoPath(_recordsSavedThisSession, videoPath);
      } else {
        File(videoPath).delete().catchError((e) => File(videoPath));
      }
    }

    if (!mounted || result == null) return;

    switch (result.kind) {
      case _CompletionKind.retry:
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => BodyTrainingScreen(
            action: widget.action,
            trainingActionMeta: widget.trainingActionMeta,
            difficultyMeta: widget.difficultyMeta,
            autoLevelUp: widget.autoLevelUp, // 🆕(原本漏了,補上)
          ),
        ));
        break;
      case _CompletionKind.home:
        Navigator.of(context).pop();
        break;
      case _CompletionKind.startNew:
        _navigateToAction(result.action!, result.difficulty!, result.autoLevelUp!); // 🆕
        break;
    }
  }

  Future<void> _navigateToAction(
      TrainingAction action, DifficultyOption difficulty, bool autoLevelUp) async { // 🆕 多一個參數
    _engine.poseNotifier.removeListener(_onPoseUpdate); // 🆕 先停止監聽,避免dispose過程中還觸發更新
    _piCamera?.dispose();
    _piHand?.dispose(); // 🚀 樹莓派新增:離開畫面前記得釋放
    await _engine.dispose();
    // 🆕 給相機資源多一點時間真正釋放乾淨,避免畫面切換太快
    //    導致 Flutter 內部元件清單對不起來而閃紅畫面
    await Future.delayed(const Duration(milliseconds: 300));
    
    if (!mounted) return;

    Widget screen;
    final diff = _mapDifficulty(difficulty.level);
    if (action.type == ActionType.wipeBody) {
      screen = BodyTrainingScreen(
        action: StandingKneeRaiseAction(
          difficulty: diff,
          targetCount: difficulty.targetReps,
        ),
        trainingActionMeta: action,
        difficultyMeta: difficulty,
        autoLevelUp: autoLevelUp, // 🆕(原本是 widget.autoLevelUp)
      );
    } else if (action.type == ActionType.drawCircle) {
      screen = BodyTrainingScreen(
        action: DrawCircleAction(
          difficulty: diff,
          targetCount: difficulty.targetReps,
        ),
        trainingActionMeta: action,
        difficultyMeta: difficulty,
        autoLevelUp: autoLevelUp, // 🆕
      );
    } else if (action.type == ActionType.reach) {
      screen = BodyTrainingScreen(
        action: ReachAction(
          difficulty: diff,
          targetCount: difficulty.targetReps,
        ),
        trainingActionMeta: action,
        difficultyMeta: difficulty,
        autoLevelUp: autoLevelUp, // 🆕
      );
    } else if (action.type == ActionType.raiseBothArms) {
      screen = BodyTrainingScreen(
        action: RaiseBothArmsAction(
          difficulty: diff,
          targetCount: difficulty.targetReps,
        ),
        trainingActionMeta: action,
        difficultyMeta: difficulty,
        autoLevelUp: autoLevelUp, // 🆕
      );
    } else if (action.type == ActionType.elbowForward) {
      screen = BodyTrainingScreen(
        action: ElbowForwardAction(
          difficulty: diff,
          targetCount: difficulty.targetReps,
        ),
        trainingActionMeta: action,
        difficultyMeta: difficulty,
        autoLevelUp: autoLevelUp, // 🆕
      );
    } else if (action.type == ActionType.sitToStand) {
      screen = BodyTrainingScreen(
        action: SitToStandAction(
          difficulty: diff,
          targetCount: difficulty.targetReps,
        ),
        trainingActionMeta: action,
        difficultyMeta: difficulty,
        autoLevelUp: autoLevelUp, // 🆕
      );
    } else if (action.type == ActionType.lateralStep) {
      screen = BodyTrainingScreen(
        action: LateralStepAction(
          difficulty: diff,
          targetCount: difficulty.targetReps,
        ),
        trainingActionMeta: action,
        difficultyMeta: difficulty,
        autoLevelUp: autoLevelUp, // 🆕
      );
    } else {
      screen = TrainingScreen(
        action: action,
        difficulty: difficulty,
        autoLevelUp: autoLevelUp, // 🆕(原本沒帶,手部動作換過去會變回預設 true)
      );
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => screen));
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

  @override
  void dispose() {
    if (_recordingStarted && !_completionShown) {
      ScreenRecorderService.stopRecording().then((path) {
        if (path != null) {
          File(path).delete().catchError((e) => File(path));
        }
      });
    }
    VoiceService.stop();
    // 🖥️ 電視投放新增
    _socketSub?.cancel();
    _engine.imageNotifier.removeListener(_onImageUpdate);
    _rtcService.dispose();
    _remoteRenderer.dispose();
    _remoteState.dispose();
    _engine.poseNotifier.removeListener(_onPoseUpdate);
    _piCamera?.dispose(); // 🚀 樹莓派新增
    _piHand?.dispose(); // 🚀 樹莓派手部新增
    _handService.dispose(); // 🚀 樹莓派手部新增
    _engine.dispose();
    _levelUpRepsController.dispose(); // 🆕
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFFFFFFF),
          body: SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(child: _buildBody()),
                // 🖥️ 電視投放:顯示端讀 remote,控制端讀本機
                if (widget.isDisplay)
                  ValueListenableBuilder<RehabSessionState>(
                    valueListenable: _remoteState,
                    builder: (_, remote, __) => _buildRemoteCoachCard(remote),
                  )
                else
                  _buildCoachCard(),
                if (widget.isDisplay)
                  ValueListenableBuilder<RehabSessionState>(
                    valueListenable: _remoteState,
                    builder: (_, remote, __) => _buildRemoteStatsBar(remote),
                  )
                else
                  _buildStatsBar(),
              ],
            ),
          ),
        ),
        if (_levelUpDialogShowing) _buildLevelUpOverlay(), // 🆕
      ],
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40, height: 40,
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
            child: Text(
              widget.action.title,
              style: const TextStyle(
                color: Color(0xFF1A1D2E),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          // 🚀 樹莓派新增:外接鏡頭開關按鈕
          GestureDetector(
            onTap: _isExternalCamera
                ? _disableExternalCamera
                : _enableExternalCamera,
            child: Container(
              width: 40, height: 40,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: _isExternalCamera
                    ? const Color(0xFF4A65FF)
                    : const Color(0xFFF5F6FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDDE0F0)),
              ),
              child: Icon(
                Icons.videocam,
                color: _isExternalCamera ? Colors.white : const Color(0xFF374151),
                size: 20,
              ),
            ),
          ),
          GestureDetector(
            onTap: _switchCamera,
            child: Container(
              width: 40, height: 40,
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

  Widget _buildBody() {
    // 🖥️ 電視投放新增:顯示端 → 顯示遠端傳來的畫面+骨架,不開相機
    if (widget.isDisplay) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Container(
            color: const Color(0xFF1A1D2E),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ValueListenableBuilder<Uint8List?>(
                  valueListenable: _engine.imageNotifier,
                  builder: (_, jpeg, __) {
                    if (jpeg == null) {
                      return const Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFF4A65FF)),
                      );
                    }
                    return Image.memory(jpeg,
                        gaplessPlayback: true, fit: BoxFit.cover);
                  },
                ),
                ValueListenableBuilder<PoseData>(
                  valueListenable: _engine.poseNotifier,
                  builder: (_, data, __) {
                    return TweenAnimationBuilder<PoseData>(
                      tween: _PoseTween(end: data),
                      duration: const Duration(milliseconds: 40),
                      curve: Curves.easeOutCubic,
                      builder: (_, lerped, __) => CustomPaint(
                        painter: _SkeletonPainter(lerped, _scoreThreshold),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 🚀 樹莓派新增:外接來源時顯示 JPEG 畫面,不是 CameraPreview
    if (_isExternalCamera && _piCamera != null && _piHand != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ValueListenableBuilder<Uint8List?>(
                valueListenable: _piCamera!.latestJpeg,
                builder: (_, jpeg, __) {
                  if (jpeg == null) {
                    return const Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF00BCD4), strokeWidth: 3),
                    );
                  }
                  return Image.memory(jpeg, fit: BoxFit.cover, gaplessPlayback: true);
                },
              ),
              // 🚀 修正:身體骨架 painter 加上 sourceSize(來自 _piCamera.frameSize),
              // 讓骨架點位跟畫面顯示用的 BoxFit.cover 裁切/縮放對齊。
              ValueListenableBuilder<PoseData>(
                valueListenable: _engine.poseNotifier,
                builder: (_, data, __) {
                  return ValueListenableBuilder<Size?>(
                    valueListenable: _piCamera!.frameSize,
                    builder: (_, srcSize, __) {
                      return TweenAnimationBuilder<PoseData>(
                        tween: _PoseTween(end: data),
                        duration: const Duration(milliseconds: 40),
                        curve: Curves.easeOutCubic,
                        builder: (_, lerped, __) => CustomPaint(
                          painter: _SkeletonPainter(
                            lerped,
                            _scoreThreshold,
                            sourceSize: srcSize, // 🚀 新增
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
              // 🚀 樹莓派手部骨架:一樣加上 sourceSize(來自 _piHand.frameSize),
              // 跟身體骨架用同一套 BoxFit.cover 換算,確保三者(畫面/身體/手部)貼合。
              ValueListenableBuilder<DetectionResult>(
                valueListenable: _piHand!.handResult,
                builder: (_, hand, __) {
                  if (!hand.handDetected || hand.landmarks.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return ValueListenableBuilder<Size?>(
                    valueListenable: _piHand!.frameSize,
                    builder: (_, srcSize, __) => CustomPaint(
                      painter: _PiHandSkeletonPainter(
                        hand.landmarks,
                        sourceSize: srcSize, // 🚀 新增
                      ),
                    ),
                  );
                },
              ),
              ValueListenableBuilder<bool>(
                valueListenable: _piCamera!.connected,
                builder: (_, connected, __) {
                  if (connected) return const SizedBox.shrink();
                  return Container(
                    color: Colors.black.withValues(alpha: 0.5),
                    child: const Center(
                      child: Text(
                        '樹莓派連線中斷,請確認網路',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                  );
                },
              ),
              if (!_bodyVisible)
                Container(
                  color: Colors.black.withValues(alpha: 0.3),
                  child: const Center(
                    child: Text(
                      '請站入鏡頭範圍內',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        shadows: [Shadow(blurRadius: 8, color: Colors.black)],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // ── 原本手機內建鏡頭邏輯,完全不變(不傳 sourceSize,行為不受影響) ──
    final cam = _engine.cameraController;
    if (!_engine.cameraReady.value || cam == null) {
      return const Center(
        child: CircularProgressIndicator(
            color: Color(0xFF00BCD4), strokeWidth: 3),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CameraPreview(cam),
            ValueListenableBuilder<PoseData>(
              valueListenable: _engine.poseNotifier,
              builder: (_, data, __) {
                return TweenAnimationBuilder<PoseData>(
                  tween: _PoseTween(end: data),
                  duration: const Duration(milliseconds: 40),
                  curve: Curves.easeOutCubic,
                  builder: (_, lerped, __) => CustomPaint(
                    painter: _SkeletonPainter(lerped, _scoreThreshold),
                  ),
                );
              },
            ),
            if (!_bodyVisible)
              Container(
                color: Colors.black.withValues(alpha: 0.3),
                child: const Center(
                  child: Text(
                    '請站入鏡頭範圍內',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      shadows: [Shadow(blurRadius: 8, color: Colors.black)],
                    ),
                  ),
                ),
              ),
            if (_waitingHandSelect)
              Container(
                color: Colors.black.withValues(alpha: 0.65),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '請選擇要訓練的手',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          shadows: [Shadow(blurRadius: 8, color: Colors.black)],
                        ),
                      ),
                      const SizedBox(height: 36),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _handButton('左手', () {
                            setState(() {
                              (widget.action as ReachAction).selectLeftHand();
                              _feedback = '已選擇左手,請將手自然放下';
                              _instruction = '';
                            });
                          }),
                          const SizedBox(width: 28),
                          _handButton('右手', () {
                            setState(() {
                              (widget.action as ReachAction).selectRightHand();
                              _feedback = '已選擇右手,請將手自然放下';
                              _instruction = '';
                            });
                          }),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (_isPaused)
              Container(
                color: Colors.black.withValues(alpha: 0.4),
                child: const Center(
                  child: Text(
                    '⏸ 已暫停',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      shadows: [Shadow(blurRadius: 8, color: Colors.black)],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _handButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          color: const Color(0xFF4A65FF),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.back_hand, color: Colors.white, size: 42),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoachCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDE0F0)),
      ),
      child: Row(
        children: [
          const Text('🤖', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _feedback,
                  style: const TextStyle(
                    color: Color(0xFF1A1D2E),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_instruction.isNotEmpty)
                  Text(
                    _instruction,
                    style: const TextStyle(
                        color: Color(0xFF4A65FF), fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 🖥️ 電視投放:顯示端教練卡,讀遠端傳來的 feedback/instruction
  Widget _buildRemoteCoachCard(RehabSessionState state) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDE0F0)),
      ),
      child: Row(
        children: [
          const Text('🤖', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  state.feedback,
                  style: const TextStyle(
                    color: Color(0xFF1A1D2E),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (state.instruction.isNotEmpty)
                  Text(
                    state.instruction,
                    style: const TextStyle(
                        color: Color(0xFF4A65FF), fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar() {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: Row(
      children: [
        Expanded(child: _statCard('完成次數', '$_repCount')),
        const SizedBox(width: 12),
        Expanded(
            child: _statCard('目前難度', widget.action.difficultyLabel)),
        const SizedBox(width: 12),
        _buildStopButton(),
      ],
    ),
  );
}

// 🖥️ 電視投放:顯示端次數列,讀遠端傳來的 repCount
  Widget _buildRemoteStatsBar(RehabSessionState state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(child: _statCard('完成次數', '${state.repCount}')),
          const SizedBox(width: 12),
          Expanded(
              child: _statCard('目前難度', widget.action.difficultyLabel)),
          const SizedBox(width: 12),
          _buildStopButton(),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF8A8D9F), fontSize: 11)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF1A1D2E),
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStopButton() {
    return GestureDetector(
      onTap: _handleStopButtonTap,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: const Color(0xFFFF4B4B),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF4B4B).withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.stop_rounded, color: Colors.white, size: 28),
      ),
    );
  }

  Widget _buildLevelUpOverlay() {
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
                  Text(
                    _hasNextLevel ? '動作做得很棒！' : '已經是最高難度了！',
                    style: const TextStyle(
                      color: Color(0xFF1A1D2E),
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _hasNextLevel ? '要挑戰下一階「$_nextLevelLabel」嗎？' : '再接再厲，繼續保持！',
                    style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  if (_hasNextLevel) ...[
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
                            style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _hasNextLevel ? _confirmLevelUp : _declineLevelUp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4A65FF),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        _hasNextLevel ? '💪 挑戰下一階' : '🎉 完成訓練',
                        style: const TextStyle(
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
}



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

class _SkeletonPainter extends CustomPainter {
  final PoseData data;
  final double threshold;
  // 🚀 新增:原始畫面(樹莓派 JPEG)的實際尺寸。傳 null 時維持原本行為
  // (直接用容器尺寸換算),手機鏡頭(CameraPreview)場景不受影響。
  final Size? sourceSize;

  _SkeletonPainter(this.data, this.threshold, {this.sourceSize});

  bool _valid(Offset p) =>
      p.dx > 0.02 && p.dx < 0.98 && p.dy > 0.02 && p.dy < 0.98;

  // 🚀 新增:算出跟 Image.memory(fit: BoxFit.cover) 一致的縮放倍率
  // 與置中裁切偏移量,邏輯跟 hand_overlay_widget.dart 的修正相同。
  ({double scale, double dx, double dy}) _coverTransform(Size canvasSize) {
    final src = sourceSize;
    if (src == null || src.width <= 0 || src.height <= 0) {
      return (scale: 1.0, dx: 0.0, dy: 0.0);
    }
    final scaleX = canvasSize.width / src.width;
    final scaleY = canvasSize.height / src.height;
    final scale = scaleX > scaleY ? scaleX : scaleY; // cover: 取較大值
    final scaledW = src.width * scale;
    final scaledH = src.height * scale;
    final dx = (canvasSize.width - scaledW) / 2;
    final dy = (canvasSize.height - scaledH) / 2;
    return (scale: scale, dx: dx, dy: dy);
  }

  Offset _map(Offset p, Size canvasSize) {
    final t = _coverTransform(canvasSize);
    final srcW = sourceSize?.width ?? canvasSize.width;
    final srcH = sourceSize?.height ?? canvasSize.height;
    return Offset(
      p.dx * srcW * t.scale + t.dx,
      p.dy * srcH * t.scale + t.dy,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (data.keypoints.isEmpty || data.scores.isEmpty) return;

    final bone = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.8)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final joint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..style = PaintingStyle.fill;

    for (final c in _skeletonConnections) {
      final a = c[0], b = c[1];
      if (a >= data.keypoints.length || b >= data.keypoints.length) continue;
      if (a >= data.scores.length || b >= data.scores.length) continue;
      if (data.scores[a] < threshold || data.scores[b] < threshold) continue;
      final pa = data.keypoints[a], pb = data.keypoints[b];
      if (!_valid(pa) || !_valid(pb)) continue;
      canvas.drawLine(_map(pa, size), _map(pb, size), bone);
    }
    for (int i = 0; i < 17 && i < data.keypoints.length; i++) {
      if (i >= data.scores.length || data.scores[i] < threshold) continue;
      final p = data.keypoints[i];
      if (!_valid(p)) continue;
      canvas.drawCircle(_map(p, size), 5, joint);
    }
  }

  @override
  bool shouldRepaint(_SkeletonPainter old) => true;
}

// 🚀 樹莓派手部骨架 painter
// 🚀 修正:加上 sourceSize,套用跟 _SkeletonPainter / HandOverlayPainter
// 相同的 BoxFit.cover 換算邏輯,確保跟畫面顯示、跟身體骨架三者對齊。
// 若跑起來發現方向不對(左右相反或上下顛倒),把 map() 裡的
// lm.x 改成 (1 - lm.x) 或 lm.y 改成 (1 - lm.y) 即可修正。
class _PiHandSkeletonPainter extends CustomPainter {
  final List<Landmark> landmarks;
  final Size? sourceSize; // 🚀 新增

  _PiHandSkeletonPainter(this.landmarks, {this.sourceSize});

  static const _connections = [
    [0, 1], [1, 2], [2, 3], [3, 4],
    [0, 5], [5, 6], [6, 7], [7, 8],
    [0, 9], [9, 10], [10, 11], [11, 12],
    [0, 13], [13, 14], [14, 15], [15, 16],
    [0, 17], [17, 18], [18, 19], [19, 20],
  ];

  ({double scale, double dx, double dy}) _coverTransform(Size canvasSize) {
    final src = sourceSize;
    if (src == null || src.width <= 0 || src.height <= 0) {
      return (scale: 1.0, dx: 0.0, dy: 0.0);
    }
    final scaleX = canvasSize.width / src.width;
    final scaleY = canvasSize.height / src.height;
    final scale = scaleX > scaleY ? scaleX : scaleY;
    final scaledW = src.width * scale;
    final scaledH = src.height * scale;
    final dx = (canvasSize.width - scaledW) / 2;
    final dy = (canvasSize.height - scaledH) / 2;
    return (scale: scale, dx: dx, dy: dy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (landmarks.isEmpty) return;

    final t = _coverTransform(size);
    final srcW = sourceSize?.width ?? size.width;
    final srcH = sourceSize?.height ?? size.height;

    Offset map(Landmark lm) => Offset(
          lm.x * srcW * t.scale + t.dx,
          lm.y * srcH * t.scale + t.dy,
        );

    final linePaint = Paint()
      ..color = Colors.amberAccent.withValues(alpha: 0.85)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final pointPaint = Paint()
      ..color = Colors.orangeAccent
      ..style = PaintingStyle.fill;

    for (final conn in _connections) {
      if (conn[0] >= landmarks.length || conn[1] >= landmarks.length) continue;
      canvas.drawLine(map(landmarks[conn[0]]), map(landmarks[conn[1]]), linePaint);
    }

    for (final lm in landmarks) {
      canvas.drawCircle(map(lm), 5, pointPaint);
    }
  }

  @override
  bool shouldRepaint(_PiHandSkeletonPainter old) => true;
}

class _PoseTween extends Tween<PoseData> {
  _PoseTween({super.end});

  @override
  PoseData lerp(double t) {
    final b = begin ?? PoseData.empty();
    final e = end ?? PoseData.empty();
    if (b.keypoints.isEmpty ||
        e.keypoints.isEmpty ||
        b.keypoints.length != e.keypoints.length) {
      return e;
    }
    final lerped = <Offset>[];
    for (int i = 0; i < e.keypoints.length; i++) {
      lerped.add(Offset.lerp(b.keypoints[i], e.keypoints[i], t)!);
    }
    return PoseData(lerped, e.scores);
  }
}

enum _CompletionKind { retry, home, startNew }

class _CompletionResult {
  final _CompletionKind kind;
  final TrainingAction? action;
  final DifficultyOption? difficulty;
  final bool? autoLevelUp; // 🆕
  const _CompletionResult._(this.kind, this.action, this.difficulty, this.autoLevelUp);
  factory _CompletionResult.retry() =>
      const _CompletionResult._(_CompletionKind.retry, null, null, null);
  factory _CompletionResult.home() =>
      const _CompletionResult._(_CompletionKind.home, null, null, null);
  factory _CompletionResult.startNew(
          TrainingAction a, DifficultyOption d, bool autoLevelUp) => // 🆕
      _CompletionResult._(_CompletionKind.startNew, a, d, autoLevelUp);
}