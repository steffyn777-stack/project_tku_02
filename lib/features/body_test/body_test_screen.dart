// lib/screens/body_test_screen.dart
//
// 全身骨架測試頁面
// ONNX 邏輯已移至 body_pose_engine.dart,本檔只負責 UI + 骨架繪製。

import 'package:flutter/material.dart';
import '../../models/pose_data.dart';
import '../../services/body_pose_engine.dart';
import 'package:camera/camera.dart';

// ── 骨骼連線定義 ─────────────────────────────────────────────────────
const _skeletonConnections = [
  // 臉部
  [0, 1], [0, 2], [1, 3], [2, 4],
  // 上半身
  [5, 6], [5, 7], [7, 9], [6, 8], [8, 10],
  [5, 11], [6, 12], [11, 12],
  // 下半身
  [11, 13], [13, 15], [12, 14], [14, 16],
  // 左手指
  [91, 92], [92, 93], [93, 94], [94, 95],
  [91, 96], [96, 97], [97, 98], [98, 99],
  [91, 100], [100, 101], [101, 102], [102, 103],
  [91, 104], [104, 105], [105, 106], [106, 107],
  [91, 108], [108, 109], [109, 110], [110, 111],
  // 右手指
  [112, 113], [113, 114], [114, 115], [115, 116],
  [112, 117], [117, 118], [118, 119], [119, 120],
  [112, 121], [121, 122], [122, 123], [123, 124],
  [112, 125], [125, 126], [126, 127], [127, 128],
  [112, 129], [129, 130], [130, 131], [131, 132],
];

class BodyTestScreen extends StatefulWidget {
  const BodyTestScreen({super.key});

  @override
  State<BodyTestScreen> createState() => _BodyTestScreenState();
}

class _BodyTestScreenState extends State<BodyTestScreen> {
  // 唯一的依賴:引擎
  final BodyPoseEngine _engine = BodyPoseEngine();

  static const double _scoreThreshold = BodyPoseEngine.scoreThreshold;

  int _detectedPoints = 0;
  double _avgScore = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await _engine.init();
    if (!mounted) return;
    setState(() {}); // 相機就緒,觸發 build
    await _engine.startCamera();

    // 監聽骨架更新,順便算狀態列數字
    _engine.poseNotifier.addListener(_onPoseUpdate);
  }

  void _onPoseUpdate() {
    final data = _engine.poseNotifier.value;
    final validScores =
        data.scores.where((s) => s > _scoreThreshold).toList();
    if (mounted) {
      setState(() {
        _detectedPoints = validScores.length;
        _avgScore = validScores.isEmpty
            ? 0
            : validScores.reduce((a, b) => a + b) / validScores.length;
      });
    }
  }

  Future<void> _switchCamera() async {
    await _engine.switchCamera();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _engine.poseNotifier.removeListener(_onPoseUpdate);
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(child: _buildBody()),
            _buildStatusBar(),
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
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F6FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDDE0F0)),
              ),
              child: const Icon(Icons.arrow_back_ios_new,
                  color: const Color(0xFF374151), size: 16),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '全身骨架偵測',
                      style: TextStyle(
                        color: const Color(0xFF1A1D2E),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(width: 8),
                    _TopBarBetaBadge(),
                  ],
                ),
                Text(
                  'RTMPose Wholebody · 133 關鍵點',
                  style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _switchCamera,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F6FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDDE0F0)),
              ),
              child: const Icon(Icons.flip_camera_ios,
                  color: const Color(0xFF374151), size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final cam = _engine.cameraController;
    if (!_engine.cameraReady.value || cam == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
                color: Color(0xFF00BCD4), strokeWidth: 3),
            SizedBox(height: 16),
            Text('載入模型中...',
                style: TextStyle(color: Colors.white70, fontSize: 14)),
          ],
        ),
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

            // 骨架 Overlay (60FPS 補幀)
            ValueListenableBuilder<PoseData>(
              valueListenable: _engine.poseNotifier,
              builder: (_, data, __) {
                return TweenAnimationBuilder<PoseData>(
                  tween: PoseDataTween(end: data),
                  duration: const Duration(milliseconds: 40),
                  curve: Curves.easeOutCubic,
                  builder: (_, lerpedData, __) {
                    return CustomPaint(
                      painter:
                          _BodySkeletonPainter(lerpedData, _scoreThreshold),
                    );
                  },
                );
              },
            ),

            if (_detectedPoints < 5)
              Container(
                color: Colors.black.withValues(alpha: 0.3),
                child: const Center(
                  child: Text(
                    '請站入鏡頭範圍內',
                    style: TextStyle(
                      color: const Color(0xFF1A1D2E),
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

  Widget _buildStatusBar() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDE0F0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStat(
            icon: Icons.location_on,
            label: '偵測點數',
            value: '$_detectedPoints / 133',
            color: _detectedPoints > 50
                ? const Color(0xFF4CAF50)
                : const Color(0xFFFF9800),
          ),
          Container(width: 1, height: 32, color: const Color(0xFFDDE0F0)),
          _buildStat(
            icon: Icons.analytics,
            label: '平均信心度',
            value: _avgScore > 0 ? _avgScore.toStringAsFixed(2) : '--',
            color: const Color(0xFF00BCD4),
          ),
          Container(width: 1, height: 32, color: const Color(0xFFDDE0F0)),
          _buildStat(
            icon: Icons.camera_alt,
            label: '鏡頭',
            value: _engine.isFrontCamera ? '前鏡頭' : '後鏡頭',
            color: const Color(0xFF6B7280),
          ),
        ],
      ),
    );
  }

  Widget _buildStat({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF6B7280), fontSize: 10),
        ),
      ],
    );
  }
}

// ── TopBar Beta 標籤 ──────────────────────────────────────────────────
class _TopBarBetaBadge extends StatelessWidget {
  const _TopBarBetaBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF00BCD4).withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: const Color(0xFF00BCD4).withOpacity(0.4), width: 1),
      ),
      child: const Text(
        'Beta',
        style: TextStyle(
          color: Color(0xFF00BCD4),
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── 骨架繪製器 (與原版完全相同) ──────────────────────────────────────
class _BodySkeletonPainter extends CustomPainter {
  final PoseData data;
  final double threshold;

  _BodySkeletonPainter(this.data, this.threshold);

  bool _valid(Offset p) =>
      p.dx > 0.02 && p.dx < 0.98 && p.dy > 0.02 && p.dy < 0.98;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.keypoints.isEmpty || data.scores.isEmpty) return;

    final bodyVisible = List.generate(17, (i) => i)
        .where((i) =>
            i < data.scores.length &&
            data.scores[i] > threshold &&
            i < data.keypoints.length &&
            _valid(data.keypoints[i]))
        .length;
    if (bodyVisible < 3) return;

    final bonePaint = Paint()
      ..color = const Color(0xFF00E5FF).withOpacity(0.8)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final jointPaint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..style = PaintingStyle.fill;

    for (final conn in _skeletonConnections) {
      final a = conn[0], b = conn[1];
      if (a >= data.keypoints.length || b >= data.keypoints.length) continue;
      if (a >= data.scores.length || b >= data.scores.length) continue;
      if (data.scores[a] < threshold || data.scores[b] < threshold) continue;

      final pa = data.keypoints[a];
      final pb = data.keypoints[b];
      if (!_valid(pa) || !_valid(pb)) continue;

      final dx = (pa.dx - pb.dx) * size.width;
      final dy = (pa.dy - pb.dy) * size.height;
      if ((dx * dx + dy * dy) > size.width * size.width * 0.5) continue;

      canvas.drawLine(
        Offset(pa.dx * size.width, pa.dy * size.height),
        Offset(pb.dx * size.width, pb.dy * size.height),
        bonePaint,
      );
    }

    for (int i = 0; i < data.keypoints.length; i++) {
      if (i >= data.scores.length || data.scores[i] < threshold) continue;
      final p = data.keypoints[i];
      if (!_valid(p)) continue;
      canvas.drawCircle(
        Offset(p.dx * size.width, p.dy * size.height),
        i < 17 ? 5 : 3,
        jointPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_BodySkeletonPainter old) => true;
}

// ── 骨架補幀過渡引擎 (與原版完全相同) ────────────────────────────────
class PoseDataTween extends Tween<PoseData> {
  PoseDataTween({super.begin, super.end});

  @override
  PoseData lerp(double t) {
    final b = begin ?? PoseData.empty();
    final e = end ?? PoseData.empty();

    if (b.keypoints.isEmpty ||
        e.keypoints.isEmpty ||
        b.keypoints.length != e.keypoints.length) {
      return e;
    }

    final lerpedPoints = <Offset>[];
    for (int i = 0; i < e.keypoints.length; i++) {
      lerpedPoints.add(Offset.lerp(b.keypoints[i], e.keypoints[i], t)!);
    }
    return PoseData(lerpedPoints, e.scores);
  }
}