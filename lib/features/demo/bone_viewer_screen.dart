// lib/features/demo/bone_viewer_screen.dart
//
// 骨架即時連動畫面
// 上半：相機預覽（RTMPose 偵測）
// 下半：Three.js 3D 模型（WebView，可收放）

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../models/pose_data.dart';
import '../../services/body_pose_engine.dart';
import '../../services/pose_to_bone_mapper.dart';

// 🖥️ 電視投放新增
import '../tv_cast/socket_client_service.dart';

class BoneViewerScreen extends StatefulWidget {
  const BoneViewerScreen({super.key});

  @override
  State<BoneViewerScreen> createState() => _BoneViewerScreenState();
}

class _BoneViewerScreenState extends State<BoneViewerScreen> {
  final BodyPoseEngine _engine = BodyPoseEngine();
  final PoseToBoneMapper _mapper = PoseToBoneMapper();
  final _clientService = SocketClientService(); // 🖥️ 電視投放新增
  static const double _scoreThreshold = BodyPoseEngine.scoreThreshold;

  InAppWebViewController? _webController;
  bool _webReady = false;
  bool _modelExpanded = true; // 3D 區塊是否展開

  // 測試用：顯示當前角度
  BoneAngles _currentAngles = BoneAngles.zero;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await _engine.init();
    if (!mounted) return;
    setState(() {});
    await _engine.startCamera();
    _engine.poseNotifier.addListener(_onPoseUpdate);
  }

  void _onPoseUpdate() {
    final data = _engine.poseNotifier.value;
    //final angles = _mapper.computeAngles(data);
    final angles =
        _mapper.computeAngles(data, isFrontCamera: _engine.isFrontCamera);

    if (mounted) {
      setState(() => _currentAngles = angles);
    }

    if (_webReady && _webController != null) {
      final json = jsonEncode(angles.toMap());
      _webController!.evaluateJavascript(
        source: 'window.updateBones(${jsonEncode(json)})',
      );
    }
  }

  Future<void> _switchCamera() async {
    await _engine.switchCamera();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _engine.poseNotifier.removeListener(_onPoseUpdate);
    _mapper.reset();
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && _clientService.isConnected) {
          _clientService.sendCommand({'type': 'POP_SCREEN'});
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F6FA),
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: Column(
                  children: [
                    // ── 相機預覽區（彈性佔剩餘空間）──
                    Expanded(child: _buildCamera()),

                    // ── 測試用角度面板 ──
                    _buildAngleDebugPanel(),

                    // ── 3D 模型區（可收放）──
                    AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      child: _modelExpanded
                          ? SizedBox(height: 280, child: _buildWebView())
                          : const SizedBox.shrink(),
                    ),

                    // ── 收放按鈕 ──
                    _buildToggleBar(),
                  ],
                ),
              ),
            ],
          ),
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
              // 🖥️ 電視投放新增:同步返回指令
              if (_clientService.isConnected) {
                _clientService.sendCommand({'type': 'POP_SCREEN'});
              }
              Navigator.of(context).pop();
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDDE0F0)),
              ),
              child: const Icon(Icons.arrow_back_ios_new,
                  color: Color(0xFF374151), size: 16),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              '即時骨架連動',
              style: TextStyle(
                color: Color(0xFF1A1D2E),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          GestureDetector(
            onTap: _switchCamera,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
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

  Widget _buildCamera() {
    final cam = _engine.cameraController;
    if (!_engine.cameraReady.value || cam == null) {
      return const Center(
        child:
            CircularProgressIndicator(color: Color(0xFF00BCD4), strokeWidth: 3),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CameraPreview(cam),
            ValueListenableBuilder<PoseData>(
              valueListenable: _engine.poseNotifier,
              builder: (_, data, __) => CustomPaint(
                painter: _SkeletonPainter(data, _scoreThreshold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 測試用角度面板 ──────────────────────────────────────────────
  Widget _buildAngleDebugPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D2E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _angleChip('L肩', _currentAngles.shoulderL),
          _angleChip('L肘', _currentAngles.elbowL),
          _angleChip('L腕', _currentAngles.wristL),
          _angleChip('R肩', _currentAngles.shoulderR),
          _angleChip('R肘', _currentAngles.elbowR),
          _angleChip('R腕', _currentAngles.wristR),
        ],
      ),
    );
  }

  Widget _angleChip(String label, double angle) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 10)),
        Text('${angle.toStringAsFixed(0)}°',
            style: const TextStyle(
                color: Color(0xFF00E5FF),
                fontSize: 13,
                fontWeight: FontWeight.w700)),
      ],
    );
  }

  // ── Three.js WebView ────────────────────────────────────────────
  Widget _buildWebView() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: InAppWebView(
          initialFile: 'assets/viewer/index.html',
          initialSettings: InAppWebViewSettings(
            allowFileAccessFromFileURLs: true,
            allowUniversalAccessFromFileURLs: true,
            javaScriptEnabled: true,
            transparentBackground: true,
          ),
          onWebViewCreated: (controller) {
            _webController = controller;
          },
          onLoadStop: (controller, url) {
            print('[3D-DEBUG] WebView loaded: $url');
            setState(() => _webReady = true);
          },
          onConsoleMessage: (controller, msg) {
            print('[WebView Console] ${msg.messageLevel}: ${msg.message}');
          },
          onLoadError: (controller, url, code, message) {
            print('[3D-DEBUG] WebView LOAD ERROR: $url → $code / $message');
          },
        ),
      ),
    );
  }

  // ── 收放按鈕 ────────────────────────────────────────────────────
  Widget _buildToggleBar() {
    return GestureDetector(
      onTap: () => setState(() => _modelExpanded = !_modelExpanded),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 6, 16, 8),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFDDE0F0)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _modelExpanded ? '收起 3D 模型' : '展開 3D 模型',
              style: const TextStyle(
                color: Color(0xFF4A65FF),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            AnimatedRotation(
              turns: _modelExpanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 300),
              child: const Icon(Icons.keyboard_arrow_down,
                  color: Color(0xFF4A65FF), size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 骨架繪製器（簡化版，只畫上半身）──────────────────────────────
class _SkeletonPainter extends CustomPainter {
  final PoseData data;
  final double threshold;

  static const _connections = [
    [5, 6],
    [5, 7],
    [7, 9],
    [6, 8],
    [8, 10],
    [5, 11],
    [6, 12],
    [11, 12],
  ];

  _SkeletonPainter(this.data, this.threshold);

  bool _valid(Offset p) =>
      p.dx > 0.02 && p.dx < 0.98 && p.dy > 0.02 && p.dy < 0.98;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.keypoints.isEmpty) return;
    final bone = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.8)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final joint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..style = PaintingStyle.fill;

    for (final c in _connections) {
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
    for (int i = 5; i <= 12 && i < data.keypoints.length; i++) {
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
