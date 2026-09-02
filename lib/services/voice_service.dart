// lib/services/voice_service.dart
//
// ══════════════════════════════════════════════════════════════════
//  語音主控 — 全 App 唯一的語音出口
//
//  全身、手部兩邊都呼叫這裡。要換語音 / 改語速 / 改規則,只改這個檔。
//
//  功能:
//    1. TTS 設定集中(語速、語言)
//    2. 智慧挑聲音 — 掃描系統所有中文聲音,自動挑最高品質(去機械感)
//    3. 智慧過濾 — 只念「重要」的話,狀態提示不念(解決吵)
//    4. 防打斷 — 重要的話念完前,不被普通的話插隊(解決念一半)
//    5. 防重複 — 同一句剛念過就跳過
// ══════════════════════════════════════════════════════════════════

import 'package:flutter_tts/flutter_tts.dart';

class VoiceService {
  // ── flutter_tts 實例 ────────────────────────────────────────────
  // static:整個 App 共用同一個 TTS,不同畫面切換不會重新初始化
  static final FlutterTts _tts = FlutterTts();

  // ── 是否已初始化過(避免重複跑 init)──
  static bool _ready = false;

  // ── 記錄上一句念過的話 + 時間點,用來擋「同句快速重複」──
  static String _lastSpoken = '';
  static DateTime _lastSpeakTime = DateTime.now();

  // ── 「正在念重要句子」的鎖 ──
  // 重要句念完前(_speakingImportant = true),普通句都會被跳過,
  // 避免使用者聽到一半被截斷。念完由 CompletionHandler 解鎖。
  static bool _speakingImportant = false;

  // ── 黑名單 — 含這些關鍵字就跳過 ──
  // 這些是「狀態播報」,一直觸發會很吵,所以直接不念。
  static const List<String> _skipKeywords = [
    '已向外轉',
    '已向內轉',
    '已張開',
    '捏緊完成',
  ];

  // ══════════════════════════════════════════════════════════════
  //  對外 API
  // ══════════════════════════════════════════════════════════════

  /// 初始化 — App 啟動時呼叫一次
  /// 重複呼叫也安全(有 _ready 旗標擋著)
  static Future<void> init() async {
    if (_ready) return;

    // ── 基本 TTS 參數 ──
    await _tts.setLanguage('zh-TW');   // 台灣繁體中文
    await _tts.setSpeechRate(0.5);      // 語速:0.5 = 適合復健的慢速
    await _tts.setVolume(1.0);          // 音量:1.0 = 最大
    await _tts.setPitch(1.0);           // 音調:1.0 = 正常

    // ── 智慧挑聲音 ──
    // 掃描系統所有可用的 TTS 聲音,挑最好聽的中文那個
    // 這是「去機械感」的核心,不用改別的地方就有差
    await _pickBestChineseVoice();

    // ── 重要句念完時的回呼 ──
    // 讓 _speakingImportant 解鎖,後續普通句才能繼續念
    _tts.setCompletionHandler(() {
      _speakingImportant = false;
    });

    _ready = true;
  }

  /// 念一句話 — 畫面層直接把 feedback 丟進來
  /// VoiceService 自己決定要不要念(黑名單、去重、防打斷都在這判斷)
  static Future<void> speak(String text) async {
    // 沒 init 就補跑一次,防呆
    if (!_ready) await init();
    if (text.isEmpty) return;

    // 過濾 1:含「狀態提示」關鍵字 → 直接跳過
    for (final kw in _skipKeywords) {
      if (text.contains(kw)) return;
    }

    // 清掉 emoji / 符號,只留 TTS 能念的文字
    final clean = _stripEmoji(text);
    if (clean.isEmpty) return;

    final now = DateTime.now();

    // 過濾 2:同一句 2 秒內不重複念
    if (clean == _lastSpoken &&
        now.difference(_lastSpeakTime).inSeconds < 2) {
      return;
    }

    // 判斷這句重不重要(重要句可以打斷別人,自己也不被打斷)
    final important = _isImportant(clean);

    // 過濾 3:正在念重要句 → 普通句不插隊(解決「念一半」問題)
    if (_speakingImportant && !important) {
      return;
    }

    // 更新「上一句」記憶
    _lastSpoken = clean;
    _lastSpeakTime = now;

    if (important) {
      _speakingImportant = true;   // 上鎖,念完由 CompletionHandler 解開
      await _tts.stop();            // 重要句可以打斷別人正在念的普通句
    }

    // 真正念出來
    await _tts.speak(clean);
  }

  /// 立刻停止並清狀態 — 畫面 dispose 時呼叫
  /// 避免離開畫面後還在念上一句
  static Future<void> stop() async {
    _speakingImportant = false;
    await _tts.stop();
  }

  // ══════════════════════════════════════════════════════════════
  //  私有 helpers
  // ══════════════════════════════════════════════════════════════

  /// 掃描系統所有可用聲音,挑最高品質的中文那個
  ///
  /// 每台手機支援的聲音不一樣:
  ///   - 好手機:可能有 Neural / Wavenet 高品質中文
  ///   - 普通手機:可能只有預設機械聲
  ///
  /// 這個方法用「評分制」自動挑最好的:
  ///   1. 品質標記 "very high" / "high"    → 大加分
  ///   2. 名字含 neural / wavenet / network → 大加分(神經網路合成)
  ///   3. 台灣腔(zh-TW / cmn-tw)          → 中加分
  ///   4. 女聲                              → 小加分(復健 app 較合適)
  ///
  /// 失敗就直接用預設聲音,不影響功能
  static Future<void> _pickBestChineseVoice() async {
    try {
      final voices = await _tts.getVoices;
      if (voices == null || voices is! List) return;

      // 過濾:只留中文聲音
      // locale 開頭 zh 或 cmn(cmn = Mandarin Chinese,某些手機用這個)
      final chinese = voices
          .whereType<Map>()
          .where((v) {
            final locale = v['locale']?.toString().toLowerCase() ?? '';
            return locale.startsWith('zh') || locale.startsWith('cmn');
          })
          .toList();

      // 完全沒中文聲音 → 用預設
      if (chinese.isEmpty) return;

      // 評分函數
      int score(Map v) {
        var s = 0;
        final q = v['quality']?.toString().toLowerCase() ?? '';
        final n = v['name']?.toString().toLowerCase() ?? '';
        final locale = v['locale']?.toString().toLowerCase() ?? '';

        // 品質(Android 有標 quality 欄位,能挑的話一定要挑)
        if (q.contains('very high')) s += 100;
        if (q == 'high') s += 60;

        // 神經網路聲(名字裡有這些字眼,通常品質最高)
        if (n.contains('neural') ||
            n.contains('wavenet') ||
            n.contains('network')) s += 80;

        // 台灣腔優先(zh-TW / cmn-TW)
        if (locale.startsWith('zh-tw') || locale.contains('cmn-tw')) s += 40;

        // 女聲加分
        if (n.contains('female') || n.contains('女')) s += 20;

        return s;
      }

      // 按分數由高到低排序,挑第一名
      chinese.sort((a, b) => score(b).compareTo(score(a)));
      final best = chinese.first;

      // 套用選好的聲音
      await _tts.setVoice({
        'name': best['name'].toString(),
        'locale': best['locale'].toString(),
      });

      // Debug 印出:讓開發時能看到選了什麼
      // (Release 版本可以註解掉這行,但留著也不影響效能)
      print('[VoiceService] Picked voice: '
            '${best['name']} (${best['locale']}, quality=${best['quality']})');
    } catch (e) {
      // 挑聲失敗(某些手機不支援 getVoices / setVoice)
      // 靜默處理,用預設聲音,不影響 app 運作
      print('[VoiceService] pickBestChineseVoice failed: $e');
    }
  }

  /// 判斷這句話是不是「重要句」
  ///
  /// 重要句 = 使用者需要聽清楚的內容(完成、動作提示、結束訊息)
  /// 重要句會:
  ///   - 打斷正在念的普通句
  ///   - 上鎖,擋住後續普通句
  ///
  /// 想加新的重要關鍵字,改這個列表就好
  static bool _isImportant(String text) {
    const importantKeywords = [
      '完成', '捏緊了', '訓練結束', '太快',
      '歪', '通過', '開始翻掌', '解鎖', '難度',
    ];
    for (final kw in importantKeywords) {
      if (text.contains(kw)) return true;
    }
    return false;
  }

  /// 濾掉 emoji 跟符號,只留 TTS 能念的文字
  ///
  /// TTS 唸 emoji 會噴奇怪的東西(例如「拳頭表情符號」),
  /// 用 regex 只保留中文字、英數、基本標點
  static String _stripEmoji(String text) {
    return text
        .replaceAll(RegExp(r'[^\u4e00-\u9fa5a-zA-Z0-9,。!?、\s]'), '')
        .trim();
  }
}