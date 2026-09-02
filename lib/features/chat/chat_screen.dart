import 'package:flutter/material.dart';
import 'dart:async'; // 🖥️ 電視投放新增
import 'chat_repository.dart';
import 'chat_conversation.dart';
import 'chat_storage.dart';
import 'user_context_builder.dart';

// 🖥️ 電視投放新增
import '../tv_cast/socket_client_service.dart';
import '../tv_cast/socket_server_service.dart';

enum ChatSender { me, therapist }

class ChatMessage {
  final String text;
  final ChatSender sender;
  final DateTime time;

  ChatMessage({required this.text, required this.sender, required this.time});

  Map<String, dynamic> toJson() => {
        'text': text,
        'sender': sender.name,
        'time': time.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        text: json['text'] as String,
        sender: ChatSender.values.firstWhere((e) => e.name == json['sender']),
        time: DateTime.parse(json['time'] as String),
      );
}

class ChatScreen extends StatefulWidget {
  final bool isDisplay; // 🖥️ 電視投放新增
  const ChatScreen({super.key, this.isDisplay = false});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _clientService = SocketClientService(); // 🖥️ 電視投放新增
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ChatRepository _chatRepository = ChatRepository();
  final UserContextBuilder _contextBuilder = UserContextBuilder();
  final ChatStorage _storage = ChatStorage();

  List<ChatConversation> _conversations = [];
  ChatConversation? _current;
  final Set<String> _typingConversationIds = {};
  bool _loaded = false;

  StreamSubscription? _socketSub; // 🖥️ 電視投放新增

  ChatMessage get _welcomeMessage => ChatMessage(
        text: '您好,我是您的 AI 復健治療師,有任何訓練上的問題都可以在這裡問我。',
        sender: ChatSender.therapist,
        time: DateTime.now(),
      );

  @override
  void initState() {
    super.initState();
    _loadConversations();

    // 🖥️ 電視投放新增:監聽同步指令
    final clientService = SocketClientService();
    final serverService = SocketServerService();
    if (clientService.isConnected) {
      _socketSub = clientService.messages.listen(_handleSyncMessage);
    } else if (serverService.isClientConnected) {
      _socketSub = serverService.messages.listen(_handleSyncMessage);
    }

    _inputController.addListener(_onInputChanged);
  }

  void _onInputChanged() {
    if (widget.isDisplay) return;
    _broadcastSync('INPUT', data: {'text': _inputController.text});
  }

  void _handleSyncMessage(Map<String, dynamic> msg) {
    if (!widget.isDisplay || !mounted) return;
    if (msg['type'] != 'CHAT_SYNC') return;

    final action = msg['action'];
    if (action == 'INPUT') {
      final text = msg['data']['text'];
      if (text != null && text != _inputController.text) {
        _inputController.text = text;
      }
    } else if (action == 'MESSAGE') {
      final messageJson = msg['data']['message'];
      if (messageJson != null && _current != null) {
        final message = ChatMessage.fromJson(messageJson);
        setState(() {
          _current = _current!.copyWith(
            messages: [..._current!.messages, message],
            updatedAt: DateTime.now(),
          );
        });
        _scrollToBottom();
      }
    }
  }

  void _broadcastSync(String action, {Map<String, dynamic>? data}) {
    if (widget.isDisplay) return;

    final msg = {
      'type': 'CHAT_SYNC',
      'action': action,
      'data': data ?? {},
    };

    if (_clientService.isConnected) {
      _clientService.sendCommand(msg);
    } else {
      final serverService = SocketServerService();
      if (serverService.isClientConnected) {
        serverService.sendMessage(msg);
      }
    }
  }

  @override
  void dispose() {
    _inputController.removeListener(_onInputChanged);
    _inputController.dispose();
    _scrollController.dispose();
    _socketSub?.cancel();
    super.dispose();
  }

  // ---------- 對話管理 ----------

  Future<void> _loadConversations() async {
    final all = await _storage.getAll();
    final currentId = await _storage.getCurrentId();

    ChatConversation? current;
    if (all.isNotEmpty) {
      current = all.firstWhere(
        (c) => c.id == currentId,
        orElse: () => all.first,
      );
    }

    // 沒有任何對話 → 建一個新的
    if (current == null) {
      current = _createBlankConversation();
      all.insert(0, current);
      await _storage.saveAll(all);
      await _storage.setCurrentId(current.id);
    }

    if (!mounted) return;
    setState(() {
      _conversations = all;
      _current = current;
      _loaded = true;
    });
    _scrollToBottom();
  }

  ChatConversation _createBlankConversation() {
    final now = DateTime.now();
    return ChatConversation(
      id: now.microsecondsSinceEpoch.toString(),
      title: ChatConversation.makeTitle(now),
      updatedAt: now,
      messages: [_welcomeMessage],
    );
  }

  Future<void> _startNewConversation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('開始新對話',
            style: TextStyle(
                color: Color(0xFF1A1D2E),
                fontSize: 16,
                fontWeight: FontWeight.w800)),
        content: const Text(
          '目前的對話會保留在對話記錄裡,\n之後可以從左側選單回去繼續。',
          style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: Color(0xFF6B7280))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('開始新對話', style: TextStyle(color: Color(0xFF4A65FF))),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    final newConv = _createBlankConversation();
    final all = [newConv, ..._conversations];
    await _storage.saveAll(all);
    await _storage.setCurrentId(newConv.id);
    if (!mounted) return;
    setState(() {
      _conversations = all;
      _current = newConv;
    });
    _scrollToBottom();
  }

  Future<void> _startNewConversationDirectly() async {
    final newConv = _createBlankConversation();
    final all = [newConv, ..._conversations];
    await _storage.saveAll(all);
    await _storage.setCurrentId(newConv.id);
    if (!mounted) return;
    setState(() {
      _conversations = all;
      _current = newConv;
    });
    Navigator.of(context).pop(); // 關 Drawer
    _scrollToBottom();
  }

  Future<void> _switchTo(ChatConversation conv) async {
    await _storage.setCurrentId(conv.id);
    if (!mounted) return;
    setState(() => _current = conv);
    Navigator.of(context).pop(); // 關 Drawer
    _scrollToBottom();
  }

  Future<void> _deleteConversation(String id) async {
    await _storage.delete(id);
    final remaining = _conversations.where((c) => c.id != id).toList();

    ChatConversation next;
    if (remaining.isEmpty) {
      next = _createBlankConversation();
      remaining.add(next);
      await _storage.saveAll(remaining);
    } else if (_current?.id == id) {
      next = remaining.first;
    } else {
      next = _current!;
    }

    await _storage.setCurrentId(next.id);
    if (!mounted) return;
    setState(() {
      _conversations = remaining;
      _current = next;
    });
  }

  Future<void> _persistCurrent() async {
    if (_current == null) return;
    await _storage.upsert(_current!);
    // 更新記憶體裡的列表,讓 Drawer 也同步
    final idx = _conversations.indexWhere((c) => c.id == _current!.id);
    if (idx >= 0) _conversations[idx] = _current!;
  }

  // ---------- 送訊息 ----------

  void _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _current == null) return;

    // ✅ 鎖定這則訊息屬於哪個對話 — 之後 _current 換掉也不影響
    final targetId = _current!.id;

    final userMsg =
        ChatMessage(text: text, sender: ChatSender.me, time: DateTime.now());

    _broadcastSync('MESSAGE', data: {'message': userMsg.toJson()});

    setState(() {
      _current = _current!.copyWith(
        messages: [..._current!.messages, userMsg],
        updatedAt: DateTime.now(),
      );
      _typingConversationIds.add(targetId);
    });
    _inputController.clear();
    await _persistCurrent();
    _scrollToBottom();

    final userContext = await _contextBuilder.build();
    final reply = await _chatRepository.sendMessage(
      userMessage: text,
      context: userContext,
    );

    if (!mounted) return;

    final replyMsg = ChatMessage(
        text: reply, sender: ChatSender.therapist, time: DateTime.now());

    _broadcastSync('MESSAGE', data: {'message': replyMsg.toJson()});

    // ✅ 把回覆寫回「當初送訊息的那個對話」,不是現在的 _current
    final targetIdx = _conversations.indexWhere((c) => c.id == targetId);
    if (targetIdx < 0) {
      setState(() => _typingConversationIds.remove(targetId));
      return;
    }

    final updated = _conversations[targetIdx].copyWith(
      messages: [..._conversations[targetIdx].messages, replyMsg],
      updatedAt: DateTime.now(),
    );
    _conversations[targetIdx] = updated;
    await _storage.upsert(updated);

    setState(() {
      if (_current?.id == targetId) {
        _current = updated;
      }
      _typingConversationIds.remove(targetId);
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ---------- Build ----------

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
        drawer: _buildDrawer(),
        body: SafeArea(
          child: !_loaded || _current == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    _buildTopBar(),
                    Expanded(child: _buildMessageList()),
                    _buildInputBar(),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        children: [
          Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu, color: Color(0xFF374151)),
              onPressed: () => Scaffold.of(ctx).openDrawer(),
              tooltip: '對話列表',
            ),
          ),
          const Expanded(
            child: Text(
              'AI 助手',
              style: TextStyle(
                color: Color(0xFF1A1D2E),
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            onPressed: _startNewConversation,
            icon: const Icon(
              Icons.add_comment_outlined,
              color: Color(0xFF4A65FF),
            ),
            tooltip: '新對話',
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '對話記錄',
                      style: TextStyle(
                        color: Color(0xFF1A1D2E),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _startNewConversationDirectly,
                    icon: const Icon(Icons.add_circle_outline,
                        color: Color(0xFF4A65FF)),
                    tooltip: '新對話',
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFDDE0F0)),
            Expanded(
              child: _conversations.isEmpty
                  ? const Center(
                      child: Text('尚無對話',
                          style: TextStyle(
                              color: Color(0xFF9CA3AF), fontSize: 13)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: _conversations.length,
                      itemBuilder: (_, i) {
                        final c = _conversations[i];
                        final isActive = c.id == _current?.id;
                        return Dismissible(
                          key: ValueKey(c.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            color: const Color(0xFFEF4444),
                            child: const Icon(Icons.delete_outline,
                                color: Colors.white, size: 22),
                          ),
                          onDismissed: (_) => _deleteConversation(c.id),
                          child: Container(
                            color: isActive
                                ? const Color(0xFF4A65FF)
                                    .withValues(alpha: 0.08)
                                : Colors.transparent,
                            child: ListTile(
                              title: Text(
                                c.title,
                                style: TextStyle(
                                  color: isActive
                                      ? const Color(0xFF4A65FF)
                                      : const Color(0xFF1A1D2E),
                                  fontSize: 14,
                                  fontWeight: isActive
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                              subtitle: Text(
                                c.messages.isEmpty
                                    ? '(空對話)'
                                    : c.messages.last.text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Color(0xFF9CA3AF), fontSize: 11),
                              ),
                              onTap: () => _switchTo(c),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Text(
                '往左滑刪除對話',
                style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    final msgs = _current?.messages ?? [];
    final isCurrentTyping =
        _current != null && _typingConversationIds.contains(_current!.id);
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: msgs.length + (isCurrentTyping ? 1 : 0),
      itemBuilder: (_, i) {
        if (isCurrentTyping && i == msgs.length) {
          return _buildTypingBubble();
        }
        return _buildBubble(msgs[i]);
      },
    );
  }

  Widget _buildTypingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
          border: Border.all(color: const Color(0xFFDDE0F0)),
        ),
        child: const Text(
          '思考中...',
          style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildBubble(ChatMessage msg) {
    final isMe = msg.sender == ChatSender.me;
    final timeText =
        '${msg.time.hour.toString().padLeft(2, '0')}:${msg.time.minute.toString().padLeft(2, '0')}';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? const Color(0xFF4A65FF) : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
                border:
                    isMe ? null : Border.all(color: const Color(0xFFDDE0F0)),
              ),
              child: Text(
                msg.text,
                style: TextStyle(
                  color: isMe ? Colors.white : const Color(0xFF1A1D2E),
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              timeText,
              style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F6FA),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFDDE0F0)),
                ),
                child: TextField(
                  controller: _inputController,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: '輸入訊息...',
                    hintStyle:
                        TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                  style:
                      const TextStyle(fontSize: 14, color: Color(0xFF1A1D2E)),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sendMessage,
              child: Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: Color(0xFF4A65FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_upward_rounded,
                    color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
