// lib/features/stats/badges_card.dart
//
// 成就徽章卡:4 大類共 12 個徽章
// - 點徽章看詳情
// - 已解鎖顯示彩色圖示,尚未解鎖顯示灰色鎖頭

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/history_service.dart';
import 'stats_calculator.dart';

class BadgesCard extends StatefulWidget {
  const BadgesCard({super.key});

  @override
  State<BadgesCard> createState() => _BadgesCardState();
}

class _BadgesCardState extends State<BadgesCard> {
  final _calculator = StatsCalculator();
  List<Achievement> _achievements = [];
  bool _loading = true;

  Future<void> _load() async {
    final data = await _calculator.getAchievements();
    if (!mounted) return;
    setState(() {
      _achievements = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<HistoryService>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });

    final unlockedCount = _achievements.where((a) => a.unlocked).length;
    final total = _achievements.length;

    return Container(
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
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.emoji_events_rounded,
                    color: Color(0xFFF59E0B), size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '成就徽章',
                      style: TextStyle(
                        color: Color(0xFF374151),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _loading ? '載入中...' : '$unlockedCount / $total 已解鎖',
                      style: const TextStyle(
                          color: Color(0xFF9CA3AF), fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_loading)
            const SizedBox(
              height: 60,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else ...[
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              children: _achievements
                  .map((a) => _buildBadge(a))
                  .toList(),
            ),
            const SizedBox(height: 8),
            const Text(
              '點徽章看詳情',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBadge(Achievement a) {
    final color = _colorFor(a.category);
    final icon = _iconFor(a.category);

    return GestureDetector(
      onTap: () => _showDetail(a),
      child: Container(
        decoration: BoxDecoration(
          color: a.unlocked
              ? color.withValues(alpha: 0.12)
              : const Color(0xFFF5F6FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: a.unlocked
                ? color.withValues(alpha: 0.3)
                : const Color(0xFFDDE0F0),
          ),
        ),
        child: Center(
          child: Icon(
            a.unlocked ? icon : Icons.lock_outline,
            color: a.unlocked ? color : const Color(0xFF9CA3AF),
            size: 24,
          ),
        ),
      ),
    );
  }

  IconData _iconFor(BadgeCategory c) => switch (c) {
        BadgeCategory.streak => Icons.local_fire_department_rounded,
        BadgeCategory.volume => Icons.fitness_center_rounded,
        BadgeCategory.intensity => Icons.bolt_rounded,
        BadgeCategory.accuracy => Icons.gps_fixed_rounded,
      };

  Color _colorFor(BadgeCategory c) => switch (c) {
        BadgeCategory.streak => const Color(0xFFEF4444),   // 紅 - 熱情
        BadgeCategory.volume => const Color(0xFF4A65FF),   // 藍 - 累積
        BadgeCategory.intensity => const Color(0xFFF59E0B), // 橙 - 爆發
        BadgeCategory.accuracy => const Color(0xFF10B981),  // 綠 - 精準
      };

  String _categoryName(BadgeCategory c) => switch (c) {
        BadgeCategory.streak => '堅持系',
        BadgeCategory.volume => '累積系',
        BadgeCategory.intensity => '強度系',
        BadgeCategory.accuracy => '精準系',
      };

  void _showDetail(Achievement a) {
    final color = _colorFor(a.category);
    final icon = _iconFor(a.category);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: a.unlocked
                    ? color.withValues(alpha: 0.15)
                    : const Color(0xFFF5F6FA),
                shape: BoxShape.circle,
              ),
              child: Icon(
                a.unlocked ? icon : Icons.lock_outline,
                color: a.unlocked ? color : const Color(0xFF9CA3AF),
                size: 32,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              a.name,
              style: const TextStyle(
                color: Color(0xFF1A1D2E),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _categoryName(a.category),
                style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              a.description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Color(0xFF6B7280), fontSize: 13, height: 1.5),
            ),
            if (a.unlocked && a.unlockedAt != null) ...[
              const SizedBox(height: 10),
              Text(
                '解鎖於 ${_formatDate(a.unlockedAt!)}',
                style: const TextStyle(
                    color: Color(0xFF10B981),
                    fontSize: 11,
                    fontWeight: FontWeight.w700),
              ),
            ] else ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F6FA),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lightbulb_outline,
                        color: Color(0xFF9CA3AF), size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        a.hint,
                        style: const TextStyle(
                            color: Color(0xFF6B7280), fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('關閉',
                style: TextStyle(color: Color(0xFF6B7280))),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.year}/${dt.month.toString().padLeft(2, '0')}/'
      '${dt.day.toString().padLeft(2, '0')}';
}