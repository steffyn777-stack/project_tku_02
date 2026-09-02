// lib/actions/body_rehab_action.dart
//
// 全身復健動作的「合約」。
// 所有全身復健動作都 implements 這個,共用畫面殼才認得它們。

import '../models/body_frame.dart';

// 動作每幀判定後,回報給畫面的結果
class RehabFeedback {
  final String? prompt;   // 要顯示的提示文字 (null = 無變化)
  final bool scored;      // 這幀是否完成一次計數
  final bool leveledUp;   // 這幀是否升級難度

  const RehabFeedback({
    this.prompt,
    this.scored = false,
    this.leveledUp = false,
  });

  static const none = RehabFeedback();
}

// 全身復健動作合約
abstract class BodyRehabAction {
  // 畫面標題
  String get title;

  // 開始時的提示語
  String get initialHint;

  // 目前難度顯示文字 (例:初級/中級/高級)
  String get difficultyLabel;

  // 畫面每幀餵骨架進來,動作回報判定結果
  RehabFeedback update(BodyFrame frame);
}

abstract class LevelUpControllable {
  bool get isPendingLevelUp;
  void confirmLevelUp({int? customTargetReps});
  void declineLevelUp();
}

// 復健難度三階(全身共用)
enum RehabDifficulty { easy, medium, hard }