// lib/features/analysis/hand_analysis_service.dart
//
// ══════════════════════════════════════════════════════════════════
//  手部影片分析服務
//
//  用途:對手部影片跑逐幀 MediaPipe 手部偵測 + 手部專屬特徵萃取
//
//  技術架構:
//    - 使用同學做的 mediapipeService.detectHandInImage(IMAGE 模式)
//    - 完全獨立於相機串流,不影響手部訓練
//    - 逐幀截圖 → 送 MediaPipe → 收 21 點手部骨架
//    - 委派給 HandFeatureExtractor 做特徵萃取
// ══════════════════════════════════════════════════════════════════

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../services/mediapipe_service.dart';
import 'hand_feature_extractor.dart';

class HandAnalysisService {
  /// 對手部影片跑逐幀 MediaPipe 偵測 + 特徵萃取
  ///
  /// [videoPath] 影片檔案路徑
  /// [onProgress] 進度 callback(0.0 ~ 1.0)
  /// [shouldCancel] 取消檢查
  /// [fps] 每秒抽幀數,預設 3(手部動作稍快)
  /// [maxAnalyzeSec] 最多分析前 N 秒,預設 60
  static Future<HandAnalysisResult?> analyzeVideo({
    required String videoPath,
    void Function(double progress)? onProgress,
    bool Function()? shouldCancel,
    int fps = 3,
    int maxAnalyzeSec = 60,
  }) async {
    // 使用同學的 MediaPipeService(獨立 IMAGE 模式)
    final mediapipeService = MediaPipeService();

    try {
      // ── 讀影片實際長度 ──
      final videoCtrl = VideoPlayerController.file(File(videoPath));
      await videoCtrl.initialize();
      final double videoDurationSec =
          videoCtrl.value.duration.inMilliseconds / 1000.0;
      await videoCtrl.dispose();

      // ── 決定要抽多少幀 ──
      final double actualSec =
          math.min(videoDurationSec, maxAnalyzeSec.toDouble());
      final int totalFrames = (fps * actualSec).ceil();

      debugPrint('🖐 手部影片: ${videoDurationSec.toStringAsFixed(1)} 秒, '
          '將分析前 ${actualSec.toStringAsFixed(1)} 秒 = $totalFrames 幀 (${fps}fps)');

      final List<List<Offset>> frameHandLandmarks = [];
      int successFrames = 0;
      int failedFrames = 0;

      // ── 逐幀分析 ──
      for (int i = 0; i < totalFrames; i++) {
        // 檢查取消
        if (shouldCancel?.call() == true) {
          debugPrint('🛑 使用者取消手部分析');
          break;
        }

        final int timeMs = i * (1000 ~/ fps);

        // (a) 截圖(加 10 秒 timeout)
        Uint8List? jpegBytes;
        try {
          jpegBytes = await VideoThumbnail.thumbnailData(
            video: videoPath,
            timeMs: timeMs,
            imageFormat: ImageFormat.JPEG,
            quality: 75,
          ).timeout(const Duration(seconds: 10));
        } catch (e) {
          debugPrint('⚠️ 第 $i 幀截圖失敗: $e');
          failedFrames++;
          onProgress?.call((i + 1) / totalFrames);
          if (failedFrames > 5) {
            debugPrint('❌ 連續失敗超過 5 次,終止分析');
            break;
          }
          continue;
        }

        if (jpegBytes == null) {
          failedFrames++;
          onProgress?.call((i + 1) / totalFrames);
          continue;
        }

        // (b) 送 MediaPipe(用同學的 IMAGE 模式)
        try {
          final result = await mediapipeService
              .detectHandInImage(jpegBytes, isMirror: false)
              .timeout(const Duration(seconds: 5));

          if (result.handDetected && result.landmarks.isNotEmpty) {
            // 轉成 Offset 清單(x, y)
            final offsets = result.landmarks
                .map((lm) => Offset(lm.x, lm.y))
                .toList();
            frameHandLandmarks.add(offsets);
            successFrames++;
          }
        } catch (e) {
          debugPrint('⚠️ 第 $i 幀 MediaPipe 失敗: $e');
        }

        onProgress?.call((i + 1) / totalFrames);

        // 每 5 幀 log 進度
        if ((i + 1) % 5 == 0) {
          debugPrint('🖐 已處理 ${i + 1}/$totalFrames 幀,成功 $successFrames 幀');
        }
      }

      debugPrint('🖐 手部分析完成:總 $totalFrames 幀,'
          '成功 $successFrames 幀,失敗 $failedFrames 幀');

      // ── 幀數不足 ──
      if (frameHandLandmarks.length < 3) {
        debugPrint('❌ 有效幀數不足 3,無法分析');
        return null;
      }

      // ── 委派給手部特徵萃取器 ──
      return HandFeatureExtractor.extractFeatures(
        frameHandLandmarks: frameHandLandmarks,
        fps: fps,
      );
    } finally {
      // 釋放 MediaPipe 資源
      mediapipeService.dispose();
    }
  }
}