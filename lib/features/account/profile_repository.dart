import 'dart:convert';
import 'package:http/http.dart' as http;
import 'profile_model.dart';

class ProfileRepository {
  // ⚠️ 手機實機測試時，要換成電腦的區網 IP，例如 'http://192.168.1.100:8080'
  static const String baseUrl = 'http://localhost:8080';

  /// 取得個人資料
  Future<ProfileModel> fetchProfile(String userId) async {
    final uri = Uri.parse('$baseUrl/profile/$userId'); // ⚠️ 路徑待確認
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return ProfileModel.fromJson(data);
    } else {
      throw Exception('取得個人資料失敗 (狀態碼: ${response.statusCode})');
    }
  }

  /// 更新個人資料
  Future<void> updateProfile(ProfileModel profile) async {
    final uri = Uri.parse('$baseUrl/profile/${profile.id}'); // ⚠️ 路徑待確認
    final response = await http.put(
      uri,
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      body: jsonEncode(profile.toJson()),
    );

    if (response.statusCode != 200) {
      throw Exception('更新個人資料失敗 (狀態碼: ${response.statusCode})');
    }
  }

  /// 先拿來測試連線有沒有通（打首頁）
  Future<bool> testConnection() async {
    try {
      final response = await http.get(Uri.parse(baseUrl));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}