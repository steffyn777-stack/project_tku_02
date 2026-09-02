// lib/features/notification/notification_screen.dart

import 'package:flutter/material.dart';
import 'app_notification.dart';
import 'notification_service.dart';
import 'notification_settings_screen.dart';

// 🖥️ 電視投放新增
import '../tv_cast/socket_client_service.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final _service = NotificationService();
  final _clientService = SocketClientService(); // 🖥️ 電視投放新增
  List<AppNotification> _items = [];
  bool _enabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _service.getAll();
    final enabled = await _service.isEnabled();
    if (!mounted) return;
    setState(() {
      _items = list;
      _enabled = enabled;
      _loading = false;
    });
    await _service.markAllRead();
  }

  IconData _iconFor(NotificationType t) => switch (t) {
        NotificationType.reminder => Icons.access_time_rounded,
        NotificationType.achievement => Icons.emoji_events_rounded,
        NotificationType.system => Icons.info_outline_rounded,
      };

  Color _colorFor(NotificationType t) => switch (t) {
        NotificationType.reminder => const Color(0xFF4A65FF),
        NotificationType.achievement => const Color(0xFFF59E0B),
        NotificationType.system => const Color(0xFF6B7280),
      };

  String _formatTime(String iso) {
    final dt = DateTime.parse(iso);
    return '${dt.month}/${dt.day} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && _clientService.isConnected) {
          _clientService.sendCommand({'type': 'POP_SCREEN'});
        }
      },
      child: Scaffold(
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
          title: const Text('通知中心',
              style: TextStyle(
                  color: Color(0xFF1A1D2E),
                  fontSize: 17,
                  fontWeight: FontWeight.w800)),
          iconTheme: const IconThemeData(color: Color(0xFF1A1D2E)),
          actions: [
            IconButton(
              icon:
                  const Icon(Icons.settings_outlined, color: Color(0xFF374151)),
              onPressed: () async {
                if (_clientService.isConnected) {
                  _clientService.sendCommand({
                    'type': 'OPEN_SCREEN',
                    'screen': 'NOTIFICATION_SETTINGS'
                  });
                }
                await Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const NotificationSettingsScreen()),
                );
                if (mounted) _load();
              },
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (!_enabled) _buildDisabledBanner(),
                  Expanded(
                    child: _items.isEmpty
                        ? _buildEmpty()
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _items.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) {
                              final item = _items[i];
                              return Dismissible(
                                key: ValueKey(item.id),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEF4444),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(Icons.delete_outline,
                                      color: Colors.white, size: 22),
                                ),
                                onDismissed: (_) async {
                                  await _service.removeById(item.id);
                                  if (!mounted) return;
                                  setState(() => _items.removeAt(i));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('已刪除通知'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                },
                                child: _buildItem(item),
                              );
                            },
                          ),
                  ),
                  if (_items.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () async {
                            await _service.clearAll();
                            _load();
                          },
                          child: const Text('清空全部',
                              style: TextStyle(color: Color(0xFF6B7280))),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildDisabledBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.notifications_off_outlined,
              color: Color(0xFF92400E), size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('通知功能目前為關閉狀態',
                style: TextStyle(
                    color: Color(0xFF92400E),
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () async {
              if (_clientService.isConnected) {
                _clientService.sendCommand(
                    {'type': 'OPEN_SCREEN', 'screen': 'NOTIFICATION_SETTINGS'});
              }
              await Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const NotificationSettingsScreen()),
              );
              if (mounted) _load();
            },
            child:
                const Text('前往開啟', style: TextStyle(color: Color(0xFF92400E))),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_off_outlined,
              size: 56, color: const Color(0xFF9CA3AF).withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          const Text('目前沒有通知',
              style: TextStyle(color: Color(0xFF6B7280), fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildItem(AppNotification n) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _colorFor(n.type).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_iconFor(n.type), color: _colorFor(n.type), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(n.title,
                    style: const TextStyle(
                        color: Color(0xFF1A1D2E),
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(n.body,
                    style: const TextStyle(
                        color: Color(0xFF6B7280), fontSize: 12, height: 1.4)),
                const SizedBox(height: 6),
                Text(_formatTime(n.timestamp),
                    style: const TextStyle(
                        color: Color(0xFF9CA3AF), fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
