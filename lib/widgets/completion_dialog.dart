// lib/widgets/completion_dialog.dart
//
// 🆕 2026-08-22:
//   1. onStartNew 簽名擴充成 (action, difficulty, autoLevelUp),
//      換動作時使用者可以順便選目標次數跟自動/手動升級模式,
//      不會被迫沿用切換前的設定。
//   2. _OtherActionsSection 的確認面板加上「目標次數」輸入框
//      跟「自動升級／手動確認」切換開關,樣式比照 action_list_screen.dart。
//   3. 如果該動作只有一個難度,確認面板改顯示該難度的靜態標籤,
//      不再顯示一整排「只有一個選項」的可點選按鈕。

import 'package:flutter/material.dart';
import '../models/training_action.dart';

// 手部動作清單(與 home_screen 同步)
const _handActions = [
  ActionType.turnPalm,
  ActionType.sidePinch,
  ActionType.wristExtension,
  ActionType.wristSideBend,
];

// 全身動作清單(與 home_screen / action_list_screen 同步)
// ⚠️ 修正:原本漏了 sitToStand、lateralStep 兩個動作,
// 導致做完「坐站訓練」「側跨步訓練」後,完成對話框的
// 「或換個動作」清單裡看不到這兩個選項,而且全身復健
// 手風琴也不會自動展開。
// TODO: 這份清單目前跟 action_list_screen.dart 是各自維護的兩份,
// 之後建議抽成 training_action.dart 裡的共用常數,
// 兩邊都 import 同一份,避免再次漏同步。
const _bodyActions = [
  ActionType.wipeBody,
  ActionType.drawCircle,
  ActionType.reach,
  ActionType.raiseBothArms,
  ActionType.elbowForward,
  ActionType.sitToStand,
  ActionType.lateralStep,
  ActionType.bodyTest,
];

class CompletionDialog extends StatefulWidget {
  final int repCount;
  final int durationSeconds;
  final List<String> mistakeLogs;
  final VoidCallback onRetry;
  final VoidCallback onHome;

  final TrainingAction currentAction;
  final DifficultyOption currentDifficulty;

  // 🆕 多帶一個 autoLevelUp,讓換動作時使用者選的升級模式能傳出去
  final void Function(
    TrainingAction action,
    DifficultyOption difficulty,
    bool autoLevelUp,
  ) onStartNew;

  /// 暫停模式:標題改「訓練暫停」、文案改成「剛剛做了 X 下,辛苦了」
  final bool isPaused;

  /// 這次訓練是否有錄到影片(沒有的話不顯示保留詢問區塊)
  final bool hasVideo;

  /// 使用者選擇保留(true)或不保留(false)這段錄影時呼叫
  final void Function(bool keep)? onVideoDecision;

  const CompletionDialog({
    super.key,
    required this.repCount,
    required this.durationSeconds,
    required this.mistakeLogs,
    required this.onRetry,
    required this.onHome,
    required this.currentAction,
    required this.currentDifficulty,
    required this.onStartNew,
    this.isPaused = false,
    this.hasVideo = false,
    this.onVideoDecision,
  });

  @override
  State<CompletionDialog> createState() => _CompletionDialogState();
}

class _CompletionDialogState extends State<CompletionDialog> {
  // null = 尚未決定,true = 保留,false = 不保留
  bool? _keepVideo;

  // 使用者選完之後,先讓確認文字顯示一下,再把整個區塊收合消失
  bool _videoBlockHidden = false;

  void _selectKeepVideo(bool keep) {
    if (_keepVideo != null) return; // 避免重複觸發
    setState(() => _keepVideo = keep);
    widget.onVideoDecision?.call(keep);

    // 讓使用者先看到「已保留/已捨棄」的確認文字,
    // 停留一下再讓整個小區塊收合消失,才不會覺得「按了沒反應」。
    Future.delayed(const Duration(milliseconds: 550), () {
      if (mounted) setState(() => _videoBlockHidden = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final minutes = widget.durationSeconds ~/ 60;
    final seconds = widget.durationSeconds % 60;
    final timeText = '$minutes:${seconds.toString().padLeft(2, '0')}';

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.isPaused ? '⏸️' : '🎉', style: const TextStyle(fontSize: 48)),
              const SizedBox(height: 10),
              Text(
                widget.isPaused ? '訓練暫停' : '訓練完成',
                style: const TextStyle(
                    color: Color(0xFF1A1D2E),
                    fontSize: 24,
                    fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 18),

              // ── 資訊區:有溫度的文案 + 時長/難度 ───────────────────
              _buildInfoBlock(timeText),

              // ── 保留錄影詢問區塊(選完後會自動收合消失)──────────────
              if (widget.hasVideo)
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  child: _videoBlockHidden
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: _buildVideoKeepBlock(),
                        ),
                ),

              const SizedBox(height: 22),
              _divider(widget.isPaused ? '想做什麼?' : '接下來要做什麼?'),
              const SizedBox(height: 14),

              // ── 再來一組(相同動作+難度)───────────────────────────
              _actionButton(
                icon: '🔄',
                label: widget.isPaused ? '繼續訓練' : '再來一組',
                subtitle: '${widget.currentAction.name} · ${widget.currentDifficulty.label}',
                color: const Color(0xFF4A65FF),
                onTap: widget.onRetry,
              ),
              const SizedBox(height: 10),

              // ── 切換難度(相同動作的其他難度)──────────────────────
              if (widget.currentAction.difficulties.length > 1) ...[
                _divider('換個難度'),
                const SizedBox(height: 10),
                _DifficultyRow(
                  action: widget.currentAction,
                  currentDifficulty: widget.currentDifficulty,
                  onSelect: (diff) =>
                      widget.onStartNew(widget.currentAction, diff, true), // 🆕 同動作切難度預設沿用自動升級
                ),
                const SizedBox(height: 10),
              ],

              // ── 選其他動作(手部/全身兩個 Accordion)────────────────
              _divider('或換個動作'),
              const SizedBox(height: 10),
              _OtherActionsSection(
                currentAction: widget.currentAction,
                onSelect: widget.onStartNew,
              ),

              const SizedBox(height: 14),

              // ── 回首頁 ──────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: widget.onHome,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFDDE0F0)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text(
                    '🏠 回到首頁',
                    style: TextStyle(
                        color: Color(0xFF374151),
                        fontSize: 15,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── 資訊區:有溫度的文案 + 時長 + 難度 ───────────────────
  Widget _buildInfoBlock(String timeText) {
    final mainText = widget.isPaused
        ? '你剛剛做了 ${widget.repCount} 下,辛苦了'
        : '恭喜完成 ${widget.repCount} 下,做得很棒!';
    final difficultyPrefix = widget.isPaused ? '目前難度' : '通關難度';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDDE0F0)),
      ),
      child: Column(
        children: [
          Text(
            mainText,
            style: const TextStyle(
              color: Color(0xFF1A1D2E),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.timer_outlined,
                  color: Color(0xFF6B7280), size: 14),
              const SizedBox(width: 4),
              Text(
                '時長 $timeText',
                style: const TextStyle(
                    color: Color(0xFF6B7280), fontSize: 12),
              ),
              const SizedBox(width: 16),
              Container(
                width: 4,
                height: 4,
                decoration: const BoxDecoration(
                  color: Color(0xFFB0B3C5),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                '$difficultyPrefix ${widget.currentDifficulty.label}',
                style: const TextStyle(
                    color: Color(0xFF6B7280), fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── 保留錄影詢問區塊 ───────────────────────────────────
  Widget _buildVideoKeepBlock() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F2FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF4A65FF).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.videocam_outlined, color: Color(0xFF4A65FF), size: 18),
              SizedBox(width: 8),
              Text(
                '這次訓練錄了一段影片',
                style: TextStyle(
                    color: Color(0xFF1A1D2E),
                    fontSize: 13,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '要保留這段錄影嗎?保留後可以在歷史紀錄裡回放。',
            style: TextStyle(color: Color(0xFF6B7280), fontSize: 11),
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _keepVideo == null
                ? Row(
                    key: const ValueKey('video_choice_buttons'),
                    children: [
                      Expanded(
                        child: _videoChoiceButton(
                          label: '保留',
                          icon: Icons.check_circle_outline,
                          selected: false,
                          onTap: () => _selectKeepVideo(true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _videoChoiceButton(
                          label: '不保留',
                          icon: Icons.delete_outline,
                          selected: false,
                          onTap: () => _selectKeepVideo(false),
                        ),
                      ),
                    ],
                  )
                : Row(
                    key: const ValueKey('video_choice_confirmed'),
                    children: [
                      Icon(
                        _keepVideo! ? Icons.check_circle : Icons.delete,
                        color: const Color(0xFF4A65FF),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _keepVideo! ? '已保留這段影片' : '已捨棄這段影片',
                        style: const TextStyle(
                          color: Color(0xFF4A65FF),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _videoChoiceButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF4A65FF) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? const Color(0xFF4A65FF)
                : const Color(0xFFDDE0F0),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16,
                color: selected ? Colors.white : const Color(0xFF6B7280)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFF374151),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider(String label) {
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: const Color(0xFFDDE0F0))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(label,
              style: const TextStyle(
                  color: Color(0xFF9CA3AF), fontSize: 11)),
        ),
        Expanded(child: Container(height: 1, color: const Color(0xFFDDE0F0))),
      ],
    );
  }

  Widget _actionButton({
    required String icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                Text(subtitle,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── 難度切換列 ─────────────────────────────────────────────────────────────
class _DifficultyRow extends StatelessWidget {
  final TrainingAction action;
  final DifficultyOption currentDifficulty;
  final void Function(DifficultyOption) onSelect;

  const _DifficultyRow({
    required this.action,
    required this.currentDifficulty,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: action.difficulties.map((diff) {
        final isCurrent = diff.level == currentDifficulty.level;
        return Expanded(
          child: GestureDetector(
            onTap: isCurrent ? null : () => onSelect(diff),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              decoration: BoxDecoration(
                color: isCurrent
                    ? const Color(0xFFEDEFF7)
                    : const Color(0xFFF5F6FA),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isCurrent
                      ? const Color(0xFFDDE0F0)
                      : const Color(0xFF4A65FF).withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    diff.label,
                    style: TextStyle(
                      color: isCurrent
                          ? const Color(0xFF9CA3AF)
                          : const Color(0xFF1A1D2E),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (isCurrent)
                    const Text('目前',
                        style: TextStyle(
                            color: Color(0xFF9CA3AF), fontSize: 9)),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── 其他動作選擇區(手部 + 全身兩個 Accordion)──────────────────────────────
class _OtherActionsSection extends StatefulWidget {
  final TrainingAction currentAction;
  final void Function(
    TrainingAction action,
    DifficultyOption difficulty,
    bool autoLevelUp, // 🆕
  ) onSelect;

  const _OtherActionsSection({
    required this.currentAction,
    required this.onSelect,
  });

  @override
  State<_OtherActionsSection> createState() => _OtherActionsSectionState();
}

class _OtherActionsSectionState extends State<_OtherActionsSection> {
  late bool _handExpanded;
  late bool _bodyExpanded;

  TrainingAction? _pendingAction;
  DifficultyOption? _pendingDifficulty;

  // 🆕 換動作確認面板:目標次數 + 升級模式
  final TextEditingController _pendingRepsController = TextEditingController();
  bool _pendingAutoLevelUp = true;

  @override
  void initState() {
    super.initState();
    _handExpanded = _handActions.contains(widget.currentAction.type);
    _bodyExpanded = _bodyActions.contains(widget.currentAction.type);
  }

  @override
  void dispose() {
    _pendingRepsController.dispose(); // 🆕
    super.dispose();
  }

  void _startPending(TrainingAction action) {
    final firstDiff = action.difficulties.first;
    setState(() {
      _pendingAction = action;
      _pendingDifficulty = firstDiff;
      _pendingRepsController.text = '${firstDiff.targetReps}'; // 🆕
      _pendingAutoLevelUp = true; // 🆕 每次重新選動作都重置回預設
    });
  }

  void _cancelPending() {
    setState(() {
      _pendingAction = null;
      _pendingDifficulty = null;
    });
  }

  void _confirmPending() {
    if (_pendingAction == null || _pendingDifficulty == null) return;

    var diff = _pendingDifficulty!;
    final customReps = int.tryParse(_pendingRepsController.text); // 🆕
    if (customReps != null && customReps > 0) {
      diff = diff.copyWithReps(customReps);
    }

    widget.onSelect(_pendingAction!, diff, _pendingAutoLevelUp); // 🆕
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildAccordion(
          title: '手部復健',
          icon: '🖐️',
          subtitle: '翻掌 · 側捏 · 翹手腕 · 左右彎手腕',
          isExpanded: _handExpanded,
          onToggle: () => setState(() => _handExpanded = !_handExpanded),
          children: kTrainingActions
              .where((a) => _handActions.contains(a.type))
              .expand(_buildActionTileGroup)
              .toList(),
        ),
        const SizedBox(height: 8),
        _buildAccordion(
          title: '全身復健',
          icon: '🦴',
          subtitle: '抬腳 · 畫圓 · 舉高 · 雙手抬舉 · 手肘前伸 · 坐站 · 側跨步',
          isExpanded: _bodyExpanded,
          onToggle: () => setState(() => _bodyExpanded = !_bodyExpanded),
          children: kTrainingActions
              .where((a) =>
                  _bodyActions.contains(a.type) &&
                  a.type != ActionType.bodyTest)
              .expand(_buildActionTileGroup)
              .toList(),
        ),
      ],
    );
  }

  Widget _buildAccordion({
    required String title,
    required String icon,
    required String subtitle,
    required bool isExpanded,
    required VoidCallback onToggle,
    required List<Widget> children,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6FA),
        borderRadius: BorderRadius.circular(16),
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isExpanded
                          ? const Color(0xFF4A65FF).withValues(alpha: 0.15)
                          : const Color(0xFFEDEFF7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                        child: Text(icon, style: const TextStyle(fontSize: 18))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: TextStyle(
                              color: isExpanded
                                  ? const Color(0xFF1A1D2E)
                                  : const Color(0xFF374151),
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            )),
                        Text(subtitle,
                            style: const TextStyle(
                                color: Color(0xFF9CA3AF), fontSize: 10)),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: const Icon(Icons.keyboard_arrow_down,
                        color: Color(0xFF6B7280), size: 20),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(children: children),
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

  List<Widget> _buildActionTileGroup(TrainingAction action) {
    final isPending = _pendingAction?.type == action.type;
    return [
      _buildActionTile(action, isPending: isPending),
      if (isPending) _buildConfirmPanel(action),
    ];
  }

  Widget _buildActionTile(TrainingAction action, {bool isPending = false}) {
    final isCurrent = action.type == widget.currentAction.type;
    return GestureDetector(
      onTap: isCurrent ? null : () => _startPending(action),
      child: Container(
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isCurrent
              ? const Color(0xFFEDEFF7)
              : (isPending ? const Color(0xFFF0F2FF) : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isPending
                ? const Color(0xFF4A65FF)
                : const Color(0xFFDDE0F0),
            width: isPending ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Text(action.emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(action.name,
                      style: TextStyle(
                        color: isCurrent
                            ? const Color(0xFF9CA3AF)
                            : const Color(0xFF1A1D2E),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      )),
                  Text(action.description,
                      style: const TextStyle(
                          color: Color(0xFF6B7280), fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (isCurrent)
              const Text('目前',
                  style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 10))
            else
              Icon(
                isPending ? Icons.keyboard_arrow_up : Icons.arrow_forward_ios,
                color: const Color(0xFF4A65FF),
                size: 13,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmPanel(TrainingAction action) {
    final diffs = action.difficulties;
    final selected = _pendingDifficulty ?? diffs.first;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4A65FF).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '選擇難度',
            style: TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 11,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),

          // 🆕 只有一個難度時,直接顯示那個難度的靜態標籤,不用一排按鈕
          if (diffs.length == 1)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF4A65FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                diffs.first.label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            Row(
              children: diffs.map((diff) {
                final isSelected = diff.level == selected.level;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _pendingDifficulty = diff;
                      _pendingRepsController.text = '${diff.targetReps}'; // 🆕
                    }),
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                          vertical: 9, horizontal: 4),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF4A65FF)
                            : const Color(0xFFF5F6FA),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF4A65FF)
                              : const Color(0xFFDDE0F0),
                        ),
                      ),
                      child: Text(
                        diff.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isSelected ? Colors.white : const Color(0xFF374151),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

          const SizedBox(height: 10),

          // 🆕 目標次數 + 升級模式(樣式比照 action_list_screen.dart 的 _buildRepsInput)
          Row(
            children: [
              const Text(
                '目標次數',
                style: TextStyle(
                    color: Color(0xFF374151),
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 42,
                child: TextField(
                  controller: _pendingRepsController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A1D2E)),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
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
              const SizedBox(width: 3),
              const Text('下', style: TextStyle(color: Color(0xFF6B7280), fontSize: 11)),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _pendingAutoLevelUp = !_pendingAutoLevelUp),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: _pendingAutoLevelUp
                        ? const Color(0xFF4A65FF).withValues(alpha: 0.1)
                        : const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _pendingAutoLevelUp
                          ? const Color(0xFF4A65FF)
                          : const Color(0xFFFF9800),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _pendingAutoLevelUp ? Icons.bolt : Icons.touch_app,
                        size: 13,
                        color: _pendingAutoLevelUp
                            ? const Color(0xFF4A65FF)
                            : const Color(0xFFFF9800),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        _pendingAutoLevelUp ? '自動升級' : '手動確認',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _pendingAutoLevelUp
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

          const SizedBox(height: 10),
          Text(
            '確定要切換到「${action.name} · ${selected.label}」嗎?目前訓練紀錄不會被計入。',
            style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: OutlinedButton(
                    onPressed: _cancelPending,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFDDE0F0)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('取消',
                        style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: ElevatedButton(
                    onPressed: _confirmPending,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4A65FF),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('確定切換',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}