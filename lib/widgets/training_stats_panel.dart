// lib/widgets/training_stats_panel.dart
//
// ✅ 新增:targetReps 參數,顯示動態目標次數而非寫死 10

import 'package:flutter/material.dart';
import '../models/training_action.dart';

class TrainingStatsPanel extends StatelessWidget {
  final bool isCountingDown;
  final bool countdownDone;
  final int countdownSeconds;
  final ActionType actionType;
  final int repCount;
  final int targetReps;   // ← 新增
  final double accuracy;
  final VoidCallback onStopPressed;

  const TrainingStatsPanel({
    super.key,
    required this.isCountingDown,
    required this.countdownDone,
    required this.countdownSeconds,
    required this.actionType,
    required this.repCount,
    this.targetReps = 10,   // ← 新增,預設 10
    required this.accuracy,
    required this.onStopPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(child: _buildRepCard()),
          const SizedBox(width: 12),
          Expanded(child: _buildAccuracyCard()),
          const SizedBox(width: 12),
          _buildStopButton(),
        ],
      ),
    );
  }

  Widget _buildRepCard() {
    final String label;
    final String value;
    final Color valueColor;

    if (isCountingDown) {
      label = '保持倒數';
      value = '$countdownSeconds 秒';
      valueColor = countdownSeconds <= 2
          ? const Color(0xFF4CAF50)
          : const Color(0xFFFF9800);
    } else if (!countdownDone && actionType == ActionType.turnPalm) {
      label = '準備中';
      value = '對齊棍子';
      valueColor = const Color(0xFF8A8D9F);
    } else {
      label = '完成次數';
      value = '$repCount / $targetReps';   // ← 改這行,用動態值
      valueColor = const Color(0xFF2C3040);
    }

    return _StatCard(label: label, value: value, valueColor: valueColor);
  }

  Widget _buildAccuracyCard() {
    return _StatCard(
      label: '動作角度',
      value: accuracy > 0 ? '${accuracy.toStringAsFixed(0)}°' : '--°',
      valueColor: const Color(0xFF4A65FF),
    );
  }

  Widget _buildStopButton() {
    return GestureDetector(
      onTap: onStopPressed,
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
}

// ── 共用小卡片 ────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _StatCard({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
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
            style: TextStyle(
              color: valueColor,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
