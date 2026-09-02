// lib/features/notification/notification_service.dart
//
// 通知服務 — 管理 App 內通知列表 + 本地排程推播 + 全域開關

import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;

import 'app_notification.dart';
import 'native_notification_service.dart';

class NotificationService {
  // Singleton
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  static const _storageKey = 'app_notifications_v1';
  static const _enabledKey = 'notifications_enabled_v1';
  static const _reminderHourKey = 'reminder_hour_v1';
  static const _reminderMinKey = 'reminder_min_v1';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _inited = false;

  // ═══ 初始化 ═════════════════════════════════════════════
  Future<void> init() async {
    if (_inited) return;
    tz.initializeTimeZones();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    _inited = true;
  }

  // ═══ 全域通知開關 ═══════════════════════════════════════
  // 預設關,使用者要自己開
  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);

    if (value) {
      await _requestPermission();
      final h = await getReminderHour();
      final m = await getReminderMinute();
      await _scheduleDailyReminder(hour: h, minute: m);
    } else {
      // 關閉時取消 Flutter 舊排程 + 原生排程
      await _plugin.cancelAll();
      await NativeNotificationService.cancelNotification(1001);
    }
  }

  Future<void> _requestPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  // ═══ 提醒時間設定 ═══════════════════════════════════════
  Future<int> getReminderHour() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_reminderHourKey) ?? 20;
  }

  Future<int> getReminderMinute() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_reminderMinKey) ?? 0;
  }

  Future<void> setReminderTime(int hour, int minute) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_reminderHourKey, hour);
    await prefs.setInt(_reminderMinKey, minute);

    // 如果目前是開啟狀態,更新排程
    if (await isEnabled()) {
      await _scheduleDailyReminder(hour: hour, minute: minute);
    }
  }

  // 給首頁用:如果通知開著,重新排一次下一天的提醒
  // 目的:繞過 MIUI 有時會清掉舊 alarm 的行為
  Future<void> refreshDailyReminderIfEnabled() async {
    if (!await isEnabled()) return;
    final h = await getReminderHour();
    final m = await getReminderMinute();
    await _scheduleDailyReminder(hour: h, minute: m);
  }

  // ═══ App 內通知列表 ═════════════════════════════════════
  Future<List<AppNotification>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_storageKey) ?? [];
    return raw
        .map((s) => AppNotification.fromJson(jsonDecode(s)))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  Future<int> getUnreadCount() async {
    final list = await getAll();
    return list.where((n) => !n.read).length;
  }

  Future<void> add(AppNotification n) async {
    // 通知關閉時,不塞任何通知
    if (!await isEnabled()) return;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_storageKey) ?? [];
    raw.add(jsonEncode(n.toJson()));
    await prefs.setStringList(_storageKey, raw);
  }

  Future<void> markAllRead() async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getAll();
    final updated = list
        .map((n) => n.copyWith(read: true).toJson())
        .map(jsonEncode)
        .toList();
    await prefs.setStringList(_storageKey, updated);
  }

  Future<void> removeById(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_storageKey) ?? [];
    raw.removeWhere((s) {
      final json = jsonDecode(s) as Map<String, dynamic>;
      return json['id'] == id;
    });
    await prefs.setStringList(_storageKey, raw);
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  // ═══ 快速加成就通知 ═════════════════════════════════════
  Future<void> addAchievement({
    required String title,
    required String body,
  }) async {
    // 1. 塞進 app 內通知中心(鈴鐺點進去看得到)
    await add(AppNotification(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      type: NotificationType.achievement,
      title: title,
      body: body,
      timestamp: DateTime.now().toIso8601String(),
    ));

    // 2. 通知關閉時不彈系統橫幅
    if (!await isEnabled()) return;

    // 3. 用原生 AlarmManager 立刻彈系統橫幅(1 秒後觸發)
    // id 用 timestamp 後 6 位,避免跟每日提醒 (1001) 或別的成就撞
    final id = (DateTime.now().millisecondsSinceEpoch % 900000) + 100000;
    await NativeNotificationService.scheduleNotification(
      id: id,
      title: title,
      body: body,
      triggerAt: DateTime.now().add(const Duration(seconds: 1)),
    );
  }

  // ═══ 本地排程推播(內部方法) ═══════════════════════════
  // ═══ 本地排程推播(內部方法)——改用原生 AlarmManager 繞過 MIUI ══
  Future<void> _scheduleDailyReminder({
    required int hour,
    required int minute,
  }) async {
    // 先取消舊的
    await NativeNotificationService.cancelNotification(1001);

    // 算下一次觸發時間
    final now = DateTime.now();
    var next = DateTime(now.year, now.month, now.day, hour, minute);
    if (next.isBefore(now)) {
      next = next.add(const Duration(days: 1));
    }

    await NativeNotificationService.scheduleNotification(
      id: 1001,
      title: '該做復健啦 💪',
      body: '別讓連續達成中斷,今天還有時間',
      triggerAt: next,
    );
  }
}