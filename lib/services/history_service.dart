import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/training_action.dart';
import '../features/notification/notification_service.dart';
import 'package:flutter/foundation.dart';

class HistoryService extends ChangeNotifier {
  // 其他不動
  static const String _key = 'rehab_history';

  Future<List<TrainingRecord>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_key) ?? '[]';
    final List<dynamic> list = jsonDecode(jsonStr);
    return list.map((e) => TrainingRecord.fromJson(e)).toList();
  }

  Future<void> saveRecord(TrainingRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await getHistory();
    history.add(record);
    await prefs.setString(_key, jsonEncode(history.map((e) => e.toJson()).toList()));

    final mistakes = record.mistakeLogs.length;
    final acc = ((10 - mistakes) / 10 * 100).clamp(0, 100).round();
    NotificationService().addAchievement(
      title: mistakes == 0 ? '完美完成一組訓練 🎯' : '完成一組訓練 ✅',
      body: '「${record.actionName}」${record.targetReps} 下 · 準確度 $acc%',
    ).catchError((_) {});

    notifyListeners();  // ← 新增
  }

  /// 把「最後 count 筆」紀錄的 videoPath 更新成同一個值。
  ///
  /// 用途:一次訓練 session 中可能因為升級難度分批存了好幾筆
  /// TrainingRecord(此時還不知道使用者要不要保留錄影),
  /// 等到 session 真正結束、使用者做出保留/不保留的決定後,
  /// 才回頭把這幾筆紀錄的 videoPath 補齊,讓它們共用同一段影片。
  ///
  /// 因為紀錄是依 saveRecord() 呼叫順序附加在陣列尾端,
  /// 「最後 count 筆」就對應「這個 session 存的所有紀錄」。
  Future<void> updateLastRecordsVideoPath(int count, String? videoPath) async {
    if (count <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final history = await getHistory();
    if (history.isEmpty) return;

    final updateCount = count > history.length ? history.length : count;
    final startIndex = history.length - updateCount;

    for (int i = startIndex; i < history.length; i++) {
      history[i] = history[i].copyWithVideoPath(videoPath);
    }

    await prefs.setString(_key, jsonEncode(history.map((e) => e.toJson()).toList()));

    notifyListeners();  // ← 新增
  }

  Future<void> removeByTimestamp(String timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await getHistory();
    history.removeWhere((r) => r.timestamp == timestamp);
    await prefs.setString(
        _key, jsonEncode(history.map((e) => e.toJson()).toList()));

    notifyListeners();  // ← 新增
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);

    notifyListeners();  // ← 新增
  }
}