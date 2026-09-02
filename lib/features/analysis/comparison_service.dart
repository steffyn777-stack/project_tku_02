// lib/features/analysis/comparison_service.dart
//
// ══════════════════════════════════════════════════════════════════
//  動作品質比對服務
//
//  用途:比對「病人動作特徵」vs「治療師模板特徵」
//  輸出:綜合相似度分數 + 各項差異 + 文字建議
//
//  用在:
//    - 病人訓練完後,自動跑一次比對,顯示品質報告
//    - 治療師端事後檢視歷史紀錄,也可重新跑比對
// ══════════════════════════════════════════════════════════════════

import 'dart:math' as math;
import 'motion_feature_extractor.dart';

/// 比對結果
class ComparisonResult {
  /// 綜合相似度分數(0~100)
  final double overallScore;

  /// 各項分數(0~100)
  final double repsScore;
  final double symmetryScore;
  final double stabilityScore;

  /// 各項差異值(病人 - 模板)
  final int repsDiff;              // 動作次數差(正 = 病人多做、負 = 少做)
  final double symmetryDiff;       // 對稱性差(百分點)
  final double stabilityDiff;      // 穩定性差(百分點)

  /// 病人跟模板的主要活動關節重合度(0~100)
  final double jointOverlapScore;

  /// 文字建議清單
  final List<String> suggestions;

  const ComparisonResult({
    required this.overallScore,
    required this.repsScore,
    required this.symmetryScore,
    required this.stabilityScore,
    required this.repsDiff,
    required this.symmetryDiff,
    required this.stabilityDiff,
    required this.jointOverlapScore,
    required this.suggestions,
  });

  /// 相似度等級(綠/橙/紅)
  String get grade {
    if (overallScore >= 80) return '優秀';
    if (overallScore >= 60) return '良好';
    if (overallScore >= 40) return '待加強';
    return '需要治療師檢視';
  }
}

class ComparisonService {
  /// 比對「病人」vs「模板」
  ///
  /// [patientResult] 病人的分析結果
  /// [templateJson]  治療師模板的 JSON(已解碼成 Map)
  static ComparisonResult compare({
    required MotionAnalysisResult patientResult,
    required Map<String, dynamic> templateJson,
  }) {
    // ── 1. 從模板 JSON 讀出關鍵指標 ──
    final int templateReps = (templateJson['estimatedReps'] ?? 0) as int;
    final double templateSym =
        ((templateJson['symmetryScore'] ?? 0.0) as num).toDouble();
    final double templateSta =
        ((templateJson['stabilityScore'] ?? 0.0) as num).toDouble();

    // 主要關節(病人 vs 模板重合度用)
    final List<dynamic> templateMainJointsRaw =
        (templateJson['mainJoints'] ?? []) as List;
    final Set<int> templateMainJoints = templateMainJointsRaw
        .map((e) => (e['index'] as num).toInt())
        .toSet();

    // ── 2. 算各項分數 ──
    final repsScore = _scoreReps(patientResult.estimatedReps, templateReps);
    final symmetryScore =
        _scorePercentage(patientResult.symmetryScore, templateSym);
    final stabilityScore =
        _scorePercentage(patientResult.stabilityScore, templateSta);

    // 主要關節重合度
    final jointOverlap = _scoreJointOverlap(
      patientResult.mainJointIndices.toSet(),
      templateMainJoints,
    );

    // ── 3. 綜合分數(加權平均) ──
    // 權重設計:對稱、穩定最重要(治療師關注品質)
    // 次數次之,主要關節重合度輔助
    final overall = (symmetryScore * 0.30) +
        (stabilityScore * 0.30) +
        (repsScore * 0.20) +
        (jointOverlap * 0.20);

    // ── 4. 產生建議 ──
    final suggestions = _generateSuggestions(
      repsDiff: patientResult.estimatedReps - templateReps,
      symDiff: (patientResult.symmetryScore - templateSym) * 100,
      staDiff: (patientResult.stabilityScore - templateSta) * 100,
      jointOverlap: jointOverlap,
      symmetryScore: symmetryScore,
      stabilityScore: stabilityScore,
    );

    return ComparisonResult(
      overallScore: overall.clamp(0, 100),
      repsScore: repsScore,
      symmetryScore: symmetryScore,
      stabilityScore: stabilityScore,
      repsDiff: patientResult.estimatedReps - templateReps,
      symmetryDiff: (patientResult.symmetryScore - templateSym) * 100,
      stabilityDiff: (patientResult.stabilityScore - templateSta) * 100,
      jointOverlapScore: jointOverlap,
      suggestions: suggestions,
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  Private:各項評分邏輯
  // ─────────────────────────────────────────────────────────────

  /// 動作次數評分
  /// 差 0 次 = 100 分
  /// 差 1-2 次 = 80 分
  /// 差 3 次 = 60 分
  /// 差 5+ 次 = 30 分
  static double _scoreReps(int patient, int template) {
    if (template <= 0) return 50;   // 模板沒有次數資料,給中間分
    final diff = (patient - template).abs();
    if (diff == 0) return 100;
    if (diff <= 2) return 80;
    if (diff <= 3) return 60;
    if (diff <= 5) return 40;
    return 20;
  }

  /// 百分比類指標的評分(對稱、穩定)
  /// 病人 = 模板 → 100 分
  /// 病人比模板差越多 → 分數越低
  static double _scorePercentage(double patient, double template) {
    if (template <= 0) return 50;
    // 病人如果比模板還好(例如穩定性更高)→ 直接 100 分
    if (patient >= template) return 100;
    // 病人比模板差 → 差多少扣多少
    final ratio = patient / template;   // 0~1
    return (ratio * 100).clamp(0, 100);
  }

  /// 主要關節重合度
  /// 病人跟模板的前 5 大活動關節重合越多 → 分數越高
  static double _scoreJointOverlap(Set<int> patient, Set<int> template) {
    if (template.isEmpty || patient.isEmpty) return 50;
    final overlap = patient.intersection(template).length;
    final maxPossible = math.min(patient.length, template.length);
    if (maxPossible == 0) return 50;
    return (overlap / maxPossible * 100).clamp(0, 100);
  }

  // ─────────────────────────────────────────────────────────────
  //  文字建議(根據差異自動生成)
  // ─────────────────────────────────────────────────────────────

  static List<String> _generateSuggestions({
    required int repsDiff,
    required double symDiff,
    required double staDiff,
    required double jointOverlap,
    required double symmetryScore,
    required double stabilityScore,
  }) {
    final List<String> tips = [];

    // 次數
    if (repsDiff < -2) {
      tips.add('動作次數少於治療師標準 ${repsDiff.abs()} 次,可嘗試多做幾組。');
    } else if (repsDiff > 3) {
      tips.add('動作次數比治療師標準多 $repsDiff 次,注意不要過度勉強。');
    }

    // 對稱性
    if (symDiff < -15) {
      tips.add('左右對稱性偏低(差 ${symDiff.abs().toStringAsFixed(0)}%),'
          '可能有代償動作,建議治療師檢視。');
    } else if (symmetryScore < 60) {
      tips.add('左右對稱性未達治療師標準,建議加強較弱側訓練。');
    }

    // 穩定性
    if (staDiff < -20) {
      tips.add('軀幹穩定性偏低(差 ${staDiff.abs().toStringAsFixed(0)}%),'
          '可能有平衡問題,建議治療師檢視。');
    } else if (stabilityScore < 60) {
      tips.add('軀幹在動作過程中晃動較大,注意保持核心穩定。');
    }

    // 主要關節重合
    if (jointOverlap < 60) {
      tips.add('主要活動關節與治療師示範不完全相符,'
          '可能動作模式有差異,建議治療師檢視動作正確性。');
    }

    // 都很好
    if (tips.isEmpty) {
      tips.add('動作品質與治療師標準相近,繼續保持!');
    }

    return tips;
  }
}