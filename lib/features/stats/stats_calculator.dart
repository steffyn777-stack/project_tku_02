// lib/features/stats/stats_calculator.dart
//
// 從 TrainingRecord 算統計 — 目前只算雷達圖用的資料
// 未來擴充成就徽章、個人紀錄等時,新方法都放這裡

import '../../services/history_service.dart';
import '../../models/training_action.dart';

/// 雷達圖一個軸的資料:一個動作 + 這個動作在期間內的平均準確度
class RadarAxis {
  final String actionName;
  final double accuracy; // 0.0 ~ 100.0
  final int recordCount; // 這段期間這個動作練了幾次

  const RadarAxis({
    required this.actionName,
    required this.accuracy,
    required this.recordCount,
  });
}

class StatsCalculator {
  final HistoryService _historyService = HistoryService();

  /// 近 30 天使用者練過的動作 + 各自平均準確度
  /// 回傳的 list 已經按準確度由低到高排序(讓弱項容易被看到)
  Future<List<RadarAxis>> getRecentRadarData({int daysBack = 30}) async {
    final records = await _historyService.getHistory();
    final cutoff = DateTime.now().subtract(Duration(days: daysBack));

    // 篩出時間範圍內的紀錄
    final recent = records.where((r) {
      final dt = DateTime.tryParse(r.timestamp);
      return dt != null && dt.isAfter(cutoff);
    }).toList();

    if (recent.isEmpty) return [];

    // 依動作分組 → 算平均準確度
    final Map<String, List<double>> accByAction = {};
    for (final r in recent) {
      final perfect = (r.targetReps - r.mistakeLogs.length)
          .clamp(0, r.targetReps);
      final acc = r.targetReps > 0
          ? (perfect / r.targetReps * 100)
          : 0.0;
      accByAction.putIfAbsent(r.actionName, () => []).add(acc);
    }

    final axes = accByAction.entries.map((e) {
      final avg = e.value.reduce((a, b) => a + b) / e.value.length;
      return RadarAxis(
        actionName: e.key,
        accuracy: avg,
        recordCount: e.value.length,
      );
    }).toList();

    // 由低到高排序 — 弱項在前面
    axes.sort((a, b) => a.accuracy.compareTo(b.accuracy));
    return axes;
  }

  /// 算出個人紀錄卡需要的四個數字
  Future<PersonalRecords> getPersonalRecords() async {
    final records = await _historyService.getHistory();
    if (records.isEmpty) return PersonalRecords.empty;

    // 累積組數
    final total = records.length;

    // 單日最多:把紀錄按日期分組數量最多的那天
    final Map<String, int> byDay = {};
    for (final r in records) {
      final day = r.timestamp.substring(0, 10); // YYYY-MM-DD
      byDay[day] = (byDay[day] ?? 0) + 1;
    }
    final maxDaily =
        byDay.values.fold<int>(0, (max, v) => v > max ? v : max);

    // 最高單組準確度
    int maxAcc = 0;
    for (final r in records) {
      if (r.targetReps <= 0) continue;
      final perfect =
          (r.targetReps - r.mistakeLogs.length).clamp(0, r.targetReps);
      final acc = (perfect / r.targetReps * 100).round();
      if (acc > maxAcc) maxAcc = acc;
    }

    // 連續達成天數(跟首頁同一套算法)
    final streak = _calcStreak(records.map((r) => r.timestamp).toList());

    return PersonalRecords(
      streakDays: streak,
      maxDailySessions: maxDaily,
      totalSessions: total,
      maxAccuracy: maxAcc,
    );
  }

  int _calcStreak(List<String> timestamps) {
    final days = timestamps.map((t) => t.substring(0, 10)).toSet();
    if (days.isEmpty) return 0;

    final now = DateTime.now();
    final todayStr = _formatDate(now);
    final yesterdayStr = _formatDate(now.subtract(const Duration(days: 1)));

    DateTime? anchor;
    if (days.contains(todayStr)) {
      anchor = now;
    } else if (days.contains(yesterdayStr)) {
      anchor = now.subtract(const Duration(days: 1));
    } else {
      return 0;
    }

    int streak = 0;
    var check = anchor;
    while (days.contains(_formatDate(check))) {
      streak++;
      check = check.subtract(const Duration(days: 1));
    }
    return streak;
  }

  String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// 算出本週摘要卡需要的數字
  Future<WeeklySummary> getWeeklySummary() async {
    final records = await _historyService.getHistory();
    if (records.isEmpty) return WeeklySummary.empty;

    final now = DateTime.now();
    // 本週從週一 00:00 開始算
    final startOfThisWeek =
        DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
    final startOfLastWeek =
        startOfThisWeek.subtract(const Duration(days: 7));

    final thisWeek = <TrainingRecord>[];
    final lastWeek = <TrainingRecord>[];

    for (final r in records) {
      final dt = DateTime.tryParse(r.timestamp);
      if (dt == null) continue;
      if (!dt.isBefore(startOfThisWeek)) {
        thisWeek.add(r);
      } else if (!dt.isBefore(startOfLastWeek)) {
        lastWeek.add(r);
      }
    }

    // 本週平均準確度
    int avgAcc = 0;
    if (thisWeek.isNotEmpty) {
      double sumAcc = 0;
      int count = 0;
      for (final r in thisWeek) {
        if (r.targetReps <= 0) continue;
        final perfect =
            (r.targetReps - r.mistakeLogs.length).clamp(0, r.targetReps);
        sumAcc += perfect / r.targetReps * 100;
        count++;
      }
      if (count > 0) avgAcc = (sumAcc / count).round();
    }

    // 本週總時長(分鐘)
    final totalSeconds =
        thisWeek.fold<int>(0, (sum, r) => sum + r.durationSeconds);
    final totalMinutes = (totalSeconds / 60).round();

    return WeeklySummary(
      sessions: thisWeek.length,
      avgAccuracy: avgAcc,
      totalMinutes: totalMinutes,
      sessionsLastWeek: lastWeek.length,
    );
  }

  /// 算出所有徽章的解鎖狀態
  Future<List<Achievement>> getAchievements() async {
    final records = await _historyService.getHistory();

    // 先算出所有徽章要用的統計數字
    final total = records.length;
    final firstRecordTime = records.isNotEmpty
        ? DateTime.tryParse(records.first.timestamp)
        : null;

    // 單日組數 map
    final Map<String, List<TrainingRecord>> byDay = {};
    for (final r in records) {
      final day = r.timestamp.substring(0, 10);
      byDay.putIfAbsent(day, () => []).add(r);
    }
    final maxDaily =
        byDay.values.fold<int>(0, (m, v) => v.length > m ? v.length : m);

    // 連續達成天數
    final streak =
        _calcStreak(records.map((r) => r.timestamp).toList());

    // 最高準確度
    int maxAcc = 0;
    DateTime? perfectAt;
    for (final r in records) {
      if (r.targetReps <= 0) continue;
      final perfect =
          (r.targetReps - r.mistakeLogs.length).clamp(0, r.targetReps);
      final acc = (perfect / r.targetReps * 100).round();
      if (acc > maxAcc) maxAcc = acc;
      if (acc == 100 && perfectAt == null) {
        perfectAt = DateTime.tryParse(r.timestamp);
      }
    }

    // 各徽章的解鎖時間(找到達成條件的第一筆紀錄的時間)
    final firstStreakOf = <int, DateTime?>{};
    for (final threshold in [3, 7, 30]) {
      firstStreakOf[threshold] = _findFirstStreakDate(records, threshold);
    }

    final firstTotalOf = <int, DateTime?>{};
    for (final threshold in [1, 25, 100]) {
      firstTotalOf[threshold] = records.length >= threshold
          ? DateTime.tryParse(records[threshold - 1].timestamp)
          : null;
    }

    final firstDailyOf = <int, DateTime?>{};
    for (final threshold in [3, 5]) {
      DateTime? found;
      for (final entry in byDay.entries) {
        if (entry.value.length >= threshold) {
          final dt = DateTime.tryParse(entry.value.last.timestamp);
          if (dt != null && (found == null || dt.isBefore(found))) {
            found = dt;
          }
        }
      }
      firstDailyOf[threshold] = found;
    }

    final firstAccOf = <int, DateTime?>{};
    for (final threshold in [70, 85]) {
      DateTime? found;
      for (final r in records) {
        if (r.targetReps <= 0) continue;
        final perfect =
            (r.targetReps - r.mistakeLogs.length).clamp(0, r.targetReps);
        final acc = (perfect / r.targetReps * 100).round();
        if (acc >= threshold) {
          final dt = DateTime.tryParse(r.timestamp);
          if (dt != null && (found == null || dt.isBefore(found))) {
            found = dt;
          }
        }
      }
      firstAccOf[threshold] = found;
    }

    return [
      // 堅持系
      Achievement(
        id: 'streak_3',
        category: BadgeCategory.streak,
        name: '起步走',
        description: '連續 3 天完成訓練',
        hint: '連續 3 天,證明自己願意開始',
        unlocked: streak >= 3 || (firstStreakOf[3] != null),
        unlockedAt: firstStreakOf[3],
      ),
      Achievement(
        id: 'streak_7',
        category: BadgeCategory.streak,
        name: '一週不倒',
        description: '連續 7 天完成訓練',
        hint: '連續 7 天,養成習慣了',
        unlocked: streak >= 7 || (firstStreakOf[7] != null),
        unlockedAt: firstStreakOf[7],
      ),
      Achievement(
        id: 'streak_30',
        category: BadgeCategory.streak,
        name: '月度王者',
        description: '連續 30 天完成訓練',
        hint: '連續 30 天,你是真的認真的',
        unlocked: streak >= 30 || (firstStreakOf[30] != null),
        unlockedAt: firstStreakOf[30],
      ),

      // 量系
      Achievement(
        id: 'total_1',
        category: BadgeCategory.volume,
        name: '第一步',
        description: '完成第一組訓練',
        hint: '完成第一組訓練即解鎖',
        unlocked: total >= 1,
        unlockedAt: firstRecordTime,
      ),
      Achievement(
        id: 'total_25',
        category: BadgeCategory.volume,
        name: '累積 25 組',
        description: '累積完成 25 組訓練',
        hint: '再累積 ${(25 - total).clamp(1, 25)} 組就解鎖',
        unlocked: total >= 25,
        unlockedAt: firstTotalOf[25],
      ),
      Achievement(
        id: 'total_100',
        category: BadgeCategory.volume,
        name: '百組達人',
        description: '累積完成 100 組訓練',
        hint: '再累積 ${(100 - total).clamp(1, 100)} 組就解鎖',
        unlocked: total >= 100,
        unlockedAt: firstTotalOf[100],
      ),

      // 強度系
      Achievement(
        id: 'daily_3',
        category: BadgeCategory.intensity,
        name: '認真的一天',
        description: '單日完成 3 組訓練',
        hint: '一天內完成 3 組訓練就解鎖',
        unlocked: maxDaily >= 3,
        unlockedAt: firstDailyOf[3],
      ),
      Achievement(
        id: 'daily_5',
        category: BadgeCategory.intensity,
        name: '爆發模式',
        description: '單日完成 5 組訓練',
        hint: '一天內完成 5 組訓練就解鎖',
        unlocked: maxDaily >= 5,
        unlockedAt: firstDailyOf[5],
      ),
      Achievement(
        id: 'perfect',
        category: BadgeCategory.intensity,
        name: '完美主義',
        description: '首次完美完成訓練(零錯誤)',
        hint: '單組訓練零錯誤即解鎖',
        unlocked: perfectAt != null,
        unlockedAt: perfectAt,
      ),

      // 精準系
      Achievement(
        id: 'acc_70',
        category: BadgeCategory.accuracy,
        name: '準確入門',
        description: '單組準確度達 70%',
        hint: '單組準確度達 70% 即解鎖',
        unlocked: maxAcc >= 70,
        unlockedAt: firstAccOf[70],
      ),
      Achievement(
        id: 'acc_85',
        category: BadgeCategory.accuracy,
        name: '穩定高手',
        description: '單組準確度達 85%',
        hint: '單組準確度達 85% 即解鎖',
        unlocked: maxAcc >= 85,
        unlockedAt: firstAccOf[85],
      ),
      Achievement(
        id: 'acc_100',
        category: BadgeCategory.accuracy,
        name: '百分百',
        description: '單組準確度 100%',
        hint: '單組準確度達 100% 即解鎖',
        unlocked: maxAcc >= 100,
        unlockedAt: perfectAt,
      ),
    ];
  }

  /// 找出「練最多次的動作」,回傳它的準確度進步軌跡
  /// 至少要 3 筆紀錄才有意義
  Future<ProgressTrend> getProgressTrend() async {
    final records = await _historyService.getHistory();
    if (records.isEmpty) return ProgressTrend.empty;

    // 依動作分組
    final Map<String, List<TrainingRecord>> byAction = {};
    for (final r in records) {
      byAction.putIfAbsent(r.actionName, () => []).add(r);
    }

    // 找練最多次的動作
    String? topAction;
    int maxCount = 0;
    byAction.forEach((name, list) {
      if (list.length > maxCount) {
        maxCount = list.length;
        topAction = name;
      }
    });

    if (topAction == null || maxCount < 3) {
      return ProgressTrend(
        actionName: topAction ?? '',
        accuracies: const [],
        improvement: 0,
        hasEnoughData: false,
      );
    }

    // 把該動作的紀錄依時間排序(舊 → 新)
    final list = byAction[topAction]!
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // 算每筆的準確度
    final accuracies = <double>[];
    for (final r in list) {
      if (r.targetReps <= 0) {
        accuracies.add(0);
        continue;
      }
      final perfect =
          (r.targetReps - r.mistakeLogs.length).clamp(0, r.targetReps);
      accuracies.add(perfect / r.targetReps * 100);
    }

    // 進步幅度 = 最後一筆 - 第一筆
    final improvement =
        (accuracies.last - accuracies.first).round();

    return ProgressTrend(
      actionName: topAction!,
      accuracies: accuracies,
      improvement: improvement,
      hasEnoughData: true,
    );
  }

  /// 找出使用者第一次達到「連續 X 天」的日期
  DateTime? _findFirstStreakDate(
      List<TrainingRecord> records, int threshold) {
    if (records.isEmpty) return null;

    final days = records
        .map((r) => r.timestamp.substring(0, 10))
        .toSet()
        .toList()
      ..sort();

    int currentStreak = 1;
    DateTime? prevDay;
    for (final dayStr in days) {
      final dt = DateTime.parse(dayStr);
      if (prevDay != null && dt.difference(prevDay).inDays == 1) {
        currentStreak++;
      } else {
        currentStreak = 1;
      }
      if (currentStreak >= threshold) {
        // 找到達成的那一筆紀錄的實際時間
        final match = records.firstWhere(
          (r) => r.timestamp.startsWith(dayStr),
          orElse: () => records.first,
        );
        return DateTime.tryParse(match.timestamp);
      }
      prevDay = dt;
    }
    return null;
  }
}

/// 個人紀錄卡的所有數字
class PersonalRecords {
  final int streakDays;         // 連續達成天數
  final int maxDailySessions;   // 單日最多訓練組數
  final int totalSessions;      // 累積訓練組數
  final int maxAccuracy;        // 最高單組準確度 (0~100)

  const PersonalRecords({
    required this.streakDays,
    required this.maxDailySessions,
    required this.totalSessions,
    required this.maxAccuracy,
  });

  static const empty = PersonalRecords(
    streakDays: 0,
    maxDailySessions: 0,
    totalSessions: 0,
    maxAccuracy: 0,
  );
}

/// 本週摘要卡的所有數字
class WeeklySummary {
  final int sessions;         // 本週訓練組數
  final int avgAccuracy;      // 本週平均準確度 (0~100)
  final int totalMinutes;     // 本週訓練總時長(分鐘)
  final int sessionsLastWeek; // 上週訓練組數(用來對比)

  const WeeklySummary({
    required this.sessions,
    required this.avgAccuracy,
    required this.totalMinutes,
    required this.sessionsLastWeek,
  });

  static const empty = WeeklySummary(
    sessions: 0,
    avgAccuracy: 0,
    totalMinutes: 0,
    sessionsLastWeek: 0,
  );

  /// 相比上週增減:正數表示增加,負數表示減少,null 表示上週沒資料
  int? get diffFromLastWeek {
    if (sessionsLastWeek == 0 && sessions == 0) return null;
    return sessions - sessionsLastWeek;
  }
}

/// 徽章大類
enum BadgeCategory {
  streak,    // 堅持系
  volume,    // 量系
  intensity, // 強度系
  accuracy,  // 精準系
}

/// 一個徽章的定義 + 目前狀態
class Achievement {
  final String id;
  final BadgeCategory category;
  final String name;
  final String description;
  final String hint;         // 尚未解鎖時的提示
  final bool unlocked;
  final DateTime? unlockedAt; // 解鎖時間(有解鎖才有值)

  const Achievement({
    required this.id,
    required this.category,
    required this.name,
    required this.description,
    required this.hint,
    required this.unlocked,
    this.unlockedAt,
  });
}

/// 進步軌跡:某個動作的準確度隨時間變化
class ProgressTrend {
  final String actionName;        // 分析的是哪個動作
  final List<double> accuracies;  // 依時間排序的準確度序列
  final int improvement;          // 進步幅度(最近 - 最初),可負
  final bool hasEnoughData;       // 資料夠不夠畫(至少要幾筆)

  const ProgressTrend({
    required this.actionName,
    required this.accuracies,
    required this.improvement,
    required this.hasEnoughData,
  });

  static const empty = ProgressTrend(
    actionName: '',
    accuracies: [],
    improvement: 0,
    hasEnoughData: false,
  );
}