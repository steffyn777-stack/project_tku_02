// lib/actions/base_rehab_action.dart

import '../services/mediapipe_service.dart';
import 'rehab_action_callback.dart';

abstract class BaseRehabAction {
  final RehabActionCallback callback;

  BaseRehabAction(this.callback);

  /// 每幀 landmark 進來時觸發，各動作自行處理
  void processLandmarks(List<Landmark> landmarks);

  /// trainingStream 是否可接收
  /// 翻掌要等倒數完才 true；側捏直接 true
  bool get isReadyToReceiveUpdates;

  /// 初始化完成後顯示的提示
  String get initialFeedback;
  String get initialInstruction;

  /// 釋放資源（Timer 等），子類別視需要 override
  void dispose() {}
}

// 🆕 可選介面:動作若想支援「使用者自行決定要不要升級」就實作這個
  abstract class LevelUpControllable {
    bool get isPendingLevelUp;
    void confirmLevelUp({int? customTargetReps});
    void declineLevelUp();
  }