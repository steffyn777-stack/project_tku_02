// lib/features/analysis/hand_feature_extractor.dart
//
// ══════════════════════════════════════════════════════════════════
//  手部動作特徵萃取器
//
//  用途:從逐幀手部 21 點骨架,萃取手部復健相關指標
//
//  分析指標:
//    ✅ 動作次數(通用峰值偵測)
//    ✅ 拇指-食指開合距離(側捏、抓握類動作用)
//    ✅ 手腕旋轉角度(翻掌類動作用)
//    ✅ 動作規律性(每次動作間隔穩定度)
//    ✅ 主要活動手指(哪根手指動最多)
//
//  MediaPipe 手部 21 點索引:
//    0     WRIST(手腕)
//    1-4   THUMB(拇指:CMC, MCP, IP, TIP)
//    5-8   INDEX(食指:MCP, PIP, DIP, TIP)
//    9-12  MIDDLE(中指:MCP, PIP, DIP, TIP)
//    13-16 RING(無名指:MCP, PIP, DIP, TIP)
//    17-20 PINKY(小指:MCP, PIP, DIP, TIP)
// ══════════════════════════════════════════════════════════════════

import 'dart:math' as math;
import 'dart:ui';

/// 手部分析結果
class HandAnalysisResult {
  /// 主要活動手指索引(前 3 名)
  final List<int> mainFingerIndices;

  /// 每個手指的總位移量
  final Map<int, double> fingerTotalMovement;

  /// 動作次數(峰值數)
  final int estimatedReps;

  /// 拇指-食指開合距離:最小值 / 最大值 / 平均
  final double minPinchDistance;
  final double maxPinchDistance;
  final double avgPinchDistance;

  /// 手腕旋轉角度範圍(度)
  final double wristRotationRange;
  final double avgWristRotation;

  /// 動作規律性(0~1,1=完全規律)
  final double regularityScore;

  /// 動作強度曲線(隨時間變化)
  final List<double> actionIntensity;

  /// 總分析幀數
  final int totalFrames;

  const HandAnalysisResult({
    required this.mainFingerIndices,
    required this.fingerTotalMovement,
    required this.estimatedReps,
    required this.minPinchDistance,
    required this.maxPinchDistance,
    required this.avgPinchDistance,
    required this.wristRotationRange,
    required this.avgWristRotation,
    required this.regularityScore,
    required this.actionIntensity,
    required this.totalFrames,
  });

  factory HandAnalysisResult.empty() => const HandAnalysisResult(
        mainFingerIndices: [],
        fingerTotalMovement: {},
        estimatedReps: 0,
        minPinchDistance: 0,
        maxPinchDistance: 0,
        avgPinchDistance: 0,
        wristRotationRange: 0,
        avgWristRotation: 0,
        regularityScore: 0,
        actionIntensity: [],
        totalFrames: 0,
      );
}

/// 手部特徵萃取器
class HandFeatureExtractor {
  // ─── 關鍵點索引常數 ───
  static const int wrist = 0;
  static const int thumbTip = 4;
  static const int indexTip = 8;
  static const int middleMcp = 9;   // 中指指根(手腕方向參考)

  /// 主要入口
  static HandAnalysisResult extractFeatures({
    required List<List<Offset>> frameHandLandmarks,
    required int fps,
  }) {
    final int numFrames = frameHandLandmarks.length;
    if (numFrames < 3) return HandAnalysisResult.empty();

    // ── 1. 算每個手指(5 指 + 手腕)的總位移量 ──
    // 用每指的指尖代表:0(手腕)、4(拇指尖)、8(食指尖)、12(中指尖)、16(無名指尖)、20(小指尖)
    final fingerTipIndices = [0, 4, 8, 12, 16, 20];
    final Map<int, double> totalMovement = {};

    for (final j in fingerTipIndices) {
      double sum = 0;
      int validPairs = 0;
      for (int f = 1; f < numFrames; f++) {
        if (j >= frameHandLandmarks[f].length ||
            j >= frameHandLandmarks[f - 1].length) continue;
        final prev = frameHandLandmarks[f - 1][j];
        final curr = frameHandLandmarks[f][j];
        final dx = curr.dx - prev.dx;
        final dy = curr.dy - prev.dy;
        sum += math.sqrt(dx * dx + dy * dy);
        validPairs++;
      }
      if (validPairs > 0) totalMovement[j] = sum;
    }

    // ── 2. 主要活動手指(前 3 名) ──
    final sorted = totalMovement.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final mainFingers = sorted.take(3).map((e) => e.key).toList();

    // ── 3. 動作強度曲線(主要手指每幀位移總和) ──
    final List<double> intensity = [];
    for (int f = 1; f < numFrames; f++) {
      double sum = 0;
      for (final j in mainFingers) {
        if (j >= frameHandLandmarks[f].length ||
            j >= frameHandLandmarks[f - 1].length) continue;
        final prev = frameHandLandmarks[f - 1][j];
        final curr = frameHandLandmarks[f][j];
        final dx = curr.dx - prev.dx;
        final dy = curr.dy - prev.dy;
        sum += math.sqrt(dx * dx + dy * dy);
      }
      intensity.add(sum);
    }

    // ── 4. 動作次數(峰值數) ──
    final reps = _countPeaks(intensity);

    // ── 5. 拇指-食指開合距離 ──
    final pinchDistances = <double>[];
    for (final frame in frameHandLandmarks) {
      if (frame.length <= math.max(thumbTip, indexTip)) continue;
      final t = frame[thumbTip];
      final i = frame[indexTip];
      final dx = t.dx - i.dx;
      final dy = t.dy - i.dy;
      pinchDistances.add(math.sqrt(dx * dx + dy * dy));
    }

    double minPinch = 0, maxPinch = 0, avgPinch = 0;
    if (pinchDistances.isNotEmpty) {
      minPinch = pinchDistances.reduce(math.min);
      maxPinch = pinchDistances.reduce(math.max);
      avgPinch = pinchDistances.reduce((a, b) => a + b) / pinchDistances.length;
    }

    // ── 6. 手腕旋轉角度(手腕 → 中指指根 的向量角度) ──
    final wristAngles = <double>[];
    for (final frame in frameHandLandmarks) {
      if (frame.length <= math.max(wrist, middleMcp)) continue;
      final w = frame[wrist];
      final m = frame[middleMcp];
      final dx = m.dx - w.dx;
      final dy = m.dy - w.dy;
      // 角度 0~360 度
      final angle = math.atan2(dy, dx) * 180 / math.pi;
      wristAngles.add(angle);
    }

    double wristRange = 0, avgWrist = 0;
    if (wristAngles.isNotEmpty) {
      wristRange = wristAngles.reduce(math.max) - wristAngles.reduce(math.min);
      avgWrist = wristAngles.reduce((a, b) => a + b) / wristAngles.length;
    }

    // ── 7. 動作規律性(峰值間隔標準差) ──
    final regularity = _computeRegularity(intensity, fps);

    return HandAnalysisResult(
      mainFingerIndices: mainFingers,
      fingerTotalMovement: totalMovement,
      estimatedReps: reps,
      minPinchDistance: minPinch,
      maxPinchDistance: maxPinch,
      avgPinchDistance: avgPinch,
      wristRotationRange: wristRange,
      avgWristRotation: avgWrist,
      regularityScore: regularity,
      actionIntensity: intensity,
      totalFrames: numFrames,
    );
  }

  // ═══════════════════════════════════════════════════════════════

  /// 峰值計數(跟全身用一樣的演算法)
  static int _countPeaks(List<double> intensity) {
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

  /// 動作規律性:找峰值 → 算間隔標準差 → 轉成 0~1 分數
  static double _computeRegularity(List<double> intensity, int fps) {
    if (intensity.length < 3) return 0;

    final mean = intensity.reduce((a, b) => a + b) / intensity.length;
    final variance = intensity
            .map((v) => (v - mean) * (v - mean))
            .reduce((a, b) => a + b) /
        intensity.length;
    final std = math.sqrt(variance);
    final threshold = mean + std * 0.3;

    // 找出每個峰值的位置(第幾幀)
    final peakPositions = <int>[];
    bool inPeak = false;
    for (int i = 0; i < intensity.length; i++) {
      if (intensity[i] > threshold && !inPeak) {
        peakPositions.add(i);
        inPeak = true;
      } else if (intensity[i] <= threshold * 0.7 && inPeak) {
        inPeak = false;
      }
    }

    if (peakPositions.length < 2) return 0;

    // 算峰值間隔(單位:幀,轉成秒)
    final intervals = <double>[];
    for (int i = 1; i < peakPositions.length; i++) {
      final gapFrames = peakPositions[i] - peakPositions[i - 1];
      intervals.add(gapFrames / fps);
    }

    if (intervals.isEmpty) return 0;

    final avgInterval = intervals.reduce((a, b) => a + b) / intervals.length;
    if (avgInterval < 0.01) return 0;

    final intervalVar = intervals
            .map((v) => (v - avgInterval) * (v - avgInterval))
            .reduce((a, b) => a + b) /
        intervals.length;
    final intervalStd = math.sqrt(intervalVar);

    // 標準差越小 = 越規律
    // 用「變異係數」正規化:std/avg → 0(規律)~ 1+(不規律)
    final cv = intervalStd / avgInterval;
    return (1 - cv).clamp(0.0, 1.0);
  }

  /// 手指名稱(給 UI 顯示)
  static String fingerName(int index) {
    switch (index) {
      case 0:
        return '手腕';
      case 4:
        return '拇指';
      case 8:
        return '食指';
      case 12:
        return '中指';
      case 16:
        return '無名指';
      case 20:
        return '小指';
      default:
        return '關節$index';
    }
  }
}