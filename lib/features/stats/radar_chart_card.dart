// lib/features/stats/radar_chart_card.dart
//
// 雷達圖卡片:顯示近 30 天各動作準確度
// - 至少 3 個動作才會畫出雷達(不然給引導提示)
// - 點軸上的動作名 → 跳歷史頁並帶篩選

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'stats_calculator.dart';
import '../history/history_screen.dart';
import 'package:provider/provider.dart';
import '../../services/history_service.dart';

class RadarChartCard extends StatefulWidget {
  const RadarChartCard({super.key});

  @override
  State<RadarChartCard> createState() => _RadarChartCardState();
}

class _RadarChartCardState extends State<RadarChartCard> {
  final _calculator = StatsCalculator();
  List<RadarAxis> _axes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await _calculator.getRecentRadarData(daysBack: 30);
    if (!mounted) return;
    setState(() {
      _axes = data;
      _loading = false;
    });
  }

  void _openHistoryFor(String actionName) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const HistoryScreen(),
      ),
    );
    // 注意:歷史頁目前沒接受初始篩選參數,未來要接的話在 HistoryScreen 加個 initialAction 參數即可
  }

  @override
  Widget build(BuildContext context) {
    // 訂閱 HistoryService,值變了會 rebuild
    context.watch<HistoryService>();
    // rebuild 就重新載入(延到下一幀,避免 build 時 setState)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E7FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.radar_rounded,
                    color: Color(0xFF4A65FF), size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '弱項動作雷達',
                      style: TextStyle(
                        color: Color(0xFF374151),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '近 30 天,弱項在前',
                      style: TextStyle(
                          color: Color(0xFF9CA3AF), fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildBody(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const SizedBox(
        height: 240,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_axes.length < 3) {
      return _buildLockedHint();
    }

    return Column(
      children: [
        SizedBox(
          height: 260,
          child: LayoutBuilder(
            builder: (_, c) => GestureDetector(
              onTapUp: (details) => _handleTap(
                details.localPosition,
                Size(c.maxWidth, c.maxHeight),
              ),
              child: CustomPaint(
                painter: _RadarPainter(axes: _axes),
                size: Size(c.maxWidth, c.maxHeight),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '點動作名稱看歷史紀錄',
          style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildLockedHint() {
    final count = _axes.length;
    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE0F0)),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.radar_rounded,
                size: 40, color: Color(0xFF9CA3AF)),
            const SizedBox(height: 12),
            Text(
              '至少練 3 種不同動作\n雷達圖就會出現',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF4A65FF).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '目前 $count / 3',
                style: const TextStyle(
                  color: Color(0xFF4A65FF),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 判斷點擊落在哪個軸的標籤位置
  void _handleTap(Offset pos, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 40;
    final n = _axes.length;

    for (int i = 0; i < n; i++) {
      final angle = -math.pi / 2 + (2 * math.pi / n) * i;
      final labelPos = Offset(
        center.dx + math.cos(angle) * (radius + 22),
        center.dy + math.sin(angle) * (radius + 22),
      );
      if ((pos - labelPos).distance < 40) {
        _openHistoryFor(_axes[i].actionName);
        return;
      }
    }
  }
}

// ═══════════════════════════════════════════════
//  雷達圖畫筆
// ═══════════════════════════════════════════════
class _RadarPainter extends CustomPainter {
  final List<RadarAxis> axes;

  _RadarPainter({required this.axes});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 40;
    final n = axes.length;

    // 網格層(20% / 40% / 60% / 80% / 100%)
    final gridPaint = Paint()
      ..color = const Color(0xFFDDE0F0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int layer = 1; layer <= 5; layer++) {
      final r = radius * (layer / 5);
      final path = Path();
      for (int i = 0; i < n; i++) {
        final angle = -math.pi / 2 + (2 * math.pi / n) * i;
        final pt = Offset(
          center.dx + math.cos(angle) * r,
          center.dy + math.sin(angle) * r,
        );
        if (i == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      path.close();
      canvas.drawPath(path, gridPaint);
    }

    // 從中心到每個軸的線
    for (int i = 0; i < n; i++) {
      final angle = -math.pi / 2 + (2 * math.pi / n) * i;
      final end = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      canvas.drawLine(center, end, gridPaint);
    }

    // 資料多邊形(藍色填充)
    final fillPath = Path();
    for (int i = 0; i < n; i++) {
      final angle = -math.pi / 2 + (2 * math.pi / n) * i;
      final r = radius * (axes[i].accuracy / 100);
      final pt = Offset(
        center.dx + math.cos(angle) * r,
        center.dy + math.sin(angle) * r,
      );
      if (i == 0) {
        fillPath.moveTo(pt.dx, pt.dy);
      } else {
        fillPath.lineTo(pt.dx, pt.dy);
      }
    }
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..color = const Color(0xFF4A65FF).withValues(alpha: 0.25)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      fillPath,
      Paint()
        ..color = const Color(0xFF4A65FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // 資料點
    for (int i = 0; i < n; i++) {
      final angle = -math.pi / 2 + (2 * math.pi / n) * i;
      final r = radius * (axes[i].accuracy / 100);
      final pt = Offset(
        center.dx + math.cos(angle) * r,
        center.dy + math.sin(angle) * r,
      );
      canvas.drawCircle(
          pt, 5, Paint()..color = const Color(0xFF4A65FF));
      canvas.drawCircle(
        pt,
        5,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // 動作名稱標籤 + 百分比
    for (int i = 0; i < n; i++) {
      final angle = -math.pi / 2 + (2 * math.pi / n) * i;
      final labelPos = Offset(
        center.dx + math.cos(angle) * (radius + 22),
        center.dy + math.sin(angle) * (radius + 22),
      );

      final tp = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(
              text: axes[i].actionName,
              style: const TextStyle(
                color: Color(0xFF1A1D2E),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: '\n${axes[i].accuracy.toStringAsFixed(0)}%',
              style: const TextStyle(
                color: Color(0xFF4A65FF),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      tp.layout(maxWidth: 80);
      tp.paint(
        canvas,
        Offset(labelPos.dx - tp.width / 2, labelPos.dy - tp.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.axes != axes;
}