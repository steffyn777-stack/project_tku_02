// lib/features/chat/therapist.dart
//
// 治療師資料 model + 目前的 mock 資料
// 未來接後端時,mock 清單換成從 API 拉即可,UI 不用動

class Therapist {
  final String id;
  final String name;
  final String title;        // 頭銜:物理治療師 / 職能治療師
  final String clinic;       // 所屬診所
  final String avatarText;   // 頭像顯示的字(通常姓氏)
  final String lastMessage;  // 最後一則訊息預覽
  final String lastTime;     // 最後互動時間(顯示用字串)
  final bool online;         // 線上狀態
  final int unread;          // 未讀數

  const Therapist({
    required this.id,
    required this.name,
    required this.title,
    required this.clinic,
    required this.avatarText,
    required this.lastMessage,
    required this.lastTime,
    required this.online,
    required this.unread,
  });
}

/// 目前的假治療師清單
/// 未來:改成從後端拉「這個病人綁定了哪些治療師」
const List<Therapist> kMockTherapists = [
  Therapist(
    id: 't1',
    name: '王怡君',
    title: '物理治療師',
    clinic: '康復物理治療所',
    avatarText: '王',
    lastMessage: '這週的訓練報告我看過了,進步很多喔!',
    lastTime: '2 天前',
    online: true,
    unread: 1,
  ),
  Therapist(
    id: 't2',
    name: '陳建豪',
    title: '職能治療師',
    clinic: '康復物理治療所',
    avatarText: '陳',
    lastMessage: '記得每天要做手部的伸展運動',
    lastTime: '5 天前',
    online: false,
    unread: 0,
  ),
];