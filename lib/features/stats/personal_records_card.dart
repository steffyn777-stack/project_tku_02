// lib/features/stats/personal_records_card.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/history_service.dart';
import 'stats_calculator.dart';

class PersonalRecordsCard extends StatefulWidget {
  const PersonalRecordsCard({super.key});

  @override
  State<PersonalRecordsCard> createState() => _PersonalRecordsCardState();
}

class _PersonalRecordsCardState extends State<PersonalRecordsCard> {
  final _calculator = StatsCalculator();
  PersonalRecords _records = PersonalRecords.empty;
  bool _loading = true;

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await _calculator.getPersonalRecords();
    if (!mounted) return;
    setState(() {
      _records = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 訂閱 HistoryService,值變了會觸發 rebuild
    context.watch<HistoryService>();
    // rebuild 就重新載入(延到下一幀,避免 build 時 setState)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });

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
                  color: const Color(0xFFD1FAE5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.local_fire_department_rounded,
                    color: Color(0xFF10B981), size: 20),
              ),
              const SizedBox(width: 10),
              const Text(
                '個人紀錄',
                style: TextStyle(
                  color: Color(0xFF374151),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else ...[
            _row('連續達成天數',
                _records.streakDays == 0
                    ? '尚未開始'
                    : '${_records.streakDays} 天'),
            _divider(),
            _row('單日最多訓練', '${_records.maxDailySessions} 組'),
            _divider(),
            _row('累積訓練組數', '${_records.totalSessions} 組'),
            _divider(),
            _row('最高單組準確度',
                _records.totalSessions == 0
                    ? '--'
                    : '${_records.maxAccuracy} %'),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    final isPlaceholder = value == '尚未開始' || value == '--';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: isPlaceholder
                  ? const Color(0xFF9CA3AF)
                  : const Color(0xFF1A1D2E),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() =>
      const Divider(height: 1, color: Color(0xFFF5F6FA));
}