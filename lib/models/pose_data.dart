// lib/models/pose_data.dart
import 'dart:ui';

class PoseData {
  final List<Offset> keypoints;
  final List<double> scores;
  const PoseData(this.keypoints, this.scores);
  static PoseData empty() => const PoseData([], []);
}