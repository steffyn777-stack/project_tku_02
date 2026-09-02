import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart'; // 用 kDebugMode
import 'package:flutter/services.dart';

class Landmark {
  final double x;
  final double y;
  final double z;
  const Landmark(this.x, this.y, this.z);
}

class DetectionResult {
  final List<Landmark> landmarks;
  final bool handDetected;
  final String? imageBase64;
  DetectionResult({
    required this.landmarks,
    required this.handDetected,
    this.imageBase64,
  });
}

class TrainingUpdate {
  final String feedback;
  final String instruction;
  final int repCount;
  final double accuracy;
  final double progress;
  final int speedState;
  final bool isComplete;
  final List<String> mistakeLogs;
  final int durationSeconds;

  TrainingUpdate({
    this.feedback = '',
    this.instruction = '',
    this.repCount = 0,
    this.accuracy = 0,
    this.progress = 0,
    this.speedState = 0,
    this.isComplete = false,
    this.mistakeLogs = const [],
    this.durationSeconds = 0,
  });

  factory TrainingUpdate.fromMap(Map<dynamic, dynamic> map) {
    return TrainingUpdate(
      feedback: map['feedback'] ?? '',
      instruction: map['instruction'] ?? '',
      repCount: map['repCount'] ?? 0,
      accuracy: (map['accuracy'] ?? 0).toDouble(),
      progress: (map['progress'] ?? 0).toDouble(),
      speedState: map['speedState'] ?? 0,
      isComplete: map['isComplete'] ?? false,
      mistakeLogs: List<String>.from(map['mistakeLogs'] ?? []),
      durationSeconds: map['durationSeconds'] ?? 0,
    );
  }
}

class MediaPipeService {
  static const MethodChannel _channel =
      MethodChannel('com.rehabassist/mediapipe');
  static const EventChannel _landmarkChannel =
      EventChannel('com.rehabassist/landmarks');
  static const EventChannel _trainingChannel =
      EventChannel('com.rehabassist/training');

  StreamSubscription? _landmarkSub;
  StreamSubscription? _trainingSub;

  final StreamController<DetectionResult> _landmarkController =
      StreamController.broadcast();
  final StreamController<TrainingUpdate> _trainingController =
      StreamController.broadcast();

  Stream<DetectionResult> get landmarkStream => _landmarkController.stream;
  Stream<TrainingUpdate> get trainingStream => _trainingController.stream;

  Future<void> startDetection({
    required String actionType,
    required int difficulty,
    bool useFrontCamera = false,
  }) async {
    await _channel.invokeMethod('startDetection', {
      'actionType': actionType,
      'difficulty': difficulty,
      'useFrontCamera': useFrontCamera,
    });
    _subscribeLandmarks();
    _subscribeTraining();
  }

  Future<void> stopDetection() async {
    await _channel.invokeMethod('stopDetection');
    _landmarkSub?.cancel();
    _trainingSub?.cancel();
  }

  Future<void> flipCamera() async {
    await _channel.invokeMethod('flipCamera');
  }

  /// 🆕 樹莓派用:傳入單張 JPEG bytes,回傳這一幀的手部 landmarks。
  /// 走 IMAGE 模式,跟即時串流(startDetection)完全獨立,可以同時或分開使用。
  Future<DetectionResult> detectHandInImage(
    Uint8List jpegBytes, {
    bool isMirror = false,
  }) async {
    try {
      final data = await _channel.invokeMethod('detectHandInImage', {
        'jpegBytes': jpegBytes,
        'isMirror': isMirror,
      });
      if (data == null) {
        return DetectionResult(landmarks: [], handDetected: false);
      }
      final map = data as Map;
      final rawLandmarks = map['landmarks'] as List? ?? [];
      final landmarks = rawLandmarks.map((lm) {
        final m = lm as Map;
        return Landmark(
          (m['x'] ?? 0).toDouble(),
          (m['y'] ?? 0).toDouble(),
          (m['z'] ?? 0).toDouble(),
        );
      }).toList();
      return DetectionResult(
        landmarks: landmarks,
        handDetected: map['handDetected'] ?? false,
      );
    } catch (e) {
      debugPrint('=== detectHandInImage ERROR: $e');
      return DetectionResult(landmarks: [], handDetected: false);
    }
  }

  void _subscribeLandmarks() {
    _landmarkSub = _landmarkChannel.receiveBroadcastStream().listen(
      (data) {
        if (kDebugMode) {
          final map = data as Map?;
          final count = (map?['landmarks'] as List?)?.length ?? 0;
          if (count == 0) debugPrint('=== No landmarks detected');
        }

        if (data == null) return;
        final map = data as Map;
        final rawLandmarks = map['landmarks'] as List? ?? [];
        final landmarks = rawLandmarks.map((lm) {
          final m = lm as Map;
          return Landmark(
            (m['x'] ?? 0).toDouble(),
            (m['y'] ?? 0).toDouble(),
            (m['z'] ?? 0).toDouble(),
          );
        }).toList();
        _landmarkController.add(DetectionResult(
          landmarks: landmarks,
          handDetected: map['handDetected'] ?? false,
          imageBase64: map['imageBase64'], // 🚀 新增: 讀取影像資料
        ));
      },
      onError: (e) => debugPrint('=== LANDMARK ERROR: $e'),
    );
  }

  void _subscribeTraining() {
    _trainingSub = _trainingChannel.receiveBroadcastStream().listen(
      (data) {
        if (data == null) return;
        final update = TrainingUpdate.fromMap(data as Map);
        if (kDebugMode && update.isComplete) {
          debugPrint('=== Training complete: reps=${update.repCount}');
        }
        _trainingController.add(update);
      },
      onError: (e) => debugPrint('=== TRAINING ERROR: $e'),
    );
  }

  void dispose() {
    _landmarkSub?.cancel();
    _trainingSub?.cancel();
    _landmarkController.close();
    _trainingController.close();
  }
}
