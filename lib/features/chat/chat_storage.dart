// lib/screens/chat/chat_storage.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_conversation.dart';
import 'chat_screen.dart';

class ChatStorage {
  static const _conversationsKey = 'conversations_v1';
  static const _currentIdKey = 'current_conversation_id_v1';
  static const _legacyKey = 'chat_messages'; // 舊版單一對話

  /// 讀所有對話(依更新時間新到舊)
  Future<List<ChatConversation>> getAll() async {
    await _migrateLegacyIfNeeded();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_conversationsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final all = list
          .map((e) =>
              ChatConversation.fromJson(e as Map<String, dynamic>))
          .toList();
      all.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return all;
    } catch (_) {
      return [];
    }
  }

  /// 讀目前使用中的對話 id;沒有就回 null
  Future<String?> getCurrentId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_currentIdKey);
  }

  Future<void> setCurrentId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentIdKey, id);
  }

  /// 存整份對話列表
  Future<void> saveAll(List<ChatConversation> list) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(list.map((c) => c.toJson()).toList());
    await prefs.setString(_conversationsKey, raw);
  }

  /// 存或更新單一對話
  Future<void> upsert(ChatConversation conv) async {
    final all = await getAll();
    final idx = all.indexWhere((c) => c.id == conv.id);
    if (idx >= 0) {
      all[idx] = conv;
    } else {
      all.add(conv);
    }
    await saveAll(all);
  }

  Future<void> delete(String id) async {
    final all = await getAll();
    all.removeWhere((c) => c.id == id);
    await saveAll(all);
  }

  /// 舊版單一對話 → 遷移成第一個 conversation
  /// 只在第一次執行,舊 key 保留(不刪),避免萬一 bug 導致資料丟失
  Future<void> _migrateLegacyIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final hasNew = prefs.getString(_conversationsKey);
    if (hasNew != null && hasNew.isNotEmpty) return;

    final legacy = prefs.getString(_legacyKey);
    if (legacy == null || legacy.isEmpty) return;

    try {
      final list = jsonDecode(legacy) as List<dynamic>;
      final messages = list
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
      if (messages.isEmpty) return;

      final now = DateTime.now();
      final conv = ChatConversation(
        id: now.microsecondsSinceEpoch.toString(),
        title: '${now.month}/${now.day} 舊對話',
        updatedAt: now,
        messages: messages,
      );
      await prefs.setString(
          _conversationsKey, jsonEncode([conv.toJson()]));
      await prefs.setString(_currentIdKey, conv.id);
    } catch (_) {
      // 舊資料壞掉就當作沒有,不阻塞新流程
    }
  }
}