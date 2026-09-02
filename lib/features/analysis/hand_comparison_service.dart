// lib/features/analysis/hand_comparison_service.dart
//
// ══════════════════════════════════════════════════════════════════
//  手部動作品質比對服務
//
//  用途:比對「病人手部特徵」vs「治療師手部模板」
//  輸出:綜合相似度 + 各項差異 + 建議
//
//  評分權重:
//    動作次數  30%
//    開合幅度  30%
//    手腕旋轉  20%
//    動作規律性 20%
// ══════════════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'hand_feature_extractor.dart';

/// 手部比對結果
class HandComparisonResult {
  /// 綜合相似度分數(0~100)
  final double overallScore;

  /// 各項分數(0~100)
  final double repsScore;
  final double pinchRangeScore;
  final double wristRotationScore;
  final double regularityScore;

  /// 各項差異值(病人 - 模板)
  final int repsDiff;
  final double pinchRangeDiff;
  final double wristRotationDiff;
  final double regularityDiff;

  /// 病人跟模板的主要手指重合度(0~100)
  final double fingerOverlapScore;

  /// 文字建議
  final List<String> suggestions;

  const HandComparisonResult({
    required this.overallScore,
    required this.repsScore,
    required this.pinchRangeScore,
    required this.wristRotationScore,
    required this.regularityScore,
    required this.repsDiff,
    required this.pinchRangeDiff,
    required this.wristRotationDiff,
    required this.regularityDiff,
    required this.fingerOverlapScore,
    required this.suggestions,
  });

  String get grade {
    if (overallScore >= 80) return '優秀';
    if (overallScore >= 60) return '良好';
    if (overallScore >= 40) return '待加強';
    return '需要治療師檢視';
  }
}

class HandComparisonService {
  /// 比對「病人手部」vs「模板」
  static HandComparisonResult compare({
    required HandAnalysisResult patientResult,
    required Map<String, dynamic> templateJson,
  }) {
    // ── 從模板 JSON 讀出關鍵指標 ──
    final int templateReps = (templateJson['estimatedReps'] ?? 0) as int;
    final double templatePinchRange =
        (((templateJson['maxPinchDistance'] ?? 0.0) as num).toDouble() -
                ((templateJson['minPinchDistance'] ?? 0.0) as num).toDouble())
            .abs();
    final double templateWristRange =
        ((templateJson['wristRotationRange'] ?? 0.0) as num).toDouble();
    final double templateRegularity =
        ((templateJson['regularityScore'] ?? 0.0) as num).toDouble();

    // 主要活動手指
    final List<dynamic> templateMainFingersRaw =
        (templateJson['mainFingers'] ?? []) as List;
    final Set<int> templateMainFingers = templateMainFingersRaw
        .map((e) => (e['index'] as num).toInt())
        .toSet();

    // ── 各項分數 ──
    final patientPinchRange =
        (patientResult.maxPinchDistance - patientResult.minPinchDistance).abs();

    final repsScore = _scoreReps(patientResult.estimatedReps, templateReps);
    final pinchScore = _scoreRange(patientPinchRange, templatePinchRange);
    final wristScore =
        _scoreRange(patientResult.wristRotationRange, templateWristRange);
    final regularityScore = _scorePercentage(
        patientResult.regularityScore, templateRegularity);

    final fingerOverlap = _scoreFingerOverlap(
      patientResult.mainFingerIndices.toSet(),
      templateMainFingers,
    );

    // ── 綜合分數(加權平均) ──
    final overall = (repsScore * 0.30) +
        (pinchScore * 0.30) +
        (wristScore * 0.20) +
        (regularityScore * 0.20);

    // ── 產生建議 ──
    final suggestions = _generateSuggestions(
      repsDiff: patientResult.estimatedReps - templateReps,
      pinchDiff: patientPinchRange - templatePinchRange,
      wristDiff: patientResult.wristRotationRange - templateWristRange,
      regularityDiff:
          (patientResult.regularityScore - templateRegularity) * 100,
      fingerOverlap: fingerOverlap,
    );

    return HandComparisonResult(
      overallScore: overall.clamp(0, 100),
      repsScore: repsScore,
      pinchRangeScore: pinchScore,
      wristRotationScore: wristScore,
      regularityScore: regularityScore,
      repsDiff: patientResult.estimatedReps - templateReps,
      pinchRangeDiff: patientPinchRange - templatePinchRange,
      wristRotationDiff:
          patientResult.wristRotationRange - templateWristRange,
      regularityDiff:
          (patientResult.regularityScore - templateRegularity) * 100,
      fingerOverlapScore: fingerOverlap,
      suggestions: suggestions,
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  評分邏輯
  // ─────────────────────────────────────────────────────────────

  static double _scoreReps(int patient, int template) {
    if (template <= 0) return 50;
    final diff = (patient - template).abs();
    if (diff == 0) return 100;
    if (diff <= 2) return 80;
    if (diff <= 3) return 60;
    if (diff <= 5) return 40;
    return 20;
  }

  /// 範圍類指標(開合、旋轉)評分
  static double _scoreRange(double patient, double template) {
    if (template <= 0.001) return 50;
    if (patient >= template) return 100;
    return ((patient / template) * 100).clamp(0, 100);
  }

  /// 百分比類指標(規律性)評分
  static double _scorePercentage(double patient, double template) {
    if (template <= 0) return 50;
    if (patient >= template) return 100;
    return ((patient / template) * 100).clamp(0, 100);
  }

  /// 主要手指重合度
  static double _scoreFingerOverlap(Set<int> patient, Set<int> template) {
    if (template.isEmpty || patient.isEmpty) return 50;
    final overlap = patient.intersection(template).length;
    final maxPossible = math.min(patient.length, template.length);
    if (maxPossible == 0) return 50;
    return (overlap / maxPossible * 100).clamp(0, 100);
  }

  // ─────────────────────────────────────────────────────────────
  //  文字建議
  // ─────────────────────────────────────────────────────────────

  static List<String> _generateSuggestions({
    required int repsDiff,
    required double pinchDiff,
    required double wristDiff,
    required double regularityDiff,
    required double fingerOverlap,
  }) {
    final List<String> tips = [];

    // 次數
    if (repsDiff < -2) {
      tips.add('動作次數少於治療師標準 ${repsDiff.abs()} 次,可嘗試多做幾組。');
    } else if (repsDiff > 3) {
      tips.add('動作次數比治療師標準多 $repsDiff 次,注意不要過度勉強。');
    }

    // 開合幅度
    if (pinchDiff < -0.05) {
      tips.add('手指開合幅度較治療師小,可能靈活度不足,'
          '建議治療師評估關節活動度。');
    } else if (pinchDiff > 0.1) {
      tips.add('手指開合幅度大於治療師示範,注意動作是否穩定。');
    }

    // 手腕旋轉
    if (wristDiff < -15) {
      tips.add('手腕旋轉角度較治療師小(差 ${wristDiff.abs().toStringAsFixed(0)}°),'
          '翻掌動作可能不夠完整。');
    } else if (wristDiff > 20) {
      tips.add('手腕旋轉角度較治療師大,注意有無過度動作。');
    }

    // 規律性
    if (regularityDiff < -20) {
      tips.add('動作規律性偏低(差 ${regularityDiff.abs().toStringAsFixed(0)}%),'
          '節奏不夠穩定,建議放慢節拍。');
    }

    // 手指重合度
    if (fingerOverlap < 60) {
      tips.add('主要活動手指與治療師示範不完全相符,'
          '可能動作重點有差異,建議治療師檢視動作正確性。');
    }

    if (tips.isEmpty) {
      tips.add('手部動作品質與治療師標準相近,繼續保持!');
    }

    return tips;
  }
}