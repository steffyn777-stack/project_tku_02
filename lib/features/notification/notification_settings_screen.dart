// lib/features/notification/notification_settings_screen.dart

import 'package:flutter/material.dart';
import 'notification_service.dart';
import 'native_notification_service.dart';

// 🖥️ 電視投放新增
import '../tv_cast/socket_client_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final _service = NotificationService();
  final _clientService = SocketClientService(); // 🖥️ 電視投放新增
  bool _enabled = false;
  int _hour = 20;
  int _minute = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await _service.isEnabled();
    final h = await _service.getReminderHour();
    final m = await _service.getReminderMinute();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _hour = h;
      _minute = m;
      _loading = false;
    });
  }

  Future<void> _toggle(bool value) async {
    setState(() => _enabled = value);
    await _service.setEnabled(value);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _hour, minute: _minute),
    );
    if (picked == null) return;
    setState(() {
      _hour = picked.hour;
      _minute = picked.minute;
    });
    await _service.setReminderTime(picked.hour, picked.minute);
  }

  String get _timeText =>
      '${_hour.toString().padLeft(2, '0')}:${_minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: GestureDetector(
          onTap: () {
            // 🖥️ 電視投放新增:同步返回指令
            if (_clientService.isConnected) {
              _clientService.sendCommand({'type': 'POP_SCREEN'});
            }
            Navigator.of(context).pop();
          },
          child: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        title: const Text('通知設定',
            style: TextStyle(
                color: Color(0xFF1A1D2E),
                fontSize: 17,
                fontWeight: FontWeight.w800)),
        iconTheme: const IconThemeData(color: Color(0xFF1A1D2E)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('啟用通知',
                            style: TextStyle(
                                color: Color(0xFF1A1D2E),
                                fontWeight: FontWeight.w700)),
                        subtitle: const Text('包含訓練提醒與成就通知',
                            style: TextStyle(
                                color: Color(0xFF6B7280), fontSize: 12)),
                        value: _enabled,
                        onChanged: _toggle,
                        activeThumbColor: const Color(0xFF4A65FF),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        title: const Text('每日提醒時間',
                            style: TextStyle(
                                color: Color(0xFF1A1D2E),
                                fontWeight: FontWeight.w700)),
                        subtitle: Text(_enabled ? _timeText : '通知關閉中',
                            style: const TextStyle(
                                color: Color(0xFF6B7280), fontSize: 12)),
                        trailing: const Icon(Icons.chevron_right,
                            color: Color(0xFF9CA3AF)),
                        enabled: _enabled,
                        onTap: _enabled ? _pickTime : null,
                      ),
                    ],
                  ),
                ),
                if (_enabled) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await NativeNotificationService.scheduleNotification(
                          id: 9999,
                          title: '測試通知 🔔(原生)',
                          body: '如果你看到這個 = MIUI 沒殺我 🎉',
                          triggerAt:
                              DateTime.now().add(const Duration(seconds: 5)),
                        );
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('5 秒後跳原生通知,可以直接把 app 關掉試看看'),
                            duration: Duration(seconds: 3),
                          ),
                        );
                      },
                      icon: const Icon(Icons.notifications_active_outlined),
                      label: const Text('立刻測試通知(5 秒後)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4A65FF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '關閉通知後,系統排程推播會全部取消,\n訓練完成也不會再產生成就通知。\n已存在的通知記錄會保留。',
                    style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 11),
                  ),
                ),
              ],
            ),
    );
  }
}
