// lib/widgets/training_overlays.dart

import 'package:flutter/material.dart';

// ── TopBar ────────────────────────────────────────────────────────────────────

class TrainingTopBar extends StatelessWidget {
  final String actionName;
  final String difficultyDesc;
  final VoidCallback onBack;
  final VoidCallback onFlipCamera;

  const TrainingTopBar({
    super.key,
    required this.actionName,
    required this.difficultyDesc,
    required this.onBack,
    required this.onFlipCamera,
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
                  style: const TextStyle(
                      color: Color(0xFF6B7280), fontSize: 12),
                ),
              ],
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

// ── CoachCard ─────────────────────────────────────────────────────────────────

class CoachCard extends StatelessWidget {
  final String feedback;
  final String instruction;

  const CoachCard({
    super.key,
    required this.feedback,
    required this.instruction,
  });

  @override
  Widget build(BuildContext context) {
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
                  feedback,
                  style: const TextStyle(
                    color: Color(0xFF1A1D2E),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (instruction.isNotEmpty)
                  Text(
                    instruction,
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
}

// ── LoadingOverlay(維持深色,因為是 loading 蓋住相機)─────────────────────

class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
                color: Color(0xFF4A65FF), strokeWidth: 3),
            SizedBox(height: 16),
            Text(
              '正在啟動 AI 引擎...',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

// ── NoHandOverlay(維持深色覆蓋層,提示對比夠)────────────────────────────

class NoHandOverlay extends StatelessWidget {
  final Animation<double> pulseAnim;

  const NoHandOverlay({super.key, required this.pulseAnim});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.4),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: pulseAnim,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF4A65FF).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF4A65FF).withValues(alpha: 0.5),
                    width: 2,
                  ),
                ),
                child: const Icon(Icons.back_hand_outlined,
                    color: Color(0xFF4A65FF), size: 40),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '請將手放入鏡頭範圍內',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(blurRadius: 8, color: Colors.black)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── CountdownOverlay(維持深色圓圈,在相機上看得清楚)─────────────────────

class CountdownOverlay extends StatelessWidget {
  final int seconds;

  const CountdownOverlay({super.key, required this.seconds});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 16,
      right: 16,
      child: TweenAnimationBuilder<double>(
        key: ValueKey(seconds),
        tween: Tween(begin: 1.3, end: 1.0),
        duration: const Duration(milliseconds: 350),
        curve: Curves.elasticOut,
        builder: (_, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            shape: BoxShape.circle,
            border: Border.all(
              color: seconds <= 2
                  ? const Color(0xFF4CAF50)
                  : const Color(0xFFFF9800),
              width: 3,
            ),
          ),
          child: Center(
            child: Text(
              '$seconds',
              style: TextStyle(
                color: seconds <= 2
                    ? const Color(0xFF4CAF50)
                    : const Color(0xFFFF9800),
                fontSize: 34,
                fontWeight: FontWeight.w900,
                shadows: const [Shadow(blurRadius: 8, color: Colors.black)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
