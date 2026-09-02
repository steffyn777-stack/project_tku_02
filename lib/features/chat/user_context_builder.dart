// lib/features/chat/user_context_builder.dart
//
// 負責:把 HistoryService 的訓練紀錄 + PlanRepository 的今日計畫,
// 轉換成 chat_repository.dart 需要的 UserContext。
//
// 邏輯直接沿用 home_screen.dart 裡 _HomeContentState 已經寫好的
// _calcStreak / _calcTodayAccuracy 演算法,確保跟首頁顯示的數字一致。

import '../../services/history_service.dart';
import '../../models/training_action.dart';
import 'chat_repository.dart';

class UserContextBuilder {
  final HistoryService _historyService = HistoryService();

  Future<UserContext> build() async {
    final records = await _historyService.getHistory();

    final streak = _calcStreak(records);
    final lastScore = _calcLastScore(records);
    final weekly = _calcWeeklyCompleted(records);

    // currentLevel 沒有全域儲存的地方(是每次訓練session才有的狀態),
    // 先用「最近一次訓練紀錄的難度」代表目前程度
    final currentLevel = records.isNotEmpty ? records.last.difficulty : 1;

    return UserContext(
      name: '使用者', // 之後有帳號系統再換成真實姓名
      currentLevel: currentLevel,
      weeklyCompleted: weekly.completed,
      weeklyTarget: weekly.target,
      streak: streak,
      lastScore: lastScore,
    );
  }

  // ── 以下三個method邏輯照抄 home_screen.dart,確保跟首頁顯示一致 ──

  int _calcStreak(List<TrainingRecord> records) {
    if (records.isEmpty) return 0;

    final days = records.map((r) => r.timestamp.substring(0, 10)).toSet();

    final now = DateTime.now();
    final todayStr = _formatDate(now);
    final yesterdayStr = _formatDate(now.subtract(const Duration(days: 1)));

    DateTime anchor;
    if (days.contains(todayStr)) {
      anchor = now;
    } else if (days.contains(yesterdayStr)) {
      anchor = now.subtract(const Duration(days: 1));
    } else {
      return 0;
    }

    int streak = 0;
    DateTime check = anchor;
    while (days.contains(_formatDate(check))) {
      streak++;
      check = check.subtract(const Duration(days: 1));
    }
    return streak;
  }

  // 用「最後一次訓練」的準確度公式,當作最近一次評分
  double? _calcLastScore(List<TrainingRecord> records) {
    if (records.isEmpty) return null;
    final last = records.last;
    final acc = ((10 - last.mistakeLogs.length) / 10 * 100).clamp(0, 100);
    return acc.toDouble();
  }

  // 本週(過去7天,含今天)有幾天練過 / 7天為目標
  // 注意:這跟「計畫裡的每日項目」不是同一件事,是用「有無訓練紀錄」概算週頻率
  ({int completed, int target}) _calcWeeklyCompleted(List<TrainingRecord> records) {
    final now = DateTime.now();
    final last7Days = List.generate(
      7,
      (i) => _formatDate(now.subtract(Duration(days: i))),
    ).toSet();

    final trainedDays = records
        .map((r) => r.timestamp.substring(0, 10))
        .toSet()
        .where((d) => last7Days.contains(d))
        .length;

    return (completed: trainedDays, target: 7);
  }

  String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}