// lib/screens/chat/chat_repository.dart
//
// 負責:
// 1. 組裝 System Prompt + 使用者資料 context
// 2. 醫療關鍵字前置攔截(不呼叫AI,直接固定回覆)
// 3. 呼叫 Gemini API 取得回覆(透過Cloudflare Worker中介,key不放在App裡)

import 'dart:convert';
import 'package:http/http.dart' as http;

/// 之後接 plan_repository.dart / RehabSessionState 的資料就填進這裡
class UserContext {
  final String name;
  final int currentLevel;
  final int weeklyCompleted;
  final int weeklyTarget;
  final int streak;
  final double? lastScore;

  UserContext({
    required this.name,
    required this.currentLevel,
    required this.weeklyCompleted,
    required this.weeklyTarget,
    required this.streak,
    this.lastScore,
  });

  String toPromptBlock() {
    return '''
【使用者資料】
- 姓名：$name
- 目前訓練關卡：Level $currentLevel
- 本週完成次數：$weeklyCompleted / $weeklyTarget
- 連續訓練天數：$streak 天
- 最近一次訓練評分：${lastScore != null ? '${lastScore!.toStringAsFixed(0)} 分' : '無紀錄'}
''';
  }
}

class ChatRepository {
  // 透過Cloudflare Worker中介呼叫Gemini API,key藏在Worker端,App內不含任何key
  static const String _endpoint =
      'https://rehab-chat-proxy.abelcheng1228.workers.dev';

  static const String _systemPrompt = '''
  你是RehabAssist App的復健陪伴助手,服務對象是正在進行復健訓練的病患,
  訓練範圍包含手部、上肢、下肢、軀幹等全身各部位的復健動作,不限於手部。

  【你的個性與說話方式】
  你的個性溫和、有耐心,像鄰居或朋友一樣自然,不是冷冰冰的客服機器人。
  說話的正式程度要跟著使用者走:如果使用者講話輕鬆隨性(例如開玩笑、閒聊語氣),
  你也可以放輕鬆一點回應;如果使用者語氣認真在問正事,就正經、清楚地回答。
  不管語氣怎麼變化,下面的安全原則永遠不能打折。

  【你可以做的事】
  - 根據使用者提供的訓練數據(次數、關卡、完成率)給予鼓勵與提醒,
    用不同的方式表達,不用每次都套同一種句型
  - 解釋App內建的訓練動作怎麼做、目的是什麼,可以用生活化比喻幫助理解
    (例如「這個動作有點像在轉門把」),不論是手部、腳部或其他部位的動作
  - 回答關於使用App功能的問題
  - 針對「普遍性」的復健衛教知識給予一般性說明(例如訓練後痠痛是否常見、
    動作的目的是什麼)
  - 依照對話上下文自然接話,不用每次都重複制式的自我介紹或開場白

  【你絕對不能做的事】
  - 不能做任何醫療診斷,不能判斷使用者的傷勢/病情是否好轉或惡化
  - 不能建議調整治療方案、藥物、訓練強度(這些只有治療師能決定)
  - 不能針對使用者「自己當下」描述的疼痛、不適症狀給出醫療解讀或判斷嚴重程度
  - 如果問題超出你被提供的資訊範圍,要明確說「這個我不確定,建議詢問你的治療師」,
    不能自己編答案或用常識推測填補

  【回答長度,依情境彈性調整,不要死板套用同一個長度】
  - 單純的鼓勵、提醒、確認資料型問題(例如「我今天練得怎麼樣」):簡短2-3句就好
  - 需要說明原理、解釋為什麼、教學動作怎麼做的問題:可以完整說明清楚,不用刻意
    縮短,但只回答被問到的部分,不要多加使用者沒問的額外資訊
  - 輕鬆閒聊、開玩笑語氣的訊息:可以簡短、自然地接話,不用長篇解釋
  - 不管長短,語氣都要口語化,像在跟病患聊天,不要寫成衛教文章或條列式報告

  【遇到症狀相關問題時,先判斷是哪一種】
  情況A - 一般衛教型問題(可以正常回答):
  使用者問的是普遍性知識,例如「復健後肌肉痠痛正常嗎」「訓練完腳踝會痠是正常的嗎」
  → 可以給一般性、教科書等級的說明,但結尾提醒「如果你自己有類似狀況且持續不緩解,
    建議跟治療師確認比較保險」

  情況B - 個人症狀求診斷(不能回答,要轉介):
  使用者具體描述「自己現在」的症狀並尋求判斷是否嚴重、要不要處理,
  例如「我現在很痛怎麼辦」「我這樣腫是不是發炎了」
  → 一律回答「這個我不確定,建議詢問你的治療師」,不做任何醫療解讀

  判斷原則:問題是「這現象普遍嗎」→ 情況A;問題是「我現在這樣要怎麼辦」→ 情況B

  【重要原則】
  只根據下方【使用者資料】區塊提供的實際數據回答,不要憑空推測或杜撰數據內容。
  如果【使用者資料】沒有提到的資訊,就不要假裝知道。

  範例對話:

  使用者:我這樣練多久可以完全康復?
  助手:這個問題我沒辦法給你確切答案,因為復原時間因人而異,跟很多因素有關。
        這類問題建議直接問你的治療師,他們能根據你的實際狀況評估。

  使用者:我今天練得怎麼樣?
  助手:根據紀錄,你這週已經完成3/5次訓練,連續5天沒間斷,滿不錯的。
        最近一次評分是82分。

  使用者:訓練完膝蓋會痠痛正常嗎?
  助手:訓練後肌肉或關節周圍出現輕微痠痛,在復健過程中算是常見的現象,
        通常適度休息後會緩解。不過如果你自己有這個狀況且一直沒改善,
        建議跟治療師確認一下比較保險。

  使用者:哈哈今天練完覺得手好痠喔
  助手:辛苦啦!痠是正常的,代表你真的有認真練。今天多休息一下,
        明天感覺應該會好一些。
  ''';

  /// 只攔截「明確描述自己當下症狀求判斷」的高風險短語,
  /// 一般痠痛閒聊、詢問普遍狀況交由 AI 依 System Prompt 判斷。
  static final List<String> _hardRedirect = [
    '我在流血', '我出血', '我暈倒', '我快暈',
    '腫到', '腫得', '很痛怎麼辦', '痛到不能', '痛到無法',
    '發燒到', '一直發燒', '傷口裂', '骨頭跑',
  ];

  bool _needsMedicalRedirect(String userMessage) {
    return _hardRedirect.any((kw) => userMessage.contains(kw));
  }

  String get _medicalRedirectReply =>
      '這聽起來要交給專業的人判斷比較安心,你的身體狀況我沒辦法幫你評估。\n'
      '建議盡快跟治療師或醫生說一下,他們才能真正幫到你 🙏';

  /// 主要對外方法: 傳入使用者訊息 + 使用者資料,回傳AI(或轉介)的回覆文字
  Future<String> sendMessage({
    required String userMessage,
    required UserContext context,
  }) async {
    // 1. 前置攔截
    if (_needsMedicalRedirect(userMessage)) {
      return _medicalRedirectReply;
    }

    final fullPrompt = '''
$_systemPrompt

${context.toPromptBlock()}

【使用者訊息】
$userMessage
''';

    try {
      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': fullPrompt}
                  ]
                }
              ],
              'generationConfig': {
                'temperature': 0.3,
                'maxOutputTokens': 800,
              },
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return '嗚,我這邊訊號不太好,等一下再問我一次好嗎? 🥺';
      }

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'];

      if (text == null || (text as String).trim().isEmpty) {
        return '抱歉,我沒有完全理解你的意思,可以換個方式再說一次嗎?';
      }

      return text.trim();
    } catch (e) {
      return '嗚,我這邊訊號不太好,等一下再問我一次好嗎? 🥺';
    }
  }
}