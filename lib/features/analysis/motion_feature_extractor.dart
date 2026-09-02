// lib/features/analysis/motion_feature_extractor.dart
//
// ══════════════════════════════════════════════════════════════════
//  動作特徵萃取(共用邏輯)
//
//  給「治療師端(動作標準分析)」跟「病人端(訓練後分析)」共用
//  純 static 方法,無狀態,可安全在任何地方呼叫
// ══════════════════════════════════════════════════════════════════

import 'dart:math' as math;
import 'dart:ui';

/// 動作分析結果封裝(所有多維度特徵集中在此)
class MotionAnalysisResult {
  final List<int> mainJointIndices;              // 主要活動關節(前 5)
  final Map<int, double> jointTotalMovement;      // 每個關節的總位移
  final List<double> actionIntensity;             // 動作強度曲線
  final int estimatedReps;                        // 估算動作次數
  final double symmetryScore;                     // 對稱性 0~1
  final double stabilityScore;                    // 穩定性 0~1

  const MotionAnalysisResult({
    required this.mainJointIndices,
    required this.jointTotalMovement,
    required this.actionIntensity,
    required this.estimatedReps,
    required this.symmetryScore,
    required this.stabilityScore,
  });

  /// 空結果(還沒分析時用)
  factory MotionAnalysisResult.empty() => const MotionAnalysisResult(
        mainJointIndices: [],
        jointTotalMovement: {},
        actionIntensity: [],
        estimatedReps: 0,
        symmetryScore: 0,
        stabilityScore: 0,
      );
}

/// 動作特徵萃取器(共用)
class MotionFeatureExtractor {
  /// 只分析身體主要關節(排除臉部細節、手指)
  static const int bodyJointStart = 0;
  static const int bodyJointEnd = 16;

  /// 分數門檻(骨架點可信度低於此值不列入計算)
  static const double scoreThreshold = 0.3;

  /// 主要入口 —— 傳入逐幀骨架資料,得到完整分析結果
  ///
  /// [framePoses] : 每幀的 133 個關節座標
  /// [frameScores] : 每幀對應的可信度分數
  static MotionAnalysisResult extractFeatures({
    required List<List<Offset>> framePoses,
    required List<List<double>> frameScores,
  }) {
    final int numFrames = framePoses.length;
    if (numFrames < 3) return MotionAnalysisResult.empty();

    // ── 1. 每個關節總位移 ──
    final totalMovement = _computeTotalMovement(framePoses, frameScores);

    // ── 2. 主要活動關節(前 5) ──
    final sorted = totalMovement.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final mainJoints = sorted.take(5).map((e) => e.key).toList();

    // ── 3. 動作強度曲線 ──
    final intensity =
        _computeActionIntensity(framePoses, frameScores, mainJoints);

    // ── 4-6. 統計指標 ──
    final reps = countPeaks(intensity);
    final symmetry = computeSymmetry(totalMovement);
    final stability = computeStability(framePoses, frameScores);

    return MotionAnalysisResult(
      mainJointIndices: mainJoints,
      jointTotalMovement: totalMovement,
      actionIntensity: intensity,
      estimatedReps: reps,
      symmetryScore: symmetry,
      stabilityScore: stability,
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  以下為公開 helper(病人端比對時也會用到)
  // ─────────────────────────────────────────────────────────────

  /// 計算「峰值數 = 動作次數」
  static int countPeaks(List<double> intensity) {
    if (intensity.length < 3) return 0;

    final mean = intensity.reduce((a, b) => a + b) / intensity.length;
    final variance = intensity
            .map((v) => (v - mean) * (v - mean))
            .reduce((a, b) => a + b) /
        intensity.length;
    final std = math.sqrt(variance);
    final threshold = mean + std * 0.3;

    int peaks = 0;
    bool inPeak = false;
    for (final v in intensity) {
      if (v > threshold && !inPeak) {
        peaks++;
        inPeak = true;
      } else if (v <= threshold * 0.7 && inPeak) {
        inPeak = false;
      }
    }
    return peaks;
  }

  /// 計算左右對稱性(0=完全不對稱、1=完全對稱)
  static double computeSymmetry(Map<int, double> movement) {
    const pairs = [
      [5, 6],   // 肩
      [7, 8],   // 肘
      [9, 10],  // 腕
      [11, 12], // 髖
      [13, 14], // 膝
      [15, 16], // 踝
    ];
    double total = 0;
    int valid = 0;
    for (final pair in pairs) {
      final l = movement[pair[0]];
      final r = movement[pair[1]];
      if (l == null || r == null) continue;
      final maxV = math.max(l, r);
      if (maxV < 1e-6) continue;
      total += math.min(l, r) / maxV;
      valid++;
    }
    return valid == 0 ? 0 : total / valid;
  }

  /// 計算軀幹穩定性(0=不穩、1=非常穩)
  static double computeStability(
    List<List<Offset>> framePoses,
    List<List<double>> frameScores,
  ) {
    const trunkJoints = [5, 6, 11, 12];   // 肩、髖
    double totalVariance = 0;
    int count = 0;

    for (final j in trunkJoints) {
      final List<double> xs = [];
      final List<double> ys = [];
      for (int f = 0; f < framePoses.length; f++) {
        if (frameScores[f][j] < scoreThreshold) continue;
        xs.add(framePoses[f][j].dx);
        ys.add(framePoses[f][j].dy);
      }
      if (xs.length < 3) continue;

      final meanX = xs.reduce((a, b) => a + b) / xs.length;
      final meanY = ys.reduce((a, b) => a + b) / ys.length;
      final varX = xs
              .map((v) => (v - meanX) * (v - meanX))
              .reduce((a, b) => a + b) /
          xs.length;
      final varY = ys
              .map((v) => (v - meanY) * (v - meanY))
              .reduce((a, b) => a + b) /
          ys.length;
      totalVariance += (varX + varY);
      count++;
    }

    if (count == 0) return 0;
    final avgVariance = totalVariance / count;
    return (1 - avgVariance * 20).clamp(0.0, 1.0);
  }

  /// COCO 133 關鍵點名稱(給 UI 顯示)
  static String jointName(int index) {
    const names = {
      0: '鼻',
      5: '左肩', 6: '右肩',
      7: '左肘', 8: '右肘',
      9: '左腕', 10: '右腕',
      11: '左髖', 12: '右髖',
      13: '左膝', 14: '右膝',
      15: '左踝', 16: '右踝',
    };
    return names[index] ?? '關節$index';
  }

  // ─────────────────────────────────────────────────────────────
  //  Private helpers
  // ─────────────────────────────────────────────────────────────

  /// 算每個關節的「總位移量」(只算身體 17 點)
  static Map<int, double> _computeTotalMovement(
    List<List<Offset>> framePoses,
    List<List<double>> frameScores,
  ) {
    final Map<int, double> totalMovement = {};
    final int numFrames = framePoses.length;

    for (int j = bodyJointStart; j <= bodyJointEnd; j++) {
      double sum = 0;
      int validPairs = 0;
      for (int f = 1; f < numFrames; f++) {
        if (frameScores[f][j] < scoreThreshold ||
            frameScores[f - 1][j] < scoreThreshold) continue;
        final prev = framePoses[f - 1][j];
        final curr = framePoses[f][j];
        final dx = curr.dx - prev.dx;
        final dy = curr.dy - prev.dy;
        sum += math.sqrt(dx * dx + dy * dy);
        validPairs++;
      }
      if (validPairs > 0) totalMovement[j] = sum;
    }
    return totalMovement;
  }

  /// 主要關節每幀位移總和 = 動作強度曲線
  static List<double> _computeActionIntensity(
    List<List<Offset>> framePoses,
    List<List<double>> frameScores,
    List<int> mainJoints,
  ) {
    final int numFrames = framePoses.length;
    final List<double> intensity = [];
    for (int f = 1; f < numFrames; f++) {
      double sum = 0;
      for (final j in mainJoints) {
        if (frameScores[f][j] < scoreThreshold ||
            frameScores[f - 1][j] < scoreThreshold) continue;
        final prev = framePoses[f - 1][j];
        final curr = framePoses[f][j];
        final dx = curr.dx - prev.dx;
        final dy = curr.dy - prev.dy;
        sum += math.sqrt(dx * dx + dy * dy);
      }
      intensity.add(sum);
    }
    return intensity;
  }
}