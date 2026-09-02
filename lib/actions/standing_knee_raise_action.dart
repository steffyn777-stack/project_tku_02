// lib/actions/standing_knee_raise_action.dart
//
// 站姿抬腳式訓練 — 判定邏輯。
// implements BodyRehabAction, 可直接丟進 body_training_screen。
//
// ✅ 修正重點：原本只判定左腳（leftHip/leftKnee/leftAnkle），
//    如果患側是右腳會永遠判定不到目標區。
//    比照 ReachAction 的做法，加入 selectLeftLeg() / selectRightLeg()，
//    讓外部（UI 按鈕）可以選擇要訓練哪一腳。
//
// 🩺 2026-08-20 治療師回饋:
//   抬腳時腳掌應盡量放平往上抬，不要往下垂。
//   新增 leftBigToe/rightBigToe、leftHeel/rightHeel 座標時才會啟用此檢查
//   (資料源尚未接上前直接跳過，不影響原本判定)。
//
// 🩺 2026-08-21 治療師回饋:
//   聳肩容忍度、身體後仰容忍度原本中/高階相同或固定值,沒有明顯分級。
//   改成三階分級:初階最寬鬆,高階最嚴格。

import 'dart:math' as math;
import '../models/body_frame.dart';
import 'body_rehab_action.dart';

// enum RehabDifficulty { easy, medium, hard }

class StandingKneeRaiseAction implements BodyRehabAction, LevelUpControllable {
  RehabDifficulty difficulty;
  int successCount = 0;
  int targetCount;

  bool _hasTriggeredRaise = false;
  DateTime _lastVoiceTime = DateTime.now();

  // 🆕 是否正等待使用者決定要不要升級(達標後、確認前為 true)
  bool _pendingLevelUp = false;

  // ── 左右腳選擇 ────────────────────────────────────────────
  RehabJoint? _activeHip;
  RehabJoint? _activeKnee;
  RehabJoint? _activeAnkle;
  RehabJoint? _activeBigToe; // 🆕
  RehabJoint? _activeHeel;   // 🆕

  StandingKneeRaiseAction({
    this.difficulty = RehabDifficulty.easy,
    this.targetCount = 3,
  });

  // ── 供 UI 按鈕呼叫：選擇左腳或右腳 ──────────────────────────
  bool get legSelected => _activeHip != null;

  void selectLeftLeg() {
    _activeHip = RehabJoint.leftHip;
    _activeKnee = RehabJoint.leftKnee;
    _activeAnkle = RehabJoint.leftAnkle;
    _activeBigToe = RehabJoint.leftBigToe; // 🆕
    _activeHeel = RehabJoint.leftHeel;     // 🆕
  }

  void selectRightLeg() {
    _activeHip = RehabJoint.rightHip;
    _activeKnee = RehabJoint.rightKnee;
    _activeAnkle = RehabJoint.rightAnkle;
    _activeBigToe = RehabJoint.rightBigToe; // 🆕
    _activeHeel = RehabJoint.rightHeel;     // 🆕
  }

  // ── 合約要求 ──────────────────────────────────────────────
  @override
  String get title => '站姿抬腳式訓練';

  @override
  String get initialHint => legSelected
      ? '雙腳與肩同寬站立，手扶椅背或拐杖，準備進行抬腳訓練，腳掌盡量放平'
      : '請先選擇要訓練的腳（左腳／右腳）';

  @override
  String get difficultyLabel {
    switch (difficulty) {
      case RehabDifficulty.easy:
        return '初級';
      case RehabDifficulty.medium:
        return '中級';
      case RehabDifficulty.hard:
        return '高級';
    }
  }

  // 🩺 依難度分級的防代償容錯值(聳肩、後仰),初階最寬鬆,高階最嚴格
  double get _shoulderTolerance => switch (difficulty) {
        RehabDifficulty.easy => 0.10,
        RehabDifficulty.medium => 0.06,
        RehabDifficulty.hard => 0.04,
      };

  double get _spineToleranceDeg => switch (difficulty) {
        RehabDifficulty.easy => 20.0,
        RehabDifficulty.medium => 15.0,
        RehabDifficulty.hard => 10.0,
      };

  // ── 合約核心: 每幀判定 ────────────────────────────────────
  @override
  RehabFeedback update(BodyFrame frame) {
    if (_pendingLevelUp) return RehabFeedback.none;
    // 尚未選腳 → 等待 UI 按鈕，不做任何偵測
    if (!legSelected) return RehabFeedback.none;

    // 取得上半身骨架（防代償用，雙肩仍需雙側資料）
    final leftShoulder = frame.joints[RehabJoint.leftShoulder];
    final rightShoulder = frame.joints[RehabJoint.rightShoulder];

    // 取得下半身骨架（動作判定用，依選擇的腳而定）
    final hip = frame.joints[_activeHip!];
    final knee = frame.joints[_activeKnee!];
    final ankle = frame.joints[_activeAnkle!];

    if (leftShoulder == null ||
        rightShoulder == null ||
        hip == null ||
        knee == null ||
        ankle == null) {
      return RehabFeedback.none;
    }

    // 1. 防代償：防過度傾斜/聳肩 (保持兩側肩膀水平)
    final shoulderDrop = (leftShoulder.dy - rightShoulder.dy).abs();
    if (shoulderDrop > _shoulderTolerance) {
      return RehabFeedback(prompt: _speakThrottled('請保持身體直立，不要歪斜或聳肩喔'));
    }

    // 2. 防代償：防身體後仰（用選擇那側的肩膀-髖部）
    final activeShoulder =
        _activeHip == RehabJoint.leftHip ? leftShoulder : rightShoulder;
    final spineDx = activeShoulder.dx - hip.dx;
    final spineDy = activeShoulder.dy - hip.dy;
    final spineAngle = math.atan2(spineDx, spineDy) * (180 / math.pi);
    if (spineAngle < -_spineToleranceDeg) {
      return RehabFeedback(prompt: _speakThrottled('站直一點，身體不要往後仰'));
    }

    // 3. 計算關節角度
    // 髖關節角度（大腿與軀幹的夾角）：利用肩膀、髖部、膝蓋計算
    final hipAngle = _calculateAngle(activeShoulder, hip, knee);
    // 膝關節彎曲角度：利用髖部、膝蓋、腳踝計算
    final kneeAngle = _calculateAngle(hip, knee, ankle);

    // 4. 目標區與難度判定
    bool isInTargetZone = false;

    switch (difficulty) {
      case RehabDifficulty.easy:
        // 初級：大腿微抬，膝蓋高於腳踝，髖關節彎曲角度（小於 140 度即可）
        isInTargetZone = knee.dy < hip.dy && hipAngle < 140.0;
        break;
      case RehabDifficulty.medium:
        // 中級（影片標準）：大腿抬平接近 90 度（hipAngle 約 90-110 度），且膝蓋自然彎曲（kneeAngle 約 80-110 度）
        isInTargetZone = knee.dy < hip.dy &&
            hipAngle <= 110.0 &&
            kneeAngle >= 80.0 && kneeAngle <= 110.0;
        break;
      case RehabDifficulty.hard:
        // 高級：大腿抬得更高（hipAngle < 90 度），且膝蓋能精準控制在約 90 度，停留更穩定
        isInTargetZone = knee.dy < hip.dy &&
            hipAngle < 90.0 &&
            kneeAngle >= 85.0 && kneeAngle <= 100.0;
        break;
    }

    // 🩺 4.5 腳掌平舉檢查:只在已抬起(knee.dy < hip.dy，代表大腿已離地)時檢查，
    //    腳趾明顯低於腳跟太多 = 腳掌下垂。資料源沒接上就跳過。
    if (knee.dy < hip.dy) {
      final bigToe = frame.joints[_activeBigToe!];
      final heel = frame.joints[_activeHeel!];
      if (bigToe != null && heel != null) {
        const droopMargin = 0.03; // 正規化座標容許誤差
        final isDrooping = bigToe.dy > heel.dy + droopMargin;
        if (isDrooping) {
          final prompt = _speakThrottled('腳掌盡量放平，腳尖不要往下垂');
          if (prompt != null) return RehabFeedback(prompt: prompt);
        }
      }
    }

    // 5. 計分與跳關邏輯
    if (isInTargetZone) {
      if (!_hasTriggeredRaise) {
        _hasTriggeredRaise = true;
        successCount++;

        if (successCount >= targetCount) {
          //_upgradeDifficulty();
          _pendingLevelUp = true;
          return const RehabFeedback(
            prompt: '太棒了！動作非常標準，解鎖下一個難度！',
            scored: true,
            leveledUp: true,
          );
        }
        return const RehabFeedback(
          prompt: '慢抬慢放，做得很好！',
          scored: true,
        );
      }
    } else if (knee.dy > hip.dy + 0.1) {
      // 當膝蓋放低，回到接近原起始站姿時，重置觸發開關，允許下一次計分
      _hasTriggeredRaise = false;
    }

    // 6. 即時動態提示
    if (!isInTargetZone && _hasTriggeredRaise == false) {
      if (difficulty == RehabDifficulty.medium && hipAngle > 110.0) {
        return RehabFeedback(prompt: _speakThrottled('試著把膝蓋再抬高，靠近肚子一點'));
      }
      if (kneeAngle < 70.0 || kneeAngle > 120.0) {
        return RehabFeedback(prompt: _speakThrottled('保持小腿自然下垂，膝蓋彎曲約90度'));
      }
    }

    return RehabFeedback.none;
  }

  // ── 私有方法 ──────────────────────────────────────────────
  double _calculateAngle(dynamic p1, dynamic p2, dynamic p3) {
    final a = math.sqrt(math.pow(p2.dx - p3.dx, 2) + math.pow(p2.dy - p3.dy, 2));
    final b = math.sqrt(math.pow(p1.dx - p3.dx, 2) + math.pow(p1.dy - p3.dy, 2));
    final c = math.sqrt(math.pow(p1.dx - p2.dx, 2) + math.pow(p1.dy - p2.dy, 2));
    if (a * c == 0) return 0.0;
    final cosB = (math.pow(a, 2) + math.pow(c, 2) - math.pow(b, 2)) / (2 * a * c);
    return math.acos(cosB.clamp(-1.0, 1.0)) * (180 / math.pi);
  }

  String? _speakThrottled(String text) {
    final now = DateTime.now();
    if (now.difference(_lastVoiceTime).inSeconds > 3) { // 稍微加長語音間隔，避免抬腳過程中頻繁打擾
      _lastVoiceTime = now;
      return text;
    }
    return null;
  }

  void _upgradeDifficulty() {
    successCount = 0;
    _hasTriggeredRaise = false;
    if (difficulty == RehabDifficulty.easy) {
      difficulty = RehabDifficulty.medium;
    } else if (difficulty == RehabDifficulty.medium) {
      difficulty = RehabDifficulty.hard;
    }
  }

  @override
  bool get isPendingLevelUp => _pendingLevelUp; // 🆕

  @override
  void confirmLevelUp({int? customTargetReps}) { // 🆕
    _pendingLevelUp = false;
    _upgradeDifficulty();
    if (customTargetReps != null && customTargetReps > 0) {
      targetCount = customTargetReps;
    }
  }

  @override
  void declineLevelUp() { // 🆕
    _pendingLevelUp = false;
    successCount = 0;
    _hasTriggeredRaise = false;
  }
}