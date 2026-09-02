// lib/features/notification/app_notification.dart
//
// App 內通知資料模型

enum NotificationType {
  reminder,    // 提醒(該練了)
  achievement, // 成就(連續達成、首次完成)
  system,      // 系統(app 更新、新動作)
}

class AppNotification {
  final String id;
  final NotificationType type;
  final String title;
  final String body;
  final String timestamp;
  final bool read;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.timestamp,
    this.read = false,
  });

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        type: type,
        title: title,
        body: body,
        timestamp: timestamp,
        read: read ?? this.read,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'body': body,
        'timestamp': timestamp,
        'read': read,
      };

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String,
        type: NotificationType.values.firstWhere((e) => e.name == j['type']),
        title: j['title'] as String,
        body: j['body'] as String,
        timestamp: j['timestamp'] as String,
        read: j['read'] as bool? ?? false,
      );
}