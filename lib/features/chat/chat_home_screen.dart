// lib/features/chat/chat_home_screen.dart
//
// 聊天分頁首頁(列表)— 三區:
//   1. AI 助手(漸層卡,置頂)
//   2. 我的照護團隊(治療師)
//   3. 一起加油的夥伴(病友)
//
// 治療師、病友目前全 mock,加入/聊天先跳提示,等後端接。

import 'package:flutter/material.dart';
import 'chat_screen.dart';
import 'therapist.dart';
import 'peer.dart';

// 🖥️ 電視投放新增
import '../tv_cast/socket_client_service.dart';

class ChatHomeScreen extends StatefulWidget {
  const ChatHomeScreen({super.key});

  @override
  State<ChatHomeScreen> createState() => _ChatHomeScreenState();
}

class _ChatHomeScreenState extends State<ChatHomeScreen> {
  final _clientService = SocketClientService(); // 🖥️ 電視投放新增
  List<Therapist> get _therapists => kMockTherapists;
  List<Peer> get _peers => kMockPeers;

  void _openAiChat() {
    // 🖥️ 電視投放新增:同步跳轉指令
    if (_clientService.isConnected) {
      _clientService.sendCommand({'type': 'OPEN_SCREEN', 'screen': 'CHAT_AI'});
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ChatScreen()),
    );
  }

  void _openTherapistChat(Therapist t) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('即將開啟與 ${t.name} 的對話')),
    );
  }

  void _openPeerChat(Peer p) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('即將開啟與 ${p.nickname} 的對話')),
    );
  }

  void _addTherapist() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('加入治療師功能開發中')),
    );
  }

  void _findPeer() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('尋找病友功能開發中')),
    );
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
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    _buildAiCard(),
                    const SizedBox(height: 24),

                    // ── 治療師區 ──
                    _buildSectionTitle(
                      '我的照護團隊',
                      actionLabel: '加入',
                      onAction: _addTherapist,
                    ),
                    const SizedBox(height: 12),
                    if (_therapists.isEmpty)
                      _buildEmpty('還沒有治療師', '點「加入」綁定你的治療師')
                    else
                      ..._therapists.map(_buildTherapistCard),

                    const SizedBox(height: 24),

                    // ── 病友區 ──
                    _buildSectionTitle(
                      '一起加油的夥伴',
                      actionLabel: '尋找病友',
                      onAction: _findPeer,
                    ),
                    const SizedBox(height: 12),
                    if (_peers.isEmpty)
                      _buildEmpty('還沒有夥伴', '找到同路人,一起走復健這條路')
                    else
                      ..._peers.map(_buildPeerCard),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 頁面標題 ──
  Widget _buildHeader() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '訊息',
            style: TextStyle(
              color: Color(0xFF1A1D2E),
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'AI、治療師、夥伴,陪你一起復健',
            style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ── AI 助手卡片 ──
  Widget _buildAiCard() {
    return GestureDetector(
      onTap: _openAiChat,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4A65FF), Color(0xFF7B5EA7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4A65FF).withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.auto_awesome, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'AI 復健助手',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '隨時在線',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '有任何訓練問題都可以問我',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                color: Colors.white.withValues(alpha: 0.8), size: 16),
          ],
        ),
      ),
    );
  }

  // ── 區塊標題 + 動作按鈕 ──
  Widget _buildSectionTitle(String title,
      {required String actionLabel, required VoidCallback onAction}) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF1A1D2E),
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: onAction,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF4A65FF).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add, color: Color(0xFF4A65FF), size: 16),
                const SizedBox(width: 4),
                Text(
                  actionLabel,
                  style: const TextStyle(
                    color: Color(0xFF4A65FF),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── 治療師卡片 ──
  Widget _buildTherapistCard(Therapist t) {
    return GestureDetector(
      onTap: () => _openTherapistChat(t),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: _cardDecoration(),
        child: Row(
          children: [
            _avatar(t.avatarText, online: t.online),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(t.name, style: _nameStyle()),
                      const SizedBox(width: 6),
                      _tag(t.title),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(t.lastMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _previewStyle()),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _trailing(t.lastTime, t.unread),
          ],
        ),
      ),
    );
  }

  // ── 病友卡片 ──
  Widget _buildPeerCard(Peer p) {
    return GestureDetector(
      onTap: () => _openPeerChat(p),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: _cardDecoration(),
        child: Row(
          children: [
            _avatar(p.avatarText, avatarColor: const Color(0xFF10B981)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(p.nickname, style: _nameStyle()),
                      const SizedBox(width: 6),
                      _tag('${p.condition}·第${p.week}週'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (p.trainedToday) ...[
                        const Icon(Icons.check_circle,
                            color: Color(0xFF10B981), size: 12),
                        const SizedBox(width: 3),
                        const Text('今天已完成',
                            style: TextStyle(
                                color: Color(0xFF10B981),
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(p.lastMessage,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _previewStyle()),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _trailing(p.lastTime, p.unread),
          ],
        ),
      ),
    );
  }

  // ── 共用小元件 ──
  Widget _avatar(String text,
      {bool online = false, Color avatarColor = const Color(0xFF4A65FF)}) {
    return Stack(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: avatarColor.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            text,
            style: TextStyle(
              color: avatarColor,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (online)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      ],
    );
  }

  Widget _tag(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F6FA),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  Widget _trailing(String time, int unread) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(time,
              style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11)),
          const SizedBox(height: 6),
          if (unread > 0)
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Color(0xFFEF4444),
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              child: Text('$unread',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
        ],
      );

  TextStyle _nameStyle() => const TextStyle(
        color: Color(0xFF1A1D2E),
        fontSize: 15,
        fontWeight: FontWeight.w700,
      );

  TextStyle _previewStyle() => const TextStyle(
        color: Color(0xFF9CA3AF),
        fontSize: 12,
      );

  BoxDecoration _cardDecoration() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      );

  Widget _buildEmpty(String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.group_outlined,
              size: 36, color: const Color(0xFF9CA3AF).withValues(alpha: 0.5)),
          const SizedBox(height: 10),
          Text(title,
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 14)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
        ],
      ),
    );
  }
}
