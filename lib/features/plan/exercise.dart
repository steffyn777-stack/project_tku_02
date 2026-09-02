enum ExerciseCategory { hand, fullBody } // 手部, 全身

class Exercise {
  final String id;
  final String name;
  final String icon;
  final ExerciseCategory category;
  final String level;
  final int defaultMinutes;

  const Exercise({
    required this.id,
    required this.name,
    required this.icon,
    required this.category,
    required this.level,
    required this.defaultMinutes,
  });
}

const List<Exercise> exerciseLibrary = [
  // 手部
  Exercise(id: 'ex01', name: '翻掌訓練', icon: '🤚', category: ExerciseCategory.hand, level: '初階', defaultMinutes: 6),
  Exercise(id: 'ex02', name: '側捏訓練', icon: '🤏', category: ExerciseCategory.hand, level: '初階', defaultMinutes: 6),
  Exercise(id: 'ex03', name: '翹手腕式', icon: '✋', category: ExerciseCategory.hand, level: '初階', defaultMinutes: 6),
  Exercise(id: 'ex04', name: '左右彎手腕式', icon: '🔄', category: ExerciseCategory.hand, level: '初階', defaultMinutes: 6),
  // 全身
  Exercise(id: 'ex05', name: '畫圓訓練', icon: '⭕', category: ExerciseCategory.fullBody, level: '初階', defaultMinutes: 8),
  Exercise(id: 'ex06', name: '伸手舉高訓練', icon: '🙋', category: ExerciseCategory.fullBody, level: '初階', defaultMinutes: 8),
  Exercise(id: 'ex07', name: '雙手抬舉式', icon: '💪', category: ExerciseCategory.fullBody, level: '中階', defaultMinutes: 10),
  Exercise(id: 'ex08', name: '側跨步訓練', icon: '🚶', category: ExerciseCategory.fullBody, level: '中階', defaultMinutes: 10),
  Exercise(id: 'ex09', name: '手肘屈伸訓練', icon: '💪', category: ExerciseCategory.fullBody, level: '初階', defaultMinutes: 8),
  Exercise(id: 'ex10', name: '坐站訓練', icon: '🪑', category: ExerciseCategory.fullBody, level: '中階', defaultMinutes: 10),
  Exercise(id: 'ex11', name: '站姿抬腳式訓練', icon: '🦵', category: ExerciseCategory.fullBody, level: '中階', defaultMinutes: 10),
];

Exercise findExerciseById(String id) =>
    exerciseLibrary.firstWhere((e) => e.id == id);