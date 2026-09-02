// lib/services/pose_to_bone_mapper.dart

import 'dart:math' as math;
import 'dart:ui';
import '../models/pose_data.dart';

class BoneAngles {
  final double shoulderL;
  final double elbowL;
  final double wristL;
  final double shoulderR;
  final double elbowR;
  final double wristR;

  const BoneAngles({
    required this.shoulderL,
    required this.elbowL,
    required this.wristL,
    required this.shoulderR,
    required this.elbowR,
    required this.wristR,
  });

  static const zero = BoneAngles(
    shoulderL: 0,
    elbowL: 0,
    wristL: 0,
    shoulderR: 0,
    elbowR: 0,
    wristR: 0,
  );

  Map<String, double> toMap() => {
        'shoulder-l': shoulderL,
        'elbow-l': elbowL,
        'wrist-l': wristL,
        'shoulder-r': shoulderR,
        'elbow-r': elbowR,
        'wrist-r': wristR,
      };
}

class PoseToBoneMapper {
  static const int _leftShoulder = 5;
  static const int _rightShoulder = 6;
  static const int _leftElbow = 7;
  static const int _rightElbow = 8;
  static const int _leftHip = 11;
  static const int _rightHip = 12;
  static const int _leftWristPrecise = 91;
  static const int _leftMiddleBase = 100;
  static const int _rightWristPrecise = 112;
  static const int _rightMiddleBase = 121;

  static const double _scoreThreshold = 0.3;
  static const double _smoothAlpha = 0.7;
  static const double _restReturnAlpha = 0.15;

  BoneAngles? _smoothed;

  // ← 加了 isFrontCamera 參數
  BoneAngles computeAngles(PoseData data, {bool isFrontCamera = true}) {
    if (data.keypoints.length < 133 || data.scores.length < 133) {
      return _returnToRest();
    }
    final raw = _computeRawAngles(data, isFrontCamera: isFrontCamera);
    _smoothed = _applySmoothing(raw);
    return _smoothed!;
  }

  BoneAngles _returnToRest() {
    if (_smoothed == null) return BoneAngles.zero;
    final prev = _smoothed!;
    double lerp(double v) => v + (0 - v) * _restReturnAlpha;
    _smoothed = BoneAngles(
      shoulderL: lerp(prev.shoulderL),
      elbowL: lerp(prev.elbowL),
      wristL: lerp(prev.wristL),
      shoulderR: lerp(prev.shoulderR),
      elbowR: lerp(prev.elbowR),
      wristR: lerp(prev.wristR),
    );
    return _smoothed!;
  }

  // ← 加了 isFrontCamera 參數，前鏡頭時左右對調
  BoneAngles _computeRawAngles(PoseData data, {bool isFrontCamera = true}) {
    final kp = data.keypoints;
    final sc = data.scores;

    // 前鏡頭：畫面左邊 = RTMPose 右邊，索引對調
    final lShoulder = isFrontCamera ? _leftShoulder : _rightShoulder;
    final rShoulder = isFrontCamera ? _rightShoulder : _leftShoulder;
    final lElbow    = isFrontCamera ? _leftElbow : _rightElbow;
    final rElbow    = isFrontCamera ? _rightElbow : _leftElbow;
    final lHip      = isFrontCamera ? _leftHip : _rightHip;
    final rHip      = isFrontCamera ? _rightHip : _leftHip;
    final lWrist    = isFrontCamera ? _leftWristPrecise : _rightWristPrecise;
    final rWrist    = isFrontCamera ? _rightWristPrecise : _leftWristPrecise;
    final lMiddle   = isFrontCamera ? _leftMiddleBase : _rightMiddleBase;
    final rMiddle   = isFrontCamera ? _rightMiddleBase : _leftMiddleBase;

    double shoulderL = _smoothed?.shoulderL ?? 0;
    double elbowL    = _smoothed?.elbowL ?? 0;
    double wristL    = _smoothed?.wristL ?? 0;
    double shoulderR = _smoothed?.shoulderR ?? 0;
    double elbowR    = _smoothed?.elbowR ?? 0;
    double wristR    = _smoothed?.wristR ?? 0;

    if (_visible(sc, lHip) && _visible(sc, lShoulder) && _visible(sc, lElbow)) {
      shoulderL = _shoulderRaiseDegrees(kp[lShoulder], kp[lElbow], kp[lHip]);
    }
    if (_visible(sc, lShoulder) && _visible(sc, lElbow) && _visible(sc, lWrist)) {
      elbowL = _elbowFlexDegrees(kp[lShoulder], kp[lElbow], kp[lWrist]);
    }
    if (_visible(sc, lElbow) && _visible(sc, lWrist) && _visible(sc, lMiddle)) {
      wristL = _wristTwistDegrees(kp[lElbow], kp[lWrist], kp[lMiddle]);
    }

    if (_visible(sc, rHip) && _visible(sc, rShoulder) && _visible(sc, rElbow)) {
      shoulderR = _shoulderRaiseDegrees(kp[rShoulder], kp[rElbow], kp[rHip]);
    }
    if (_visible(sc, rShoulder) && _visible(sc, rElbow) && _visible(sc, rWrist)) {
      elbowR = _elbowFlexDegrees(kp[rShoulder], kp[rElbow], kp[rWrist]);
    }
    if (_visible(sc, rElbow) && _visible(sc, rWrist) && _visible(sc, rMiddle)) {
      wristR = _wristTwistDegrees(kp[rElbow], kp[rWrist], kp[rMiddle]);
    }

    return BoneAngles(
      shoulderL: shoulderL,
      elbowL: elbowL,
      wristL: wristL,
      shoulderR: shoulderR,
      elbowR: elbowR,
      wristR: wristR,
    );
  }

  bool _visible(List<double> scores, int idx) =>
      idx < scores.length && scores[idx] > _scoreThreshold;

  double _elbowFlexDegrees(Offset shoulder, Offset elbow, Offset wrist) {
    final raw = _vectorAngleDegrees(
      shoulder.dx - elbow.dx, shoulder.dy - elbow.dy,
      wrist.dx - elbow.dx, wrist.dy - elbow.dy,
    );
    return (180.0 - raw).clamp(0.0, 150.0);
  }

  double _shoulderRaiseDegrees(Offset shoulder, Offset elbow, Offset hip) {
    final raw = _vectorAngleDegrees(
      shoulder.dx - hip.dx, shoulder.dy - hip.dy,
      elbow.dx - shoulder.dx, elbow.dy - shoulder.dy,
    );
    return (180.0 - raw).clamp(0.0, 160.0);
  }

  double _wristTwistDegrees(Offset elbow, Offset wrist, Offset middleBase) {
    final forearmX = wrist.dx - elbow.dx;
    final forearmY = wrist.dy - elbow.dy;
    final palmX = middleBase.dx - wrist.dx;
    final palmY = middleBase.dy - wrist.dy;
    final cross = forearmX * palmY - forearmY * palmX;
    final dot = forearmX * palmX + forearmY * palmY;
    return math.atan2(cross, dot) * 180.0 / math.pi.clamp(-90.0, 90.0);
  }

  double _vectorAngleDegrees(double v1x, double v1y, double v2x, double v2y) {
    final dot = v1x * v2x + v1y * v2y;
    final mag1 = math.sqrt(v1x * v1x + v1y * v1y);
    final mag2 = math.sqrt(v2x * v2x + v2y * v2y);
    if (mag1 == 0 || mag2 == 0) return 180.0;
    var cosAngle = dot / (mag1 * mag2);
    cosAngle = cosAngle.clamp(-1.0, 1.0);
    return math.acos(cosAngle) * 180.0 / math.pi;
  }

  BoneAngles _applySmoothing(BoneAngles raw) {
    if (_smoothed == null) return raw;
    final prev = _smoothed!;
    double lerp(double a, double b) => a + (b - a) * _smoothAlpha;
    return BoneAngles(
      shoulderL: lerp(prev.shoulderL, raw.shoulderL),
      elbowL: lerp(prev.elbowL, raw.elbowL),
      wristL: lerp(prev.wristL, raw.wristL),
      shoulderR: lerp(prev.shoulderR, raw.shoulderR),
      elbowR: lerp(prev.elbowR, raw.elbowR),
      wristR: lerp(prev.wristR, raw.wristR),
    );
  }

  void reset() {
    _smoothed = null;
  }
}