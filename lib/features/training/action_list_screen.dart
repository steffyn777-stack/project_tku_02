// lib/features/training/action_list_screen.dart
//
// 動作清單頁 — 原本是 home_screen 的內容
// 從新首頁的「開始訓練」大卡片點下去進來
//
// ✅ 新增:目標次數輸入框,使用者可自訂訓練次數
// ✅ 修改:選擇難度等級 / 目標次數 / 開始訓練 / 查看訓練紀錄 改為固定在畫面底部(已縮小留白)

import 'package:flutter/material.dart';
import 'dart:async'; // 🖥️ 電視投放新增
import '../../models/training_action.dart';
import '../rehab/training_screen.dart';
import '../body_test/body_test_screen.dart';
import '../history/history_screen.dart';
import '../rehab/body_training_screen.dart';
import '../../actions/standing_knee_raise_action.dart';
import '../../actions/draw_circle_action.dart';
import '../../actions/reach_action.dart';
import '../../actions/raise_both_arms_action.dart';
import '../../actions/elbow_forward_action.dart';
import '../../actions/sit_to_stand_action.dart';
import '../../actions/lateral_step_action.dart';

import '../../actions/body_rehab_action.dart';

import 'training_preview_screen.dart';

// 🖥️ 電視投放新增
import '../tv_cast/socket_client_service.dart';
import '../tv_cast/socket_server_service.dart';
import '../tv_cast/remote_controller_screen.dart';

// 手部動作清單
final _handActions = [
  ActionType.turnPalm,
  ActionType.sidePinch,
  ActionType.wristExtension,
  ActionType.wristSideBend,
];
// 全身動作清單
final _bodyActions = [
  ActionType.wipeBody,
  ActionType.drawCircle,
  ActionType.reach,
  ActionType.raiseBothArms,
  ActionType.elbowForward,
  ActionType.sitToStand,
  ActionType.lateralStep,
  ActionType.bodyTest,
];

class ActionListScreen extends StatefulWidget {
  final bool isDisplay; // 🖥️ 電視投放新增
  const ActionListScreen({super.key, this.isDisplay = false});

  @override
  State<ActionListScreen> createState() => _ActionListScreenState();
}

class _ActionListScreenState extends State<ActionListScreen>
    with TickerProviderStateMixin {
  TrainingAction? _selectedAction;
  DifficultyOption? _selectedDifficulty;

  bool _handExpanded = false;
  bool _bodyExpanded = false;

  // 🖥️ 電視投放新增
  final _clientService = SocketClientService();

  // ── 新增:目標次數輸入框控制器 ──
  final TextEditingController _repsController =
      TextEditingController(text: '10');
  bool _autoLevelUp = true; // 🆕 true=自動升級難度, false=達標後跳出詢問

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  StreamSubscription? _socketSub; // 🖥️ 電視投放新增

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    // 🖥️ 電視投放新增:監聽同步指令
    final clientService = SocketClientService();
    final serverService = SocketServerService();
    if (clientService.isConnected) {
      _socketSub = clientService.messages.listen(_handleSyncMessage);
    } else if (serverService.isClientConnected) {
      _socketSub = serverService.messages.listen(_handleSyncMessage);
    }

    _repsController.addListener(_onRepsChanged);
  }

  void _onRepsChanged() {
    _broadcastSync();
  }

  void _handleSyncMessage(Map<String, dynamic> msg) {
    if (!widget.isDisplay || !mounted) return;
    if (msg['type'] != 'ACTION_LIST_SYNC') return;

    setState(() {
      final actionType = msg['selectedActionType'];
      if (actionType != null) {
        _selectedAction = kTrainingActions.firstWhere(
          (a) => a.type.name == actionType,
          orElse: () => kTrainingActions.first,
        );
      } else {
        _selectedAction = null;
      }

      final levelName = msg['selectedDifficultyLevel'];
      if (_selectedAction != null && levelName != null) {
        _selectedDifficulty = _selectedAction!.difficulties.firstWhere(
          (d) => d.level.name == levelName,
          orElse: () => _selectedAction!.difficulties.first,
        );
      } else {
        _selectedDifficulty = null;
      }

      _handExpanded = msg['handExpanded'] ?? _handExpanded;
      _bodyExpanded = msg['bodyExpanded'] ?? _bodyExpanded;
      _autoLevelUp = msg['autoLevelUp'] ?? _autoLevelUp;

      final reps = msg['reps'];
      if (reps != null && reps != _repsController.text) {
        _repsController.text = reps;
      }
    });
  }

  void _broadcastSync() {
    if (widget.isDisplay) return;

    final msg = {
      'type': 'ACTION_LIST_SYNC',
      'selectedActionType': _selectedAction?.type.name,
      'selectedDifficultyLevel': _selectedDifficulty?.level.name,
      'handExpanded': _handExpanded,
      'bodyExpanded': _bodyExpanded,
      'autoLevelUp': _autoLevelUp,
      'reps': _repsController.text,
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
    _fadeCtrl.dispose();
    _repsController.removeListener(_onRepsChanged);
    _repsController.dispose(); // ← 新增
    _socketSub?.cancel();
    super.dispose();
  }

  void _selectAction(TrainingAction action) {
    if (action.type == ActionType.bodyTest) {
      // 🖥️ 電視投放新增:同步跳轉指令
      if (_clientService.isConnected) {
        _clientService
            .sendCommand({'type': 'OPEN_SCREEN', 'screen': 'BODY_TEST'});
      }
      Navigator.of(context).push(PageRouteBuilder(
        pageBuilder: (_, anim, __) => const BodyTestScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ));
      return;
    }
    setState(() {
      // 再點同一張卡 → 取消選中
      if (_selectedAction?.type == action.type) {
        _selectedAction = null;
        _selectedDifficulty = null;
      } else {
        _selectedAction = action;
        _selectedDifficulty = action.difficulties.first;
        _repsController.text = '${_selectedDifficulty!.targetReps}'; // ← 新增
      }
    });
    _broadcastSync();
  }

  void _startTraining({TrainingAction? action, DifficultyOption? difficulty}) {
    final act = action ?? _selectedAction;
    var diff = difficulty ?? _selectedDifficulty;
    if (act == null || diff == null) return;

    final customReps = int.tryParse(_repsController.text);
    if (customReps != null && customReps > 0) {
      diff = diff.copyWithReps(customReps);
    }

    // 🖥️ 電視投放新增:偵測是否連線中
    if (_clientService.isConnected && _isBodyAction(act.type)) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RemoteControllerScreen(
          action: act,
          difficulty: diff!,
          rehabAction: _createBodyRehabAction(act, diff),
        ),
      ));
      return;
    }

    Widget screen;
    if (act.type == ActionType.wipeBody) {
      screen = BodyTrainingScreen(
        action: StandingKneeRaiseAction(
          difficulty: _mapDifficulty(diff.level),
          targetCount: diff.targetReps,
        ),
        trainingActionMeta: act,
        difficultyMeta: diff,
        autoLevelUp: _autoLevelUp,
      );
    } else if (act.type == ActionType.drawCircle) {
      screen = BodyTrainingScreen(
        action: DrawCircleAction(
          difficulty: _mapDifficulty(diff.level),
          targetCount: diff.targetReps,
        ),
        trainingActionMeta: act,
        difficultyMeta: diff,
        autoLevelUp: _autoLevelUp,
      );
    } else if (act.type == ActionType.reach) {
      screen = BodyTrainingScreen(
        action: ReachAction(
          difficulty: _mapDifficulty(diff.level),
          targetCount: diff.targetReps,
        ),
        trainingActionMeta: act,
        difficultyMeta: diff,
        autoLevelUp: _autoLevelUp,
      );
    } else if (act.type == ActionType.raiseBothArms) {
      screen = BodyTrainingScreen(
        action: RaiseBothArmsAction(
          difficulty: _mapDifficulty(diff.level),
          targetCount: diff.targetReps,
        ),
        trainingActionMeta: act,
        difficultyMeta: diff,
        autoLevelUp: _autoLevelUp,
      );
    } else if (act.type == ActionType.elbowForward) {
      screen = BodyTrainingScreen(
        action: ElbowForwardAction(
          difficulty: _mapDifficulty(diff.level),
          targetCount: diff.targetReps,
        ),
        trainingActionMeta: act,
        difficultyMeta: diff,
        autoLevelUp: _autoLevelUp,
      );
    } else if (act.type == ActionType.sitToStand) {
      screen = BodyTrainingScreen(
        action: SitToStandAction(
          difficulty: _mapDifficulty(diff.level),
          targetCount: diff.targetReps,
        ),
        trainingActionMeta: act,
        difficultyMeta: diff,
        autoLevelUp: _autoLevelUp,
      );
    } else if (act.type == ActionType.lateralStep) {
      screen = BodyTrainingScreen(
        action: LateralStepAction(
          difficulty: _mapDifficulty(diff.level),
          targetCount: diff.targetReps,
        ),
        trainingActionMeta: act,
        difficultyMeta: diff,
        autoLevelUp: _autoLevelUp,
      );
    } else {
      screen = TrainingScreen(
        action: act,
        difficulty: diff,
        autoLevelUp: _autoLevelUp, // 🆕
      );
    }

    // 有 3D 示範的動作 → 先進示範頁;沒有的 → 直接進訓練
    final Widget destination = hasDemo3D(act.type)
        ? TrainingPreviewScreen(
            actionType: act.type,
            actionName: act.name,
            targetScreen: screen,
            difficultyLabel: diff.label, // ← 新增
            targetReps: diff.targetReps, // ← 新增
            description: act.description, // ← 新增
          )
        : screen;

    Navigator.of(context).push(PageRouteBuilder(
      pageBuilder: (_, anim, __) => destination,
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
      transitionDuration: const Duration(milliseconds: 400),
    ));
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
          backgroundColor: const Color(0xFFFFFFFF),
          body: FadeTransition(
            opacity: _fadeAnim,
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),

                  // ── 可捲動區:動作選單 ─────────────────────────
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),

                          // ── 手部復健選單 ────────────────────────────────
                          _buildAccordion(
                            title: '手部復健',
                            icon: '🖐️',
                            subtitle: '翻掌 · 側捏 · 翹手腕 · 左右彎手腕',
                            isExpanded: _handExpanded,
                            onToggle: () => setState(() {
                              _handExpanded = !_handExpanded;
                              if (_handExpanded &&
                                  _selectedAction != null &&
                                  _bodyActions
                                      .contains(_selectedAction!.type)) {
                                _selectedAction = null;
                                _selectedDifficulty = null;
                              }
                              _broadcastSync();
                            }),
                            child: Column(
                              children: kTrainingActions
                                  .where((a) => _handActions.contains(a.type))
                                  .map(_buildActionCard)
                                  .toList(),
                            ),
                          ),
                          const SizedBox(height: 10),

                          // ── 全身復健選單 ────────────────────────────────
                          _buildAccordion(
                            title: '全身復健',
                            icon: '🦴',
                            subtitle: '抬腳 · 畫圓 · 舉高 · 雙手抬舉 · 手肘前伸 · 坐站 · 骨架偵測',
                            isExpanded: _bodyExpanded,
                            onToggle: () => setState(() {
                              _bodyExpanded = !_bodyExpanded;
                              if (_bodyExpanded &&
                                  _selectedAction != null &&
                                  _handActions
                                      .contains(_selectedAction!.type)) {
                                _selectedAction = null;
                                _selectedDifficulty = null;
                              }
                              _broadcastSync();
                            }),
                            child: Column(
                              children: [
                                ...kTrainingActions
                                    .where((a) =>
                                        _bodyActions.contains(a.type) &&
                                        a.type != ActionType.bodyTest)
                                    .map(_buildActionCard),
                                _buildBodyTestCard(),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),

                  // ── 固定在底部的操作區 ─────────────────────────
                  _buildBottomBar(),
                ],
              ),
            ),
          ),
        ));
  }

  // ── 固定底部操作區(難度 / 次數 / 開始訓練 / 查看紀錄) ──
  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_selectedAction != null &&
              _selectedAction!.type != ActionType.bodyTest) ...[
            _buildSectionLabel('選擇難度等級'),
            const SizedBox(height: 8),
            _buildDifficultySelector(),
            const SizedBox(height: 10),
            _buildRepsInput(),
            const SizedBox(height: 12),
            _buildStartButton(),
            const SizedBox(height: 8),
          ],
          _buildHistoryButton(),
        ],
      ),
    );
  }

  Widget _buildAccordion({
    required String title,
    required String icon,
    required String subtitle,
    required bool isExpanded,
    required VoidCallback onToggle,
    required Widget child,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6FA),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isExpanded
              ? const Color(0xFF4A65FF).withValues(alpha: 0.5)
              : const Color(0xFFDDE0F0),
          width: isExpanded ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isExpanded
                          ? const Color(0xFF4A65FF).withValues(alpha: 0.15)
                          : const Color(0xFFEDEFF7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(icon, style: const TextStyle(fontSize: 20)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: isExpanded
                                ? const Color(0xFF1A1D2E)
                                : const Color(0xFF374151),
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: const TextStyle(
                              color: Color(0xFF9CA3AF), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: const Icon(Icons.keyboard_arrow_down,
                        color: Color(0xFF6B7280), size: 22),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: child,
            ),
            secondChild: const SizedBox.shrink(),
            crossFadeState: isExpanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 250),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              // 🖥️ 電視投放新增:同步返回指令
              final msg = {'type': 'POP_SCREEN'};
              if (_clientService.isConnected) {
                _clientService.sendCommand(msg);
              }
              Navigator.of(context).pop();
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F6FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDDE0F0)),
              ),
              child: const Icon(Icons.arrow_back_ios_new,
                  color: Color(0xFF374151), size: 16),
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '選擇訓練動作',
                  style: TextStyle(
                    color: Color(0xFF1A1D2E),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '請選擇要訓練的動作與難度',
                  style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF6B7280),
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildActionCard(TrainingAction action) {
    final isSelected = _selectedAction?.type == action.type;
    return GestureDetector(
      onTap: () => _selectAction(action),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEAEEFF) : const Color(0xFFF5F6FA),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color:
                isSelected ? const Color(0xFF4A65FF) : const Color(0xFFDDE0F0),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF4A65FF).withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  )
                ]
              : [],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF4A65FF).withValues(alpha: 0.15)
                    : const Color(0xFFEDEFF7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(action.emoji, style: const TextStyle(fontSize: 22)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    action.name,
                    style: TextStyle(
                      color: isSelected
                          ? const Color(0xFF1A1D2E)
                          : const Color(0xFF374151),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    action.description,
                    style:
                        const TextStyle(color: Color(0xFF6B7280), fontSize: 11),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isSelected)
              Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: Color(0xFF4A65FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 13),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBodyTestCard() {
    return GestureDetector(
      onTap: () => _selectAction(
          kTrainingActions.firstWhere((a) => a.type == ActionType.bodyTest)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFDDE0F0)),
          gradient: const LinearGradient(
            colors: [Color(0xFFF5F6FA), Color(0xFFEAEEFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF00BCD4).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFF00BCD4).withValues(alpha: 0.3)),
              ),
              child: const Center(
                child: Text('🦴', style: TextStyle(fontSize: 22)),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '全身骨架偵測',
                        style: TextStyle(
                          color: Color(0xFF1A1D2E),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 8),
                      _BetaBadge(),
                    ],
                  ),
                  SizedBox(height: 2),
                  Text(
                    'RTMPose 全身 133 關鍵點即時追蹤',
                    style: TextStyle(color: Color(0xFF6B7280), fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                color: Color(0xFF00BCD4), size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildDifficultySelector() {
    if (_selectedAction == null) return const SizedBox();
    return Row(
      children: _selectedAction!.difficulties.map((diff) {
        final isSelected = _selectedDifficulty?.level == diff.level;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() {
              _selectedDifficulty = diff;
              _repsController.text = '${diff.targetReps}'; // ← 新增
              _broadcastSync();
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF4A65FF)
                    : const Color(0xFFF5F6FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF4A65FF)
                      : const Color(0xFFDDE0F0),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    diff.label,
                    style: TextStyle(
                      color:
                          isSelected ? Colors.white : const Color(0xFF374151),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    diff.description,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.7)
                          : const Color(0xFF9CA3AF),
                      fontSize: 10,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── 目標次數輸入框 + 升級模式開關 ─────────────────────────
  Widget _buildRepsInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDDE0F0)),
      ),
      child: Row(
        children: [
          const Text(
            '目標次數',
            style: TextStyle(
                color: Color(0xFF374151),
                fontSize: 14,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 48, // ← 縮小(原本 64)
            child: TextField(
              controller: _repsController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1D2E)),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFDDE0F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF4A65FF)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          const Text('下',
              style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),

          const Spacer(), // 🆕 把開關推到最右邊

          // 🆕 升級模式開關
          GestureDetector(
            onTap: () => setState(() {
              _autoLevelUp = !_autoLevelUp;
              _broadcastSync();
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _autoLevelUp
                    ? const Color(0xFF4A65FF).withValues(alpha: 0.1)
                    : const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _autoLevelUp
                      ? const Color(0xFF4A65FF)
                      : const Color(0xFFFF9800),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _autoLevelUp ? Icons.bolt : Icons.touch_app,
                    size: 15,
                    color: _autoLevelUp
                        ? const Color(0xFF4A65FF)
                        : const Color(0xFFFF9800),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _autoLevelUp ? '自動升級' : '手動確認',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _autoLevelUp
                          ? const Color(0xFF4A65FF)
                          : const Color(0xFFFF9800),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStartButton() {
    final canStart = _selectedAction != null && _selectedDifficulty != null;
    return GestureDetector(
      onTap: canStart ? _startTraining : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        height: 58,
        decoration: BoxDecoration(
          gradient: canStart
              ? const LinearGradient(
                  colors: [Color(0xFF4A65FF), Color(0xFF6B82FF)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
          color: canStart ? null : const Color(0xFFEDEFF7),
          borderRadius: BorderRadius.circular(16),
          boxShadow: canStart
              ? [
                  BoxShadow(
                    color: const Color(0xFF4A65FF).withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  )
                ]
              : [],
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.play_arrow_rounded,
                color: canStart ? Colors.white : const Color(0xFFB0B3C5),
                size: 26,
              ),
              const SizedBox(width: 8),
              Text(
                '開始訓練',
                style: TextStyle(
                  color: canStart ? Colors.white : const Color(0xFFB0B3C5),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryButton() {
    return GestureDetector(
      onTap: () {
        // 🖥️ 電視投放新增:同步跳轉指令
        if (_clientService.isConnected) {
          _clientService
              .sendCommand({'type': 'OPEN_SCREEN', 'screen': 'HISTORY'});
        }
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const HistoryScreen()),
        );
      },
      child: Container(
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
          color: const Color(0xFFF5F6FA),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFDDE0F0)),
        ),
        child: const Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('📋', style: TextStyle(fontSize: 18)),
              SizedBox(width: 8),
              Text(
                '查看訓練紀錄',
                style: TextStyle(
                  color: Color(0xFF374151),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

  // 🖥️ 下列為電視投放所需的輔助方法
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
        return StandingKneeRaiseAction(
            difficulty: d, targetCount: diff.targetReps);
      case ActionType.drawCircle:
        return DrawCircleAction(difficulty: d, targetCount: diff.targetReps);
      case ActionType.reach:
        return ReachAction(difficulty: d, targetCount: diff.targetReps);
      case ActionType.raiseBothArms:
        return RaiseBothArmsAction(difficulty: d, targetCount: diff.targetReps);
      case ActionType.elbowForward:
        return ElbowForwardAction(difficulty: d, targetCount: diff.targetReps);
      case ActionType.sitToStand:
        return SitToStandAction(difficulty: d, targetCount: diff.targetReps);
      case ActionType.lateralStep:
        return LateralStepAction(difficulty: d, targetCount: diff.targetReps);
      default:
        return StandingKneeRaiseAction(
            difficulty: d, targetCount: diff.targetReps);
    }
  }
}

class _BetaBadge extends StatelessWidget {
  const _BetaBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF00BCD4).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: const Color(0xFF00BCD4).withValues(alpha: 0.4), width: 1),
      ),
      child: const Text(
        'Beta',
        style: TextStyle(
          color: Color(0xFF00BCD4),
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
