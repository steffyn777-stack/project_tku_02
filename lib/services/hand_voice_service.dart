// lib/services/hand_voice_service.dart
//
// ══════════════════════════════════════════════════════════════════
//  手部訓練專用語音服務(mp3 版)
//
//  為什麼手部要獨立寫一個(不共用 VoiceService):
//    - 手部 MediaPipe landmarks 走 EventChannel(main thread)
//    - flutter_tts 走 method channel(main thread)
//    - 兩者搶 main thread → 骨架偵測掛掉
//
//  解法:改用 audioplayers 播預錄 mp3
//    - audioplayers 用 Android SoundPool / MediaPlayer(不吃 method channel)
//    - 不干擾 MediaPipe 的 EventChannel
//    - 骨架保住
//
//  對外 API(training_screen 呼叫):
//    HandVoiceService.speak(feedback);   ← 傳整段 feedback 字串
//    → 內部用 contains 比對,自動對到 mp3
//
//  想改語音(換 mp3、加事件、換套件)
//    → 只改這個檔,其他都不用動
// ══════════════════════════════════════════════════════════════════

import 'package:audioplayers/audioplayers.dart';

class HandVoiceService {
  static AudioPlayer? _player;
  
  static AudioPlayer _getPlayer() {
    _player ??= AudioPlayer();
    return _player!;
  }

  // ── 關鍵字 → mp3 對應表 ──
  // 傳進來的 feedback 只要「包含」某個 key,就播對應 mp3
  // 想加新對應 → 這裡加 1 行
  // 判斷順序有講究:訓練結束要在完成一次前面(不然「完成 10 次!訓練結束」會被判成完成一次)
  static const List<MapEntry<String, String>> _mp3Rules = [
    // ── 特殊事件優先 ──
    MapEntry('訓練結束', 'audio/training_end.mp3'),
    MapEntry('完成 10 次', 'audio/training_end.mp3'),
    MapEntry('下一階段', 'audio/next_phase.mp3'),
    MapEntry('進入階段', 'audio/next_phase.mp3'),
    
    // ── 完成一次(4 個手部動作用不同字串,共通到同一個 mp3) ──
    MapEntry('完成一次', 'audio/rep_done.mp3'),
    MapEntry('捏緊了', 'audio/rep_done.mp3'),
    MapEntry('完成一組', 'audio/rep_done.mp3'),
    MapEntry('往上翹到了', 'audio/rep_done.mp3'),
    
    // ── 警告類 ──
    MapEntry('太快', 'audio/too_fast.mp3'),
    MapEntry('太急', 'audio/too_fast.mp3'),
    MapEntry('歪', 'audio/tilted.mp3'),
    
    // ── 開始 ──
    MapEntry('開始', 'audio/start.mp3'),
  ];

  // ── 防重複:同 mp3 2 秒內只播一次 ──
  static String _lastMp3 = '';
  static DateTime _lastPlayTime = DateTime.now();

  /// 對外 API:傳 feedback 字串進來,自動判斷播哪個 mp3
  ///
  /// - 找不到對應 → 靜默(只印 log,不會壞)
  /// - 同 mp3 2 秒內不重播
  static Future<void> speak(String feedback) async {
    if (feedback.isEmpty) return;

    // 找對應的 mp3(按 _mp3Rules 順序找,找到就用)
    String? mp3Path;
    for (final rule in _mp3Rules) {
      if (feedback.contains(rule.key)) {
        mp3Path = rule.value;
        break;
      }
    }

    if (mp3Path == null) {
      // 找不到對應 mp3 → 靜默(印 log 方便 debug)
      print('[HandVoiceService] no mp3 for: "$feedback"');
      return;
    }

    // 2 秒內同 mp3 不重播
    final now = DateTime.now();
    if (mp3Path == _lastMp3 &&
        now.difference(_lastPlayTime).inSeconds < 2) {
      return;
    }
    _lastMp3 = mp3Path;
    _lastPlayTime = now;

    try {
      await _getPlayer().play(AssetSource(mp3Path));
    } catch (e) {
      print('[HandVoiceService] play failed: $e');
    }
  }

  /// 停止播放(離開畫面時呼叫)
  static Future<void> stop() async {
    try {
      await _getPlayer().stop();
    } catch (_) {}
  }
}