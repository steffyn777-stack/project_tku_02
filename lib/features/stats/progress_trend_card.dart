// lib/features/stats/progress_trend_card.dart
//
// 進步軌跡卡:練最多次的動作,準確度隨時間的折線圖
// 大字顯示「進步 +X%」,把抽象的努力變成看得見的成長

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/history_service.dart';
import 'stats_calculator.dart';

class ProgressTrendCard extends StatefulWidget {
  const ProgressTrendCard({super.key});

  @override
  State<ProgressTrendCard> createState() => _ProgressTrendCardState();
}

class _ProgressTrendCardState extends State<ProgressTrendCard> {
  final _calculator = StatsCalculator();
  ProgressTrend _trend = ProgressTrend.empty;
  bool _loading = true;

  Future<void> _load() async {
    final data = await _calculator.getProgressTrend();
    if (!mounted) return;
    setState(() {
      _trend = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<HistoryService>();
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
                  color: const Color(0xFFD1FAE5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.trending_up_rounded,
                    color: Color(0xFF10B981), size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '進步軌跡',
                      style: TextStyle(
                        color: Color(0xFF374151),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '你練最多的動作,成長看得見',
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
        height: 160,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (!_trend.hasEnoughData) {
      return Container(
        height: 160,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFF5F6FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDDE0F0)),
        ),
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '同一個動作練滿 3 次\n就能看到你的進步曲線',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ),
      );
    }

    final improved = _trend.improvement >= 0;
    final improveColor =
        improved ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 動作名 + 進步幅度大字
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _trend.actionName,
                    style: const TextStyle(
                      color: Color(0xFF1A1D2E),
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '共 ${_trend.accuracies.length} 次紀錄',
                    style: const TextStyle(
                        color: Color(0xFF9CA3AF), fontSize: 11),
                  ),
                ],
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  improved
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  color: improveColor,
                  size: 20,
                ),
                Text(
                  '${_trend.improvement.abs()}%',
                  style: TextStyle(
                    color: improveColor,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 折線圖
        SizedBox(
          height: 120,
          child: LayoutBuilder(
            builder: (_, c) => CustomPaint(
              size: Size(c.maxWidth, c.maxHeight),
              painter: _TrendPainter(
                accuracies: _trend.accuracies,
                lineColor: improveColor,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // 一句鼓勵
        Text(
          _encourageText(improved, _trend.improvement),
          style: TextStyle(
            color: improveColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  String _encourageText(bool improved, int diff) {
    if (diff == 0) return '維持穩定,繼續保持這個水準!';
    if (improved) {
      if (diff >= 20) return '進步超多!你真的很努力 💪';
      if (diff >= 10) return '穩定進步中,持續加油!';
      return '有在進步,一點一滴累積起來';
    }
    return '最近有點退步,別氣餒,慢慢調整回來';
  }
}

// ═══════════════════════════════════════
//  折線圖畫筆
// ═══════════════════════════════════════
class _TrendPainter extends CustomPainter {
  final List<double> accuracies;
  final Color lineColor;

  _TrendPainter({required this.accuracies, required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    if (accuracies.length < 2) return;

    const padding = 8.0;
    final chartW = size.width - padding * 2;
    final chartH = size.height - padding * 2;

    // Y 軸固定 0~100
    double xFor(int i) =>
        padding + chartW * (i / (accuracies.length - 1));
    double yFor(double acc) =>
        padding + chartH * (1 - acc / 100);

    // 背景橫線(25/50/75)
    final gridPaint = Paint()
      ..color = const Color(0xFFF0F1F5)
      ..strokeWidth = 1;
    for (final v in [25.0, 50.0, 75.0]) {
      final y = yFor(v);
      canvas.drawLine(Offset(padding, y),
          Offset(size.width - padding, y), gridPaint);
    }

    // 漸層填充區
    final fillPath = Path()..moveTo(xFor(0), yFor(accuracies[0]));
    for (int i = 1; i < accuracies.length; i++) {
      fillPath.lineTo(xFor(i), yFor(accuracies[i]));
    }
    fillPath.lineTo(xFor(accuracies.length - 1), size.height - padding);
    fillPath.lineTo(xFor(0), size.height - padding);
    fillPath.close();
    canvas.drawPath(
      fillPath,
      Paint()..color = lineColor.withValues(alpha: 0.1),
    );

    // 折線
    final linePath = Path()..moveTo(xFor(0), yFor(accuracies[0]));
    for (int i = 1; i < accuracies.length; i++) {
      linePath.lineTo(xFor(i), yFor(accuracies[i]));
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );

    // 資料點
    for (int i = 0; i < accuracies.length; i++) {
      final pt = Offset(xFor(i), yFor(accuracies[i]));
      canvas.drawCircle(pt, 4, Paint()..color = lineColor);
      canvas.drawCircle(
        pt,
        4,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // 頭尾標數字(第一次 vs 最近)
    _drawLabel(canvas, '${accuracies.first.round()}%',
        Offset(xFor(0), yFor(accuracies.first)), true);
    _drawLabel(
        canvas,
        '${accuracies.last.round()}%',
        Offset(xFor(accuracies.length - 1),
            yFor(accuracies.last)),
        false);
  }

  void _drawLabel(Canvas canvas, String text, Offset pt, bool isFirst) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: lineColor,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = isFirst ? pt.dx : pt.dx - tp.width;
    tp.paint(canvas, Offset(dx, pt.dy - 16));
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.accuracies != accuracies || old.lineColor != lineColor;
}