import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart'; // ← 新增:控制端要用 CameraPreview
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../models/training_action.dart';
import '../../models/pose_data.dart';
import 'socket_client_service.dart';
import 'socket_server_service.dart';
import '../../services/body_pose_engine.dart';
import '../../actions/body_rehab_action.dart';
import '../../models/body_frame.dart';
import '../../services/voice_service.dart';
import 'webrtc_service.dart';

class RemoteControllerScreen extends StatefulWidget {
  final TrainingAction action;
  final DifficultyOption difficulty;
  final BodyRehabAction rehabAction;
  final bool isDisplay;

  const RemoteControllerScreen({
    super.key,
    required this.action,
    required this.difficulty,
    required this.rehabAction,
    this.isDisplay = false,
  });

  @override
  State<RemoteControllerScreen> createState() => _RemoteControllerScreenState();
}

class _RemoteControllerScreenState extends State<RemoteControllerScreen> {
  final _clientService = SocketClientService();
  final _serverService = SocketServerService();
  final _rtcService = WebRtcService();
  final _localRenderer = RTCVideoRenderer();
  final BodyPoseEngine _engine = BodyPoseEngine();

  int _repCount = 0;
  String _feedback = '等待連線中...';
  String _instruction = '';
  StreamSubscription? _socketSub;

  @override
  void initState() {
    super.initState();

    // Listen to whichever service is active/connected
    if (_clientService.isConnected) {
      _socketSub = _clientService.messages.listen(_handleMessage);
    } else {
      _socketSub = _serverService.messages.listen(_handleMessage);
    }

    _instruction = widget.action.description;
    VoiceService.init();
    _start();
  }

  Future<void> _start() async {
    await _localRenderer.initialize();

    // 🖥️ 電視投放新增:控制端進訓練時,通知電視開對應的顯示端畫面
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

    // Singleton handles onSignalingMessage in HomeScreen

    if (widget.isDisplay) {
      _rtcService.onRemoteStream.listen((stream) {
        if (mounted) {
          setState(() {
            _localRenderer.srcObject = stream;
          });
        }
      });

      // Listen for binary messages for video frames
      if (_clientService.isConnected) {
        _clientService.binaryMessages.listen((data) {
          if (mounted && widget.isDisplay) {
            _engine.imageNotifier.value = data;
          }
        });
      } else {
        _serverService.binaryMessages.listen((data) {
          if (mounted && widget.isDisplay) {
            _engine.imageNotifier.value = data;
          }
        });
      }

      if (_rtcService.currentRemoteStream != null) {
        setState(() {
          _localRenderer.srcObject = _rtcService.currentRemoteStream;
        });
      }
    } else {
      _rtcService.onLocalStream.listen((stream) {
        if (mounted) {
          setState(() {
            _localRenderer.srcObject = stream;
          });
        }
      });
      if (_rtcService.currentLocalStream != null) {
        setState(() {
          _localRenderer.srcObject = _rtcService.currentLocalStream;
        });
      }
    }

    // Initialize as controller or display based on role
    // If we are starting from the phone, it is the initiator (Controller)
    if (!widget.isDisplay) {
      // On phone, we prioritize AI over WebRTC video to avoid camera conflict
      await _rtcService.init(isController: true, captureVideo: false);
    } else {
      // Receiver case (Display)
      // Only init if not already initialized by HomeScreen
      if (_rtcService.currentRemoteStream == null) {
        await _rtcService.init(isController: false);
      }
    }

    // Only start Pose Engine and local camera if NOT in Display Mode
    if (!widget.isDisplay) {
      await _engine.init(asReceiver: false);
      if (!mounted) return;
      setState(() {});
      await _engine.startCamera();

      // ⚠️ 修正:這個畫面本身就是「TV 遙控模式」,控制端(手機)的
      // 職責就是把畫面串流給顯示端看。之前這個開關從沒被打開過,
      // 顯示端 (isDisplay:true) 那邊會永遠收不到 JPEG、
      // imageNotifier 永遠是 null,電視畫面一直空白/卡轉圈。
      _engine.castEnabled = true;

      _engine.poseNotifier.addListener(_onPoseUpdate);

      // Send JPEG frames over socket since WebRTC video is disabled to avoid conflict
      _engine.imageNotifier.addListener(_onImageUpdate);
    } else {
      // In display mode, just init as receiver to show skeleton
      await _engine.init(asReceiver: true);
      if (!mounted) return;
      setState(() {});
    }
  }

  void _onImageUpdate() {
    if (widget.isDisplay) return;
    final jpeg = _engine.imageNotifier.value;
    if (jpeg == null) return;

    if (_clientService.isConnected) {
      _clientService.sendBinary(jpeg);
    } else {
      _serverService.sendBinary(jpeg);
    }
  }

  void _onPoseUpdate() {
    if (widget.isDisplay) return;
    final data = _engine.poseNotifier.value;
    if (data.keypoints.isEmpty) return;

    // Send updates to peer
    final updateMsg = {
      'type': 'POSE_UPDATE',
      'keypoints': data.keypoints.map((e) => [e.dx, e.dy]).toList(),
      'scores': data.scores,
    };

    if (_clientService.isConnected) {
      _clientService.sendCommand(updateMsg);
    } else {
      _serverService.sendMessage(updateMsg);
    }

    final joints = <RehabJoint, Offset>{};
    // ... same mapping ...
    const Map<RehabJoint, int> kJointIndex = {
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

    kJointIndex.forEach((joint, idx) {
      joints[joint] = data.keypoints[idx];
    });
    final frame = BodyFrame(joints: joints);

    final fb = widget.rehabAction.update(frame);

    if (mounted) {
      setState(() {
        if (fb.scored) _repCount++;
        if (fb.prompt != null) _feedback = fb.prompt!;
        if (fb.leveledUp) _instruction = '難度提升，請繼續保持';
      });

      // Send status to peer
      final statusMsg = {
        'type': 'TRAINING_UPDATE',
        'repCount': _repCount,
        'feedback': _feedback,
        'instruction': _instruction,
      };

      if (_clientService.isConnected) {
        _clientService.sendCommand(statusMsg);
      } else {
        _serverService.sendMessage(statusMsg);
      }

      if (fb.prompt != null) {
        VoiceService.speak(fb.prompt!);
      }
    }
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    // ⚠️ 修正:離開畫面時把開關關掉,避免這個 singleton engine
    // 被其他畫面重用時,castEnabled 殘留 true 造成非預期的 JPEG 生成。
    _engine.castEnabled = false;
    _engine.poseNotifier.removeListener(_onPoseUpdate);
    _engine.imageNotifier.removeListener(_onImageUpdate);
    _engine.dispose();
    _rtcService.dispose();
    _localRenderer.dispose();
    VoiceService.stop();
    super.dispose();
  }

  void _handleMessage(Map<String, dynamic> msg) {
    if (!mounted) return;

    final type = msg['type'];

    if (widget.isDisplay) {
      if (type == 'POSE_UPDATE') {
        final List<dynamic> kpRaw = msg['keypoints'];
        final List<dynamic> scRaw = msg['scores'];
        final kpts =
            kpRaw.map((e) => Offset(e[0].toDouble(), e[1].toDouble())).toList();
        final scores = scRaw.map((e) => e.toDouble()).toList();
        _engine.updateFromRemote(kpts, List<double>.from(scores));
      } else if (type == 'TRAINING_UPDATE') {
        setState(() {
          _repCount = msg['repCount'] ?? _repCount;
          _feedback = msg['feedback'] ?? _feedback;
          _instruction = msg['instruction'] ?? _instruction;
        });
      }
    }

    if (type == 'TRAINING_COMPLETED') {
      Navigator.of(context).pop();
    } else if (type == 'RTC_SIGNAL') {
      _rtcService.handleSignal(msg['signal']);
    }
  }

  void _sendCommand(String type) {
    final msg = {'type': type};
    if (_clientService.isConnected) {
      _clientService.sendCommand(msg);
    } else {
      _serverService.sendMessage(msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    _buildActionHeader(),
                    const SizedBox(height: 32),
                    _buildStatsCard(),
                    const SizedBox(height: 32),
                    _buildCoachCard(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              _sendCommand('STOP');
              Navigator.of(context).pop();
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F6FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDDE0F0)),
              ),
              child:
                  const Icon(Icons.close, color: Color(0xFF374151), size: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.isDisplay ? '同步顯示模式' : 'TV 遙控模式',
              style: const TextStyle(
                color: Color(0xFF1A1D2E),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.link, color: Colors.green, size: 14),
                const SizedBox(width: 4),
                Text(
                  widget.isDisplay ? '正在接收' : '正在傳輸',
                  style: const TextStyle(
                      color: Colors.green,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionHeader() {
    return Column(
      children: [
        Text(
          widget.action.name,
          style: const TextStyle(
            color: Color(0xFF1A1D2E),
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.difficulty.label,
          style: const TextStyle(
            color: Color(0xFF4A65FF),
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 24),
        AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Container(
              width: double.infinity,
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.isDisplay)
                    ValueListenableBuilder<Uint8List?>(
                      valueListenable: _engine.imageNotifier,
                      builder: (_, jpeg, __) {
                        if (jpeg == null) {
                          if (_localRenderer.srcObject != null) {
                            return RTCVideoView(_localRenderer,
                                objectFit: RTCVideoViewObjectFit
                                    .RTCVideoViewObjectFitCover);
                          }
                          return const Center(
                              child: CircularProgressIndicator(
                                  color: Color(0xFF4A65FF)));
                        }
                        return Image.memory(jpeg,
                            gaplessPlayback: true, fit: BoxFit.cover);
                      },
                    )
                  else
                    // ⚠️ 修正:控制端(手機)是用 captureVideo:false 初始化
                    // WebRTC 的(刻意不開視訊,避免跟 AI 相機衝突,見 _start()),
                    // 所以 _localRenderer.srcObject 原本就不會有值,
                    // 舊版邏輯會讓手機自己這頁一直卡在轉圈圈。
                    // 改成直接用 BodyPoseEngine 自己開的相機畫面預覽,
                    // 這樣不需要額外再開一路 WebRTC 視訊。
                    ValueListenableBuilder<bool>(
                      valueListenable: _engine.cameraReady,
                      builder: (_, ready, __) {
                        final cam = _engine.cameraController;
                        if (ready && cam != null && cam.value.isInitialized) {
                          return CameraPreview(cam);
                        }
                        return const Center(
                            child: CircularProgressIndicator(
                                color: Color(0xFF4A65FF)));
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
                          painter: _SkeletonPainter(
                              lerped, BodyPoseEngine.scoreThreshold),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6FA),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDDE0F0)),
      ),
      child: Column(
        children: [
          const Text(
            '目前完成次數',
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$_repCount',
            style: const TextStyle(
              color: Color(0xFF1A1D2E),
              fontSize: 64,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoachCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6FA),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDDE0F0)),
      ),
      child: Row(
        children: [
          const Text('🤖', style: TextStyle(fontSize: 28)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _feedback,
                  style: const TextStyle(
                    color: Color(0xFF1A1D2E),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_instruction.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _instruction,
                    style: const TextStyle(
                      color: Color(0xFF4A65FF),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonPainter extends CustomPainter {
  final PoseData data;
  final double threshold;
  _SkeletonPainter(this.data, this.threshold);

  bool _valid(Offset p) =>
      p.dx > 0.02 && p.dx < 0.98 && p.dy > 0.02 && p.dy < 0.98;

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

    const skeletonConnections = [
      [0, 1],
      [0, 2],
      [1, 3],
      [2, 4],
      [5, 6],
      [5, 7],
      [7, 9],
      [6, 8],
      [8, 10],
      [5, 11],
      [6, 12],
      [11, 12],
      [11, 13],
      [13, 15],
      [12, 14],
      [14, 16],
    ];

    for (final c in skeletonConnections) {
      final a = c[0], b = c[1];
      if (a >= data.keypoints.length || b >= data.keypoints.length) continue;
      if (a >= data.scores.length || b >= data.scores.length) continue;
      if (data.scores[a] < threshold || data.scores[b] < threshold) continue;
      final pa = data.keypoints[a], pb = data.keypoints[b];
      if (!_valid(pa) || !_valid(pb)) continue;
      canvas.drawLine(
        Offset(pa.dx * size.width, pa.dy * size.height),
        Offset(pb.dx * size.width, pb.dy * size.height),
        bone,
      );
    }
    for (int i = 0; i < 17 && i < data.keypoints.length; i++) {
      if (i >= data.scores.length || data.scores[i] < threshold) continue;
      final p = data.keypoints[i];
      if (!_valid(p)) continue;
      canvas.drawCircle(
          Offset(p.dx * size.width, p.dy * size.height), 5, joint);
    }
  }

  @override
  bool shouldRepaint(_SkeletonPainter old) => true;
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
