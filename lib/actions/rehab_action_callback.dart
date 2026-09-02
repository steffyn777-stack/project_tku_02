// lib/actions/rehab_action_callback.dart

abstract class RehabActionCallback {
  void onFeedbackChanged(String feedback, String instruction);

  void onStatsChanged({
    int? repCount,
    double? accuracy,
    double? progress,
    int? speedState,
  });

  /// 翻掌專用：倒數狀態變化
  void onCountdownChanged({
    required bool isCountingDown,
    required int seconds,
    required bool isDone,
  });

  void onLevelUp({
    required int newLevel,
    required String levelLabel,
    required int newTargetReps,
  });

  // 🆕 達標了,等待使用者確認要不要升級(尚未真正升級)
  void onLevelUpReady({
    required int nextLevel,
    required String nextLevelLabel,
  });

  void onTrainingComplete({
    required int repCount,
    required int durationSeconds,
    required List<String> mistakeLogs,
  });
}