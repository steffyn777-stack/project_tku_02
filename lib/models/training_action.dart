// lib/models/training_action.dart
//
// ✅ 新增：raiseBothArms, elbowForward, wristExtension, wristSideBend
// ✅ TrainingRecord 新增 videoPath 欄位(訓練錄影)
// ✅ DifficultyOption 新增 targetReps 欄位,每難度各自預設次數(初階多、進階少)
// 🩺 2026-08-20:側蹲、坐站標記為「建議恢復狀況較佳者練習」

enum ActionType {
  turnPalm,
  sidePinch,
  bodyTest,
  wipeBody,
  drawCircle,
  reach,
  raiseBothArms,   
  elbowForward,    
  wristExtension,  // 檢查拼字是否為小寫 w 開頭的 wristExtension
  wristSideBend,   // 檢查拼字是否為小寫 w 開頭的 wristSideBend
  sitToStand, 
  lateralStep,
}

enum DifficultyLevel { level1, level2, level3 }

class TrainingAction {
  final ActionType type;
  final String name;
  final String emoji;
  final String description;
  final List<DifficultyOption> difficulties;

  const TrainingAction({
    required this.type,
    required this.name,
    required this.emoji,
    required this.description,
    required this.difficulties,
  });
}

class DifficultyOption {
  final DifficultyLevel level;
  final String label;
  final String description;
  final int targetReps;

  const DifficultyOption({
    required this.level,
    required this.label,
    required this.description,
    this.targetReps = 10,
  });

  DifficultyOption copyWithReps(int reps) => DifficultyOption(
        level: level,
        label: label,
        description: description,
        targetReps: reps,
      );
}

const List<TrainingAction> kTrainingActions = [
  TrainingAction(
    type: ActionType.turnPalm,
    name: '翻掌訓練',
    emoji: '🖐️',
    description: '訓練手腕旋轉與翻掌控制能力',
    difficulties: [
      DifficultyOption(
          level: DifficultyLevel.level1,
          label: 'Level 1',
          description: '初階 — 容錯較高',
          targetReps: 10),
      DifficultyOption(
          level: DifficultyLevel.level2,
          label: 'Level 2',
          description: '中階 — 要求嚴格',
          targetReps: 8),
    ],
  ),
  TrainingAction(
    type: ActionType.sidePinch,
    name: '側捏訓練',
    emoji: '🤏',
    description: '訓練手指精細動作與捏握力',
    difficulties: [
      DifficultyOption(
          level: DifficultyLevel.level1,
          label: 'Level 1',
          description: '初階 — 微幅側捏',
          targetReps: 10),
      DifficultyOption(
          level: DifficultyLevel.level2,
          label: 'Level 2',
          description: '中階 — 標準動作',
          targetReps: 8),
      DifficultyOption(
          level: DifficultyLevel.level3,
          label: 'Level 3',
          description: '進階 — 連擊模式',
          targetReps: 6),
    ],
  ),
  TrainingAction(
    type: ActionType.wipeBody,
    name: '站姿抬腳式訓練',
    emoji: '🦿',
    description: '站姿下左右抬膝，鍛鍊下肢平衡與核心穩定，腳掌盡量放平往上抬',
    difficulties: [
      DifficultyOption(
          level: DifficultyLevel.level1,
          label: '初級',
          description: '抬膝幅度小 — 高容錯',
          targetReps: 10),
      DifficultyOption(
          level: DifficultyLevel.level2,
          label: '中級',
          description: '抬膝至腰部高度，嚴格檢測身體晃動',
          targetReps: 8),
      DifficultyOption(
          level: DifficultyLevel.level3,
          label: '高級',
          description: '抬膝過腰並定格 2 秒',
          targetReps: 6),
    ],
  ),
  TrainingAction(
    type: ActionType.drawCircle,
    name: '畫圓訓練',
    emoji: '⭕',
    description: '訓練肩關節活動度與手臂畫圓控制，上半圓大拇指朝上，下半圓自然下垂',
    difficulties: [
      DifficultyOption(
          level: DifficultyLevel.level1, label: '初級', description: '小圓 — 高容錯',
          targetReps: 10),
      DifficultyOption(
          level: DifficultyLevel.level2, label: '中級', description: '標準圓',
          targetReps: 8),
      DifficultyOption(
          level: DifficultyLevel.level3, label: '高級', description: '大圓 — 要求手臂完全伸直',
          targetReps: 6),
    ],
  ),
  TrainingAction(
    type: ActionType.reach,
    name: '伸手舉高訓練',
    emoji: '🙋',
    description: '訓練肩關節上舉活動度與肌肉控制',
    difficulties: [
      DifficultyOption(
          level: DifficultyLevel.level1, label: '初級', description: '舉過肩膀即可',
          targetReps: 10),
      DifficultyOption(
          level: DifficultyLevel.level2, label: '中級', description: '舉過頭頂',
          targetReps: 8),
      DifficultyOption(
          level: DifficultyLevel.level3, label: '高級', description: '舉過頭頂並定格 3 秒',
          targetReps: 6),
    ],
  ),
  TrainingAction(
    type: ActionType.bodyTest,
    name: '全身骨架偵測',
    emoji: '🦴',
    description: 'RTMPose 全身 133 關鍵點即時追蹤',
    difficulties: [
      DifficultyOption(
          level: DifficultyLevel.level1, label: 'Beta', description: '測試模式',
          targetReps: 10),
    ],
  ),

  // ── 新增 4 個動作 ──────────────────────────────────────────

  TrainingAction(
    type: ActionType.raiseBothArms,
    name: '雙手抬舉式',
    emoji: '🙌',
    description: '雙手交扣往上抬舉,訓練肩膀活動度與核心穩定，舉到最高時大拇指朝上',
    difficulties: [
      DifficultyOption(
          level: DifficultyLevel.level1,
          label: '初級',
          description: '抬到肩膀水平即可',
          targetReps: 10),
      DifficultyOption(
          level: DifficultyLevel.level2,
          label: '中級',
          description: '抬過頭頂並撐住 2 秒',
          targetReps: 8),
      DifficultyOption(
          level: DifficultyLevel.level3,
          label: '高級',
          description: '抬到最高位置撐住 3 秒',
          targetReps: 6),
    ],
  ),
  TrainingAction(
    type: ActionType.elbowForward,
    name: '手肘屈伸訓練',
    emoji: '🤲',
    description: '雙手交扣後手肘來回伸直收回,訓練手肘關節活動度',
    difficulties: [
      DifficultyOption(
          level: DifficultyLevel.level1,
          label: '初級',
          description: '手肘伸到接近 130 度',
          targetReps: 10),
      DifficultyOption(
          level: DifficultyLevel.level2,
          label: '中級',
          description: '手肘伸直到 150 度並撐住 2 秒',
          targetReps: 8),
      DifficultyOption(
          level: DifficultyLevel.level3,
          label: '高級',
          description: '手肘完全伸直並撐住 3 秒',
          targetReps: 6),
    ],
  ),
  TrainingAction(
    type: ActionType.wristExtension,
    name: '翹手腕式',
    emoji: '🤚',
    description: '手腕背屈與掌屈來回訓練，從空手到拿水壺循序漸進',
    difficulties: [
      DifficultyOption(
          level: DifficultyLevel.level1,
          label: 'Level 1',
          description: '空手 — 手腕上下彎曲',
          targetReps: 10),
      DifficultyOption(
          level: DifficultyLevel.level2,
          label: 'Level 2',
          description: '拿水壺 — 加重訓練，幅度要求更大',
          targetReps: 8),
    ],
  ),
  TrainingAction(
    type: ActionType.wristSideBend,
    name: '左右彎手腕式',
    emoji: '↔️',
    description: '手腕橈偏與尺偏來回訓練，改善手腕側向活動度',
    difficulties: [
      DifficultyOption(
          level: DifficultyLevel.level1,
          label: '標準',
          description: '手腕左右來回彎曲，完成 10 次',
          targetReps: 10),
    ],
  ),
  TrainingAction(
    type: ActionType.sitToStand,
    name: '坐站訓練',
    emoji: '🪑',
    description: '訓練腿部力量與站起穩定度（建議恢復狀況較佳者練習）',
    difficulties: [
      DifficultyOption(
          level: DifficultyLevel.level1,
          label: '初級',
          description: '微蹲即達標 — 膝蓋彎曲到 140 度',
          targetReps: 10),
      DifficultyOption(
          level: DifficultyLevel.level2,
          label: '中級',
          description: '半蹲 — 大腿接近平行地面',
          targetReps: 8),
      DifficultyOption(
          level: DifficultyLevel.level3,
          label: '高級',
          description: '半蹲撐住 3 秒',
          targetReps: 6),
    ],
  ),
  TrainingAction(
    type: ActionType.lateralStep,
    name: '側跨步訓練',
    emoji: '🚶',
    description: '訓練下肢平衡與單側肌力,防止跌倒（建議恢復狀況較佳者練習）',
    difficulties: [
      DifficultyOption(
          level: DifficultyLevel.level1,
          label: '初級',
          description: '微跨即達標 — 膝蓋彎曲到 140 度',
          targetReps: 10),
      DifficultyOption(
          level: DifficultyLevel.level2,
          label: '中級',
          description: '半蹲側弓步',
          targetReps: 8),
      DifficultyOption(
          level: DifficultyLevel.level3,
          label: '高級',
          description: '深側弓步撐住 2 秒',
          targetReps: 6),
    ],
  ),
];

class TrainingRecord {
  final String timestamp;
  final String actionName;
  final int difficulty;
  final int durationSeconds;
  final List<String> mistakeLogs;
  final String? videoPath; // 訓練錄影檔案路徑,null 代表沒錄或使用者選擇不保留
  final int targetReps; // ✅ 新增

  TrainingRecord({
    required this.timestamp,
    required this.actionName,
    required this.difficulty,
    required this.durationSeconds,
    required this.mistakeLogs,
    this.videoPath,
    this.targetReps = 10, // 沒帶值時的預設，避免其他呼叫處漏改就炸掉
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'actionName': actionName,
        'difficulty': difficulty,
        'durationSeconds': durationSeconds,
        'mistakeLogs': mistakeLogs,
        'videoPath': videoPath,
        'targetReps': targetReps, // ✅
      };

  factory TrainingRecord.fromJson(Map<String, dynamic> json) => TrainingRecord(
        timestamp: json['timestamp'] ?? '',
        actionName: json['actionName'] ?? '',
        difficulty: json['difficulty'] ?? 1,
        durationSeconds: json['durationSeconds'] ?? 0,
        mistakeLogs: List<String>.from(json['mistakeLogs'] ?? []),
        videoPath: json['videoPath'] as String?,
        targetReps: json['targetReps'] ?? 10, // ✅ 舊資料 fallback
      );

  /// 複製一份紀錄,只替換 videoPath(用於「先存紀錄、後補影片路徑」的情境)
  TrainingRecord copyWithVideoPath(String? path) => TrainingRecord(
        timestamp: timestamp,
        actionName: actionName,
        difficulty: difficulty,
        durationSeconds: durationSeconds,
        mistakeLogs: mistakeLogs,
        videoPath: path,
        targetReps: targetReps, // ✅
      );
}