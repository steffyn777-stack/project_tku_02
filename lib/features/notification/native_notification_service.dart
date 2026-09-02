// lib/features/notification/native_notification_service.dart
//
// 呼叫原生 Android 的 AlarmManager 排程通知 — 繞過 MIUI 殺鎖

import 'package:flutter/services.dart';

class NativeNotificationService {
  static const _channel =
      MethodChannel('com.example.flutter_body/native_notification');

  static Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime triggerAt,
  }) async {
    await _channel.invokeMethod('scheduleNotification', {
      'id': id,
      'title': title,
      'body': body,
      'triggerAtMillis': triggerAt.millisecondsSinceEpoch,
    });
  }

  static Future<void> cancelNotification(int id) async {
    await _channel.invokeMethod('cancelNotification', {'id': id});
  }
}