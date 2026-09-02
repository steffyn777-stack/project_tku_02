// lib/features/stats/week_summary_card.dart
//
// 本週摘要卡:訓練次數、平均準確度、時長 + 對比上週

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/history_service.dart';
import 'stats_calculator.dart';

class WeekSummaryCard extends StatefulWidget {
  const WeekSummaryCard({super.key});

  @override
  State<WeekSummaryCard> createState() => _WeekSummaryCardState();
}

class _WeekSummaryCardState extends State<WeekSummaryCard> {
  final _calculator = StatsCalculator();
  WeeklySummary _summary = WeeklySummary.empty;
  bool _loading = true;

  Future<void> _load() async {
    final data = await _calculator.getWeeklySummary();
    if (!mounted) return;
    setState(() {
      _summary = data;
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4A65FF), Color(0xFF7B5EA7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '本週摘要',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          if (_loading)
            const SizedBox(
              height: 60,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: _stat(
                      '${_summary.sessions} 組', '訓練次數'),
                ),
                Expanded(
                  child: _stat(
                      _summary.sessions == 0
                          ? '--'
                          : '${_summary.avgAccuracy} %',
                      '平均準確度'),
                ),
                Expanded(
                  child: _stat(
                      '${_summary.totalMinutes} 分', '訓練時長'),
                ),
              ],
            ),
          const SizedBox(height: 12),
          _buildDiffBadge(),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildDiffBadge() {
    final diff = _summary.diffFromLastWeek;
    String text;
    IconData? icon;

    if (diff == null) {
      text = '目前沒有足夠的紀錄可以對比';
      icon = null;
    } else if (diff > 0) {
      text = '比上週多 $diff 組,繼續保持!';
      icon = Icons.trending_up_rounded;
    } else if (diff < 0) {
      text = '比上週少 ${-diff} 組,加油喔';
      icon = Icons.trending_down_rounded;
    } else {
      text = '跟上週一樣穩定';
      icon = Icons.trending_flat_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}