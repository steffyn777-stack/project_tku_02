// lib/features/home/home_screen.dart
//
// 首頁(新版)— 儀表板風格 + 底部 5 tab
// 「今日準確度」「連續達成」接 HistoryService 真實資料
//
// 🖥️ 電視投放修正:_handleRemoteCommand 原本只處理全身動作,
//    手部動作被直接忽略(return),導致電視端收到手部訓練指令時毫無反應。
//    現在改成:全身動作 → BodyTrainingScreen(isDisplay:true)
//              手部動作 → TrainingScreen(isDisplay:true)

import 'package:flutter/material.dart';

import '../../models/training_action.dart';
import '../../services/history_service.dart';
import '../history/history_screen.dart';
import '../training/action_list_screen.dart';
import '../demo/demo_library_screen.dart'; // ← 新增
import '../plan/plan_screen.dart';
import '../analysis/standard_analysis_screen.dart';
import '../chat/chat_home_screen.dart';
import '../chat/chat_screen.dart';
import '../account/profile_screen.dart';
import '../stats/stats_screen.dart';

import '../notification/notification_screen.dart';
import '../notification/notification_settings_screen.dart';
import '../notification/notification_service.dart';

import '../demo/bone_viewer_screen.dart';
import '../body_test/body_test_screen.dart';

import 'package:provider/provider.dart';

import '../tv_cast/connection_status_screen.dart';
import '../tv_cast/phone_connection_screen.dart';

// 🖥️ 電視投放串接新增
import 'dart:async';
import '../tv_cast/webrtc_service.dart';
import '../tv_cast/socket_server_service.dart';
import '../tv_cast/socket_client_service.dart';
import '../rehab/body_training_screen.dart';
import '../rehab/training_screen.dart'; // 🖥️ 電視投放新增:手部動作顯示端要用
import '../../actions/standing_knee_raise_action.dart';
import '../../actions/draw_circle_action.dart';
import '../../actions/reach_action.dart';
import '../../actions/raise_both_arms_action.dart';
import '../../actions/elbow_forward_action.dart';
import '../../actions/sit_to_stand_action.dart';
import '../../actions/lateral_step_action.dart';
import '../../actions/body_rehab_action.dart';

// ═══════════════════════════════════════════════════════════
//  外殼:管理底部 tab 切換,IndexedStack 讓導航列常駐不消失
// ═══════════════════════════════════════════════════════════
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  // 🖥️ 電視投放新增
  final _serverService = SocketServerService();
  final _clientService = SocketClientService();
  final _rtcService = WebRtcService();
  StreamSubscription? _serverSub;
  StreamSubscription? _clientSub;

  @override
  void initState() {
    super.initState();
    // WebRTC 信令透過 socket 轉發給對方
    _rtcService.onSignalingMessage = (signal) {
      final msg = {'type': 'RTC_SIGNAL', 'signal': signal};
      if (_clientService.isConnected) {
        _clientService.sendCommand(msg);
      } else if (_serverService.isClientConnected) {
        _serverService.sendMessage(msg);
      }
    };
    // 電視端:監聽手機傳來的指令
    _serverSub = _serverService.messages.listen(_handleRemoteCommand);
    _clientSub = _clientService.messages.listen(_handleRemoteCommand);
  }

  void _onTabTapped(int index) {
    setState(() => _currentIndex = index);

    // 🖥️ 電視投放新增:同步導航切換
    final msg = {'type': 'NAVIGATE_TO_TAB', 'index': index};
    if (_clientService.isConnected) {
      _clientService.sendCommand(msg);
    } else if (_serverService.isClientConnected) {
      _serverService.sendMessage(msg);
    }
  }

  void _openActionListSync() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const ActionListScreen(isDisplay: true),
    ));
  }

  void _openHistorySync() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const HistoryScreen(),
    ));
  }

  void _openDemoLibrarySync() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const DemoLibraryScreen(),
    ));
  }

  void _openStandardAnalysisSync() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const StandardAnalysisScreen(),
    ));
  }

  void _openNotificationSync() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const NotificationScreen(),
    ));
  }

  void _openNotificationSettingsSync() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const NotificationSettingsScreen(),
    ));
  }

  void _openChatAiSync() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const ChatScreen(isDisplay: true),
    ));
  }

  void _openBoneViewerSync() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const BoneViewerScreen(),
    ));
  }

  void _openBodyTestSync() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const BodyTestScreen(),
    ));
  }

  @override
  void dispose() {
    _serverSub?.cancel();
    _clientSub?.cancel();
    super.dispose();
  }

  // 🖥️ 電視端:收到 START_TRAINING → 開對應的顯示端訓練畫面
  void _handleRemoteCommand(Map<String, dynamic> msg) {
    if (!mounted) return;

    final type = msg['type'];

    if (type == 'NAVIGATE_TO_TAB') {
      final index = msg['index'] as int?;
      if (index != null && index >= 0 && index < _pages.length) {
        setState(() => _currentIndex = index);
      }
      return;
    }

    if (type == 'OPEN_SCREEN') {
      final screen = msg['screen'] as String?;
      if (screen == 'ACTION_LIST') {
        _openActionListSync();
      } else if (screen == 'HISTORY') {
        _openHistorySync();
      } else if (screen == 'DEMO_LIBRARY') {
        _openDemoLibrarySync();
      } else if (screen == 'STANDARD_ANALYSIS') {
        _openStandardAnalysisSync();
      } else if (screen == 'NOTIFICATION') {
        _openNotificationSync();
      } else if (screen == 'NOTIFICATION_SETTINGS') {
        _openNotificationSettingsSync();
      } else if (screen == 'CHAT_AI') {
        _openChatAiSync();
      } else if (screen == 'BONE_VIEWER') {
        _openBoneViewerSync();
      } else if (screen == 'BODY_TEST') {
        _openBodyTestSync();
      }
      return;
    }

    if (type == 'POP_SCREEN') {
      Navigator.of(context).pop();
      return;
    }

    if (type != 'START_TRAINING') return;

    final actionName = msg['actionName'] as String?;
    final levelName = msg['difficultyLevel'] as String?;
    if (actionName == null) return;

    final action = kTrainingActions.firstWhere(
      (a) => a.name == actionName,
      orElse: () => kTrainingActions.first,
    );
    final difficulty = action.difficulties.firstWhere(
      (d) => d.level.name == levelName,
      orElse: () => action.difficulties.first,
    );

    if (_isBodyAction(action.type)) {
      // 🖥️ 全身動作 → 電視端開全身骨架顯示畫面
      _rtcService.init(isController: false);

      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BodyTrainingScreen(
          action: _createBodyRehabAction(action, difficulty),
          trainingActionMeta: action,
          difficultyMeta: difficulty,
          isDisplay: true, // ← 電視顯示端
        ),
      ));
    } else {
      // 🖥️ 手部動作 → 電視端開手部骨架顯示畫面
      // (修正前這裡是 return,手部動作被直接忽略)
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TrainingScreen(
          action: action,
          difficulty: difficulty,
          isDisplay: true, // ← 電視顯示端
        ),
      ));
    }
  }

  bool _isBodyAction(ActionType type) {
    return type == ActionType.wipeBody ||
        type == ActionType.drawCircle ||
        type == ActionType.reach ||
        type == ActionType.raiseBothArms ||
        type == ActionType.elbowForward ||
        type == ActionType.sitToStand ||
        type == ActionType.lateralStep;
  }

  BodyRehabAction _createBodyRehabAction(
      TrainingAction act, DifficultyOption diff) {
    final d = _mapDifficulty(diff.level);
    switch (act.type) {
      case ActionType.wipeBody:
        return StandingKneeRaiseAction(difficulty: d);
      case ActionType.drawCircle:
        return DrawCircleAction(difficulty: d);
      case ActionType.reach:
        return ReachAction(difficulty: d);
      case ActionType.raiseBothArms:
        return RaiseBothArmsAction(difficulty: d);
      case ActionType.elbowForward:
        return ElbowForwardAction(difficulty: d);
      case ActionType.sitToStand:
        return SitToStandAction(difficulty: d);
      case ActionType.lateralStep:
        return LateralStepAction(difficulty: d);
      default:
        return StandingKneeRaiseAction(difficulty: d);
    }
  }

  RehabDifficulty _mapDifficulty(DifficultyLevel level) {
    switch (level) {
      case DifficultyLevel.level1:
        return RehabDifficulty.easy;
      case DifficultyLevel.level2:
        return RehabDifficulty.medium;
      case DifficultyLevel.level3:
        return RehabDifficulty.hard;
    }
  }

  late final List<Widget> _pages = [
    const _HomeContent(),
    const PlanScreen(),
    const ChatHomeScreen(),
    const StatsScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              _NavItem(
                label: '首頁',
                isActive: _currentIndex == 0,
                onTap: () => _onTabTapped(0),
              ),
              _NavItem(
                label: '數據',
                isActive: _currentIndex == 3,
                onTap: () => _onTabTapped(3),
              ),
              _NavItem(
                label: '計畫',
                isActive: _currentIndex == 1,
                onTap: () => _onTabTapped(1),
              ),
              _NavItem(
                label: '聊天',
                isActive: _currentIndex == 2,
                onTap: () => _onTabTapped(2),
              ),
              _NavItem(
                label: '個人',
                isActive: _currentIndex == 4,
                onTap: () => _onTabTapped(4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  首頁內容:原本 HomeScreen 的內容,搬進這個獨立 widget
// ═══════════════════════════════════════════════════════════
class _HomeContent extends StatefulWidget {
  const _HomeContent();

  @override
  State<_HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<_HomeContent>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  // ─── 資料層(未來換資料庫只改 HistoryService 內部即可)
  final HistoryService _historyService = HistoryService();

  // ─── 顯示用狀態
  String _accuracyText = '-- %';
  String _accuracyFooter = '尚未開始訓練';
  String _streakText = '0 天';

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    _loadStats();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  bool _hasHistory = false; // ✅ 新增
  String _lastTrainingText = ''; // ✅ 新增
  int _unreadCount = 0; // ✅ 新增(未讀通知數)

  // ═══ 載入統計 ═══════════════════════════════════════════════
  // 未來接資料庫時,只動 HistoryService 內部即可,本方法不變
  Future<void> _loadStats() async {
    // 每次進首頁時,如果通知開著就重新排下一次提醒(繞過 MIUI 殺鎖)
    await NotificationService().refreshDailyReminderIfEnabled();
    final records = await _historyService.getHistory();
    final unread = await NotificationService().getUnreadCount(); // ✅ 新增
    if (!mounted) return;

    final acc = _calcTodayAccuracy(records);
    final streak = _calcStreak(records);

    setState(() {
      _accuracyText = acc.text;
      _accuracyFooter = acc.footer;
      _streakText = '$streak 天';
      _unreadCount = unread; // ✅ 新增

      if (records.isNotEmpty) {
        _hasHistory = true;
        _lastTrainingText = _formatLastTraining(records.last);
      } else {
        _hasHistory = false;
        _lastTrainingText = '';
      }
    });
  }

  // ✅ 新增:組出「動作名稱 · 難度 · 次數」文字
  String _formatLastTraining(TrainingRecord r) {
    final action = kTrainingActions.firstWhere(
      (a) => a.name == r.actionName,
      orElse: () => kTrainingActions.first,
    );
    final idx = r.difficulty - 1;
    final label = (idx >= 0 && idx < action.difficulties.length)
        ? action.difficulties[idx].label
        : 'Lv.${r.difficulty}';
    return '${r.actionName} · $label · ${r.targetReps}下';
  }

  // 今日準確度:取今天所有 record,(10 - 平均 mistake) / 10 * 100
  ({String text, String footer}) _calcTodayAccuracy(
      List<TrainingRecord> records) {
    final todayPrefix = _todayPrefix();
    final today =
        records.where((r) => r.timestamp.startsWith(todayPrefix)).toList();

    if (today.isEmpty) {
      return (text: '-- %', footer: '尚未開始訓練');
    }

    final avgMistakes =
        today.map((r) => r.mistakeLogs.length).reduce((a, b) => a + b) /
            today.length;
    final acc = ((10 - avgMistakes) / 10 * 100).clamp(0, 100).round();

    return (text: '$acc %', footer: '今日完成 ${today.length} 組訓練');
  }

  // 連續達成:從今天往回算,每天至少 1 筆紀錄就 +1
  int _calcStreak(List<TrainingRecord> records) {
    if (records.isEmpty) return 0;

    final days = records.map((r) => r.timestamp.substring(0, 10)).toSet();

    final now = DateTime.now();
    final todayStr = _formatDate(now);
    final yesterdayStr = _formatDate(now.subtract(const Duration(days: 1)));

    // 決定往回算的起始日
    DateTime anchor;
    if (days.contains(todayStr)) {
      anchor = now; // 今天已經練過,從今天開始算
    } else if (days.contains(yesterdayStr)) {
      anchor = now.subtract(const Duration(days: 1)); // 今天還沒練,先用昨天當基準,天數不會歸零
    } else {
      return 0; // 昨天也沒練 → 斷了超過一天,歸零
    }

    int streak = 0;
    DateTime check = anchor;
    while (days.contains(_formatDate(check))) {
      streak++;
      check = check.subtract(const Duration(days: 1));
    }
    return streak;
  }

  String _todayPrefix() => _formatDate(DateTime.now());

  String _formatDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // ─── 操作:跳「選動作清單」頁,回來後重整統計 ─────────
  void _openActionList() async {
    _broadcastOpenScreen('ACTION_LIST');
    await Navigator.of(context).push(PageRouteBuilder(
      pageBuilder: (_, anim, __) => const ActionListScreen(),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
      transitionDuration: const Duration(milliseconds: 400),
    ));
    if (mounted) _loadStats(); // 訓練回來重算
  }

  // ─── 操作:跳歷史紀錄頁,回來後重整統計(可能清過紀錄)
  void _openHistory() async {
    _broadcastOpenScreen('HISTORY');
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HistoryScreen()),
    );
    if (mounted) _loadStats();
  }

  // ← 新增：跳動作示範庫
  void _openDemoLibrary() {
    _broadcastOpenScreen('DEMO_LIBRARY');
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DemoLibraryScreen()),
    );
  }

  // ← 新增：跳動作標準分析
  void _openStandardAnalysis() {
    _broadcastOpenScreen('STANDARD_ANALYSIS');
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const StandardAnalysisScreen()),
    );
  }

  void _broadcastOpenScreen(String screenName) {
    final clientService = SocketClientService();
    final serverService = SocketServerService();
    final msg = {'type': 'OPEN_SCREEN', 'screen': screenName};
    if (clientService.isConnected) {
      clientService.sendCommand(msg);
    } else if (serverService.isClientConnected) {
      serverService.sendMessage(msg);
    }
  }

  // 📺 投放到電視:底部彈窗,選這台當電視(顯示端)還是當手機(遙控端)
  void _showCastSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDDE0F0),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '電視投放',
                  style: TextStyle(
                    color: Color(0xFF1A1D2E),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '選擇這台裝置的角色',
                  style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                ),
                const SizedBox(height: 20),
                _buildCastOption(
                  emoji: '📺',
                  title: '這台當電視',
                  subtitle: '接收手機傳來的訓練畫面',
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _onCastAsTv();
                  },
                ),
                const SizedBox(height: 12),
                _buildCastOption(
                  emoji: '📱',
                  title: '這台當手機',
                  subtitle: '遙控電視、傳送訓練畫面',
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _onCastAsPhone();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCastOption({
    required String emoji,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F6FA),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFDDE0F0)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 22)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF1A1D2E),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style:
                        const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                color: Color(0xFF9CA3AF), size: 14),
          ],
        ),
      ),
    );
  }

  // 這台當電視:進 server 畫面,顯示自己的 IP 等手機連進來
  void _onCastAsTv() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ConnectionStatusScreen()),
    );
  }

  // 這台當手機:進 client 畫面,輸入電視 IP 連過去
  void _onCastAsPhone() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PhoneConnectionScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 訂閱 HistoryService,值變了會 rebuild
    context.watch<HistoryService>();
    // rebuild 就重新載入統計(延到下一幀,避免 build 時 setState)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadStats();
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTopGreeting(),
                const SizedBox(height: 20),
                _buildStatsRow(),
                const SizedBox(height: 28),
                _buildSectionTitle('今日復健計畫'),
                const SizedBox(height: 12),
                _buildMainTrainingCard(),
                const SizedBox(height: 28),
                _buildSectionTitle('功能捷徑'),
                const SizedBox(height: 12),
                _buildShortcutsRow(),
                const SizedBox(height: 12),
                _buildStandardAnalysisCard(), // ← 新增
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── 上方:歡迎詞 + 鈴鐺 ────────────────────────────────
  Widget _buildTopGreeting() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '早安,保持活力 ',
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 13,
                    ),
                  ),
                  Text('💪', style: TextStyle(fontSize: 14)),
                ],
              ),
              SizedBox(height: 4),
              Text(
                '使用者',
                style: TextStyle(
                  color: Color(0xFF1A1D2E),
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
              SizedBox(height: 2),
              Text(
                '帳號未來綁定',
                style: TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        // 📺 投放到電視:圓形按鈕,放在通知鈴鐺左邊
        GestureDetector(
          onTap: _showCastSheet,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.cast, color: Color(0xFF374151), size: 22),
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: () async {
            // ✅ 改
            _broadcastOpenScreen('NOTIFICATION');
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const NotificationScreen(),
              ),
            );
            if (mounted) _loadStats(); // 回來後重算未讀數
          },
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.notifications_outlined,
                    color: Color(0xFF374151), size: 22),
                if (_unreadCount > 0) // ✅ 改:加條件
                  Positioned(
                    top: 10,
                    right: 12,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── 數據卡 × 2 ──────────────────────────────────────
  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            // ✅ 新增
            onTap: _openHistory, // ✅ 新增:沿用既有的 _openHistory,邏輯完全沒動
            child: _StatCard(
              title: '今日準確度',
              value: _accuracyText,
              footer: _accuracyFooter,
              isPrimary: true,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            title: '連續達成 🔥',
            value: _streakText,
            footer: _streakText == '0 天' ? '今天開始吧!' : '保持下去!',
            isPrimary: false,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF1A1D2E),
        fontSize: 17,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _buildMainTrainingCard() {
    return GestureDetector(
      onTap: _openActionList, // 互動不變
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F6FA),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                '核心運算',
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ✅ 依有沒有歷史紀錄切換標題
            Text(
              _hasHistory ? '最近訓練' : '自由訓練',
              style: const TextStyle(
                color: Color(0xFF1A1D2E),
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),

            // ✅ 依有沒有歷史紀錄切換副標題
            Text(
              _hasHistory ? _lastTrainingText : '選擇動作 · 多種難度',
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1D2E),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '開始訓練',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 22),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShortcutsRow() {
    return Row(
      children: [
        Expanded(
          child: _ShortcutCard(
            label: '動作示範庫',
            iconBg: const Color(0xFFD1FAE5),
            onTap: _openDemoLibrary, // ← 改這裡
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ShortcutCard(
            label: '歷史紀錄',
            iconBg: const Color(0xFFFFE4D6),
            onTap: _openHistory,
          ),
        ),
      ],
    );
  }

  Widget _buildStandardAnalysisCard() {
    return GestureDetector(
      onTap: _openStandardAnalysis,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFE0E7FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.insights,
                  color: Color(0xFF4A65FF), size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '動作標準分析',
                    style: TextStyle(
                      color: Color(0xFF374151),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    '從治療師示範影片建立動作標準',
                    style: TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                color: Color(0xFF9CA3AF), size: 14),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════ 子元件 ═════════════════════════

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String footer;
  final bool isPrimary;

  const _StatCard({
    required this.title,
    required this.value,
    required this.footer,
    required this.isPrimary,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isPrimary
        ? const LinearGradient(
            colors: [Color(0xFF4A65FF), Color(0xFF7B5EA7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : null;
    final textColor = isPrimary ? Colors.white : const Color(0xFF1A1D2E);
    final subColor = isPrimary
        ? Colors.white.withValues(alpha: 0.85)
        : const Color(0xFF6B7280);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: bg,
        color: isPrimary ? null : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: subColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              color: textColor,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            footer,
            style: TextStyle(color: subColor, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _ShortcutCard extends StatelessWidget {
  final String label;
  final Color iconBg;
  final VoidCallback onTap;

  const _ShortcutCard({
    required this.label,
    required this.iconBg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: iconBg,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF374151),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? const Color(0xFF4A65FF) : const Color(0xFF9CA3AF);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
