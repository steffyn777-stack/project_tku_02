// lib/features/demo/demo_library_screen.dart

import 'package:flutter/material.dart';
import 'dart:async'; // 🖥️ 電視投放新增
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'bone_viewer_screen.dart';

// 🖥️ 電視投放新增
import '../tv_cast/socket_client_service.dart';
import '../tv_cast/socket_server_service.dart';

// ── 動作分類 ──────────────────────────────────────────────
enum DemoCategory { all, arm, fullBody }

// ── 動作資料模型 ──────────────────────────────────────────
class _DemoItem {
  final String emoji;
  final String title;
  final String subtitle;
  final List<String> tabLabels;
  final List<String> modelSrcs;
  final List<String> modelAlts;
  final DemoCategory category;
  final String? cameraOrbit; // ← 新增(選填)
  final String? fieldOfView; // ← 新增(選填)
  final String? cameraTarget; // ← 新增(選填)

  const _DemoItem({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.tabLabels,
    required this.modelSrcs,
    required this.modelAlts,
    required this.category,
    this.cameraOrbit, // ← 新增
    this.fieldOfView, // ← 新增
    this.cameraTarget, // ← 新增
  });
}

class DemoLibraryScreen extends StatefulWidget {
  final bool isDisplay; // 🖥️ 電視投放新增
  const DemoLibraryScreen({super.key, this.isDisplay = false});

  @override
  State<DemoLibraryScreen> createState() => _DemoLibraryScreenState();
}

class _DemoLibraryScreenState extends State<DemoLibraryScreen>
    with TickerProviderStateMixin {
  final _clientService = SocketClientService(); // 🖥️ 電視投放新增

  DemoCategory _selectedCategory = DemoCategory.all;

  // ── 所有動作資料 ──────────────────────────────────────────
  final List<_DemoItem> _items = const [
    _DemoItem(
      emoji: '🖐️',
      title: '翻掌訓練',
      subtitle: '前臂旋轉・拖曳旋轉・雙指縮放',
      tabLabels: ['示範'],
      modelSrcs: ['assets/models/forearm_supination.glb'],
      modelAlts: ['翻掌示範'],
      category: DemoCategory.arm,
      cameraOrbit: '0deg 75deg 5%', // ← 你調好的
      fieldOfView: '5deg', // ← 你調好的
      cameraTarget: '0m 5m 0m', // ← 你調好的
    ),
    _DemoItem(
      emoji: '🤏',
      title: '手指側捏訓練',
      subtitle: '拖曳旋轉・雙指縮放',
      tabLabels: ['示範'],
      modelSrcs: ['assets/models/lateral_pinch.glb'],
      modelAlts: ['手指側捏示範'],
      category: DemoCategory.arm,
      // 如果訓練示範頁有調鏡頭,這裡也套一樣的參數
      cameraOrbit: '0deg 75deg 5%',
      fieldOfView: '5deg',
      cameraTarget: '0m 5m 0m',
    ),
    _DemoItem(
      emoji: '🙋',
      title: '伸手舉高訓練',
      subtitle: '左右手可切換・拖曳旋轉・雙指縮放',
      tabLabels: ['左手', '右手'],
      modelSrcs: [
        'assets/models/turn_Right_hand.glb',
        'assets/models/turn_Left_hand.glb',
      ],
      modelAlts: ['左手舉高示範', '右手舉高示範'],
      category: DemoCategory.arm,
    ),
    _DemoItem(
      emoji: '🔄',
      title: '手臂畫圓訓練',
      subtitle: '右手示範・拖曳旋轉・雙指縮放',
      tabLabels: ['右手'],
      modelSrcs: ['assets/models/arm_circle_right.glb'],
      modelAlts: ['右手畫圓示範'],
      category: DemoCategory.arm,
    ),
    _DemoItem(
      emoji: '🙌',
      title: '雙手抬舉訓練',
      subtitle: '拖曳旋轉・雙指縮放',
      tabLabels: ['示範'],
      modelSrcs: ['assets/models/Both_Arms_Arise.glb'],
      modelAlts: ['雙手抬舉示範'],
      category: DemoCategory.fullBody,
    ),
    _DemoItem(
      emoji: '🦵',
      title: '站立抬腿訓練',
      subtitle: '左右腳可切換・拖曳旋轉・雙指縮放',
      tabLabels: ['左腳', '右腳'],
      modelSrcs: [
        'assets/models/Standing_Leg_Raise_Right.glb',
        'assets/models/Standing_Leg_Raise_left.glb',
      ],
      modelAlts: ['左腳抬腿示範', '右腳抬腿示範'],
      category: DemoCategory.fullBody,
    ),
    // ← 加在這裡
    _DemoItem(
      emoji: '💪',
      title: '手肘屈伸訓練',
      subtitle: '拖曳旋轉・雙指縮放',
      tabLabels: ['示範'],
      modelSrcs: ['assets/models/elbow_flexion_extension.glb'],
      modelAlts: ['手肘屈伸示範'],
      category: DemoCategory.arm,
    ),
    _DemoItem(
      emoji: '🚶',
      title: '側跨步訓練',
      subtitle: '拖曳旋轉・雙指縮放',
      tabLabels: ['示範'],
      modelSrcs: ['assets/models/side_step.glb'],
      modelAlts: ['側跨步示範'],
      category: DemoCategory.fullBody,
    ),
    _DemoItem(
      emoji: '🏋️',
      title: '深蹲訓練',
      subtitle: '拖曳旋轉・雙指縮放',
      tabLabels: ['示範'],
      modelSrcs: ['assets/models/squat.glb'],
      modelAlts: ['深蹲示範'],
      category: DemoCategory.fullBody,
    ),
  ];

  // ── 每張卡片的展開狀態 & tab index ──────────────────────
  late final List<bool> _expanded;
  late final List<int> _tabIndex;
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _anims;

  StreamSubscription? _socketSub; // 🖥️ 電視投放新增

  @override
  void initState() {
    super.initState();
    _expanded = List.filled(_items.length, false);
    _tabIndex = List.filled(_items.length, 0);
    _controllers = List.generate(
      _items.length,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 320),
      ),
    );
    _anims = _controllers
        .map((c) => CurvedAnimation(parent: c, curve: Curves.easeInOut))
        .toList();

    // 🖥️ 電視投放新增:監聽同步指令
    final clientService = SocketClientService();
    final serverService = SocketServerService();
    if (clientService.isConnected) {
      _socketSub = clientService.messages.listen(_handleSyncMessage);
    } else if (serverService.isClientConnected) {
      _socketSub = serverService.messages.listen(_handleSyncMessage);
    }
  }

  void _handleSyncMessage(Map<String, dynamic> msg) {
    if (!widget.isDisplay || !mounted) return;
    if (msg['type'] != 'DEMO_LIBRARY_SYNC') return;

    setState(() {
      final catName = msg['selectedCategory'];
      if (catName != null) {
        _selectedCategory =
            DemoCategory.values.firstWhere((e) => e.name == catName);
      }

      final expandedIdx = msg['expandedIndex'] as int?;
      for (int i = 0; i < _expanded.length; i++) {
        if (i == expandedIdx) {
          if (!_expanded[i]) {
            _expanded[i] = true;
            _controllers[i].forward();
          }
        } else {
          if (_expanded[i]) {
            _expanded[i] = false;
            _controllers[i].reverse();
          }
        }
      }

      final tabIndices = msg['tabIndices'] as Map<String, dynamic>?;
      if (tabIndices != null) {
        tabIndices.forEach((key, value) {
          final idx = int.tryParse(key);
          if (idx != null && idx >= 0 && idx < _tabIndex.length) {
            _tabIndex[idx] = value as int;
          }
        });
      }
    });
  }

  void _broadcastSync() {
    if (widget.isDisplay) return;

    final Map<String, int> tabIndices = {};
    for (int i = 0; i < _tabIndex.length; i++) {
      if (_tabIndex[i] != 0) {
        tabIndices[i.toString()] = _tabIndex[i];
      }
    }

    int? expandedIdx;
    for (int i = 0; i < _expanded.length; i++) {
      if (_expanded[i]) {
        expandedIdx = i;
        break;
      }
    }

    final msg = {
      'type': 'DEMO_LIBRARY_SYNC',
      'selectedCategory': _selectedCategory.name,
      'expandedIndex': expandedIdx,
      'tabIndices': tabIndices,
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
    for (final c in _controllers) {
      c.dispose();
    }
    _socketSub?.cancel();
    super.dispose();
  }

  void _toggle(int idx) {
    setState(() {
      final wasExpanded = _expanded[idx];
      // 先收起所有已展開的(含它自己)
      for (int i = 0; i < _expanded.length; i++) {
        if (_expanded[i]) {
          _expanded[i] = false;
          _controllers[i].reverse();
        }
      }
      // 原本是收起的 → 展開它;原本是展開的 → 保持收起(等於關閉)
      if (!wasExpanded) {
        _expanded[idx] = true;
        _controllers[idx].forward();
      }
    });
    _broadcastSync();
  }

  List<_DemoItem> get _filteredItems => _selectedCategory == DemoCategory.all
      ? _items
      : _items.where((item) => item.category == _selectedCategory).toList();

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
            children: [
              _buildTopBar(context),
              _buildCategoryTabs(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              // 🖥️ 電視投放新增:同步返回指令
              if (_clientService.isConnected) {
                _clientService.sendCommand({'type': 'POP_SCREEN'});
              }
              Navigator.of(context).pop();
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDDE0F0)),
              ),
              child: const Icon(Icons.arrow_back_ios_new,
                  color: Color(0xFF374151), size: 16),
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            '動作示範庫',
            style: TextStyle(
              color: Color(0xFF1A1D2E),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  // ── 分類 tab ───────────────────────────────────────────
  Widget _buildCategoryTabs() {
    final tabs = [
      (category: DemoCategory.all, label: '全部', icon: Icons.grid_view_rounded),
      (category: DemoCategory.arm, label: '手部', icon: Icons.back_hand_outlined),
      (
        category: DemoCategory.fullBody,
        label: '全身',
        icon: Icons.accessibility_new
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: tabs.map((tab) {
          final isActive = _selectedCategory == tab.category;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _selectedCategory = tab.category);
                _broadcastSync();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFF4A65FF) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isActive
                        ? const Color(0xFF4A65FF)
                        : const Color(0xFFDDE0F0),
                  ),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color:
                                const Color(0xFF4A65FF).withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : [],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      tab.icon,
                      size: 18,
                      color: isActive ? Colors.white : const Color(0xFF6B7280),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tab.label,
                      style: TextStyle(
                        color:
                            isActive ? Colors.white : const Color(0xFF6B7280),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBody() {
    final filtered = _filteredItems;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          // 動作卡片列表
          ...filtered.map((item) {
            final idx = _items.indexOf(item);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildDemoCard(
                item: item,
                idx: idx,
              ),
            );
          }),

          // 即時骨架連動入口
          GestureDetector(
            onTap: () {
              // 🖥️ 電視投放新增:同步跳轉指令
              if (_clientService.isConnected) {
                _clientService.sendCommand(
                    {'type': 'OPEN_SCREEN', 'screen': 'BONE_VIEWER'});
              }
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BoneViewerScreen()),
              );
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A1D2E), Color(0xFF2D3250)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1A1D2E).withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.accessibility_new,
                      color: Color(0xFF00E5FF), size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    '即時骨架連動',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: const BoxDecoration(
                      color: Color(0xFF00E5FF),
                      borderRadius: BorderRadius.all(Radius.circular(6)),
                    ),
                    child: const Text(
                      'BETA',
                      style: TextStyle(
                        color: Color(0xFF1A1D2E),
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
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

  Widget _buildDemoCard({
    required _DemoItem item,
    required int idx,
  }) {
    final expanded = _expanded[idx];
    final currentTab = _tabIndex[idx];
    final modelSrc =
        item.modelSrcs[currentTab.clamp(0, item.modelSrcs.length - 1)];
    final modelAlt =
        item.modelAlts[currentTab.clamp(0, item.modelAlts.length - 1)];

    return Column(
      children: [
        // header
        GestureDetector(
          onTap: () => _toggle(idx),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFDDE0F0)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F2FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child:
                        Text(item.emoji, style: const TextStyle(fontSize: 22)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          style: const TextStyle(
                            color: Color(0xFF1A1D2E),
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          )),
                      const SizedBox(height: 2),
                      Text(item.subtitle,
                          style: const TextStyle(
                              color: Color(0xFF6B7280), fontSize: 12)),
                    ],
                  ),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: expanded
                        ? const Color(0xFF4A65FF)
                        : const Color(0xFFF5F6FA),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeInOut,
                    child: Icon(Icons.keyboard_arrow_down,
                        color:
                            expanded ? Colors.white : const Color(0xFF6B7280),
                        size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),

        // 展開區塊
        SizeTransition(
          sizeFactor: _anims[idx],
          axisAlignment: -1,
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              children: [
                if (item.tabLabels.length > 1)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFDDE0F0)),
                    ),
                    child: Row(
                      children: List.generate(item.tabLabels.length, (i) {
                        final isActive = currentTab == i;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() => _tabIndex[idx] = i);
                              _broadcastSync();
                            },
                            behavior: HitTestBehavior.opaque,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? const Color(0xFF4A65FF)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Text(
                                  item.tabLabels[i],
                                  style: TextStyle(
                                    color: isActive
                                        ? Colors.white
                                        : const Color(0xFF6B7280),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                if (item.tabLabels.length > 1) const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: SizedBox(
                    height: 380,
                    child: expanded
                        ? ModelViewer(
                            key: ValueKey(modelSrc),
                            src: modelSrc,
                            alt: modelAlt,
                            autoRotate: true,
                            autoRotateDelay: 1000,
                            autoPlay: true,
                            cameraControls: true,
                            cameraOrbit: item.cameraOrbit,
                            fieldOfView: item.fieldOfView,
                            cameraTarget: item.cameraTarget,
                            backgroundColor: const Color(0xFF1A1D2E),
                          )
                        : const SizedBox.shrink(), // 摺疊時完全不建 WebView
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
