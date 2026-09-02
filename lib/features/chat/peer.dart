// lib/features/chat/peer.dart
//
// 病友(復健夥伴)資料 model + mock 資料
// 未來接後端:改成配對「相似病況/復健階段」的病友

class Peer {
  final String id;
  final String nickname;     // 暱稱(病友之間用暱稱,保護隱私)
  final String condition;    // 病況分類:中風 / 骨折 / 術後
  final int week;            // 復健第幾週
  final String avatarText;   // 頭像字
  final String lastMessage;
  final String lastTime;
  final bool trainedToday;   // 今天練了沒(互相督促用)
  final int unread;

  const Peer({
    required this.id,
    required this.nickname,
    required this.condition,
    required this.week,
    required this.avatarText,
    required this.lastMessage,
    required this.lastTime,
    required this.trainedToday,
    required this.unread,
  });
}

/// 目前的假病友清單
/// 未來:後端配對相似病況的病友
const List<Peer> kMockPeers = [
  Peer(
    id: 'p1',
    nickname: '努力的小李',
    condition: '中風',
    week: 8,
    avatarText: '李',
    lastMessage: '今天抬腳終於可以到腰部了!',
    lastTime: '1 小時前',
    trainedToday: true,
    unread: 2,
  ),
  Peer(
    id: 'p2',
    nickname: '阿明',
    condition: '骨折',
    week: 3,
    avatarText: '明',
    lastMessage: '一起加油,慢慢來就好',
    lastTime: '昨天',
    trainedToday: false,
    unread: 0,
  ),
  Peer(
    id: 'p3',
    nickname: '復健小達人',
    condition: '術後',
    week: 12,
    avatarText: '達',
    lastMessage: '謝謝你上次的鼓勵 😊',
    lastTime: '3 天前',
    trainedToday: true,
    unread: 0,
  ),
];