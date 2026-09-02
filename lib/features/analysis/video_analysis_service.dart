// lib/features/analysis/video_analysis_service.dart
//
// ══════════════════════════════════════════════════════════════════
//  影片分析服務(共用)
//
//  用途:對任意 mp4 影片跑「骨架偵測 + 多維度特徵萃取」
//
//  誰在用:
//    - standard_analysis_screen.dart(治療師建立模板時)
//    - history_screen.dart(病人歷史錄影分析時)
//    - 未來的 body_training_screen(訓練完自動分析)
// ══════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img_lib;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../services/body_pose_engine.dart';
import 'motion_feature_extractor.dart';

class VideoAnalysisService {
  /// 對影片跑逐幀骨架偵測 + 多維度分析
  ///
  /// 回傳完整分析結果(如果偵測不到骨架則回 null)
  ///
  /// [videoPath] 影片檔案路徑
  /// [onProgress] 進度 callback(0.0 ~ 1.0)
  /// [fps] 每秒抽幀數,預設 2(復健動作變化慢)
  /// [maxAnalyzeSec] 最多分析前 N 秒,預設 60(避免太久)
  static Future<MotionAnalysisResult?> analyzeVideo({
    required String videoPath,
    void Function(double progress)? onProgress,
    bool Function()? shouldCancel,   // ← 新加:取消檢查
    int fps = 2,
    int maxAnalyzeSec = 60,
  }) async {
    final engine = BodyPoseEngine();
    debugPrint('🎬 初始化引擎中...');
    await engine.init().timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw Exception('引擎初始化超時(30秒)'),
    );
    debugPrint('🎬 引擎初始化完成');

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

      debugPrint('📹 影片長度: ${videoDurationSec.toStringAsFixed(1)} 秒, '
          '將分析前 ${actualSec.toStringAsFixed(1)} 秒 = $totalFrames 幀');

      final List<List<Offset>> framePoses = [];
      final List<List<double>> frameScores = [];

      // ── 逐幀分析 ──
      int successFrames = 0;
      int failedFrames = 0;

      for (int i = 0; i < totalFrames; i++) {
        // 檢查是否被取消
        if (shouldCancel?.call() == true) {
          debugPrint('🛑 使用者取消分析');
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
          debugPrint('⚠️ 第 $i 幀截圖失敗/超時: $e');
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

        // (b) JPEG 解碼
        final img_lib.Image? decoded = img_lib.decodeJpg(jpegBytes);
        if (decoded == null) {
          onProgress?.call((i + 1) / totalFrames);
          continue;
        }

        // (c) RGB 轉換
        final Uint8List rgbBytes = _imageToRgbBytes(decoded);

        // (d) ONNX 推論(加 5 秒 timeout)
        try {
          await engine.processExternalFrame(
            rgbBytes,
            decoded.width,
            decoded.height,
            isMirror: false,
          ).timeout(const Duration(seconds: 5));
        } catch (e) {
          debugPrint('⚠️ 第 $i 幀推論失敗/超時: $e');
          onProgress?.call((i + 1) / totalFrames);
          continue;
        }

        // (e) 收集結果
        final pose = engine.poseNotifier.value;
        if (pose.keypoints.isNotEmpty) {
          framePoses.add(List<Offset>.from(pose.keypoints));
          frameScores.add(List<double>.from(pose.scores));
          successFrames++;
        }

        onProgress?.call((i + 1) / totalFrames);
        
        // 每 5 幀 log 一次進度
        if ((i + 1) % 5 == 0) {
          debugPrint('🎬 已處理 ${i + 1}/$totalFrames 幀,成功 $successFrames 幀');
        }
      }
      debugPrint('🎬 分析完成:總 $totalFrames 幀,成功 $successFrames 幀,失敗 $failedFrames 幀');

      // ── 幀數不足 ──
      if (framePoses.length < 3) return null;

      // ── 委派給共用特徵萃取器 ──
      return MotionFeatureExtractor.extractFeatures(
        framePoses: framePoses,
        frameScores: frameScores,
      );
    } finally {
      await engine.dispose();
    }
  }

  /// 讀取所有已存的治療師模板 JSON
  static Future<List<Map<String, dynamic>>> loadAllTemplates() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final templatesDir = Directory('${dir.path}/templates');
      if (!await templatesDir.exists()) return [];

      final files = templatesDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList();

      // 新到舊
      files.sort(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified));

      final List<Map<String, dynamic>> results = [];
      for (final f in files) {
        try {
          final content = await f.readAsString();
          final data = jsonDecode(content) as Map<String, dynamic>;
          data['_filePath'] = f.path;
          results.add(data);
        } catch (e) {
          debugPrint('讀取模板失敗:${f.path} - $e');
        }
      }
      return results;
    } catch (e) {
      debugPrint('列出模板失敗:$e');
      return [];
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  Private
  // ─────────────────────────────────────────────────────────────

  static Uint8List _imageToRgbBytes(img_lib.Image img) {
    final int w = img.width;
    final int h = img.height;
    final Uint8List rgb = Uint8List(w * h * 3);
    int idx = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final pixel = img.getPixel(x, y);
        rgb[idx++] = pixel.r.toInt();
        rgb[idx++] = pixel.g.toInt();
        rgb[idx++] = pixel.b.toInt();
      }
    }
    return rgb;
  }
}