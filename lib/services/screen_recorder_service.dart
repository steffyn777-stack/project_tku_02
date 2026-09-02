// lib/services/screen_recorder_service.dart
//
// 封裝原生端 com.rehabassist/screen_recorder MethodChannel
// 提供:請求權限 / 開始錄影 / 停止錄影(回傳檔案路徑)
//
// ⚠️ 重要:Android 14 (API 34) 開始,MediaProjection 授權 token 是「一次性」的,
// stop() 之後就失效,不能重複拿同一個 token 再錄一次。
// 所以這裡改成「每次 startRecording() 都重新跳系統授權框」,
// 不再快取 _hasPermission,確保每次錄影都是拿到全新、有效的 token。
//
// 使用者體驗上,每次開始訓練前會看到一次系統的「開始擷取畫面」授權視窗,
// 這是 Android 的安全機制,無法繞過或關閉。

import 'package:flutter/services.dart';

class ScreenRecorderService {
  static const MethodChannel _channel =
      MethodChannel('com.rehabassist/screen_recorder');

  /// 跳出 Android 系統的「允許螢幕錄製」授權框。
  static Future<bool> requestPermission() async {
    try {
      final granted = await _channel.invokeMethod<bool>('requestPermission');
      return granted ?? false;
    } catch (e) {
      // 包含 PlatformException、MissingPluginException 等所有可能的例外,
      // 確保錄影功能失敗時不會拖垮訓練結束的流程
      // ignore: avoid_print
      print('ScreenRecorderService.requestPermission 失敗: $e');
      return false;
    }
  }

  /// 開始錄影。每次呼叫都會先重新請求授權(見上方說明),
  /// 使用者會看到系統的「開始擷取畫面」視窗。
  static Future<bool> startRecording() async {
    final granted = await requestPermission();
    if (!granted) return false;

    try {
      final started = await _channel.invokeMethod<bool>('startRecording');
      return started ?? false;
    } catch (e) {
      // ignore: avoid_print
      print('ScreenRecorderService.startRecording 失敗: $e');
      return false;
    }
  }

  /// 停止錄影,回傳錄好的影片檔案路徑,失敗或沒在錄則回傳 null。
  static Future<String?> stopRecording() async {
    try {
      final path = await _channel.invokeMethod<String>('stopRecording');
      return path;
    } catch (e) {
      // ignore: avoid_print
      print('ScreenRecorderService.stopRecording 失敗: $e');
      return null;
    }
  }
}