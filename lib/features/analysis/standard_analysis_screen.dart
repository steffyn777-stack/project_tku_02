// lib/features/demo/standard_analysis_screen.dart
//
// ══════════════════════════════════════════════════════════════════
//  動作標準分析
//
//  功能:
//    ✅ 內建預設影片 + 使用者自選影片
//    ✅ 逐幀骨架偵測(RTMPose 全身 133 點)
//    ✅ 多維度特徵萃取(主要關節、對稱性、穩定性、動作次數)
//    ✅ 儲存為 JSON 模板(給未來病人動作比對用)
// ══════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img_lib;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

// 🖥️ 電視投放新增
import '../tv_cast/socket_client_service.dart';

import '../../models/pose_data.dart';
import '../../services/body_pose_engine.dart';
import 'motion_feature_extractor.dart';

import 'hand_analysis_service.dart';
import 'hand_feature_extractor.dart';

class StandardAnalysisScreen extends StatefulWidget {
  const StandardAnalysisScreen({super.key});

  @override
  State<StandardAnalysisScreen> createState() => _StandardAnalysisScreenState();
}

class _StandardAnalysisScreenState extends State<StandardAnalysisScreen> {
  final _clientService = SocketClientService(); // 🖥️ 電視投放新增

  // ── 預設影片清單 ──
  static const List<Map<String, String>> _presetVideos = [
    {
      'name': '站姿抬腳(示範)',
      'actionType': '站姿抬腳',
      'assetPath': 'assets/preset_videos/standing_knee_raise_demo.mp4',
    },
    // 未來擴充加在這裡
  ];

  // ── 選擇狀態 ──
  String? _selectedVideoPath;
  String _currentActionType = '';
  bool _isPreset = false; // 是否為內建影片
  bool _isAnalyzing = false;

  // ── 分析類型(全身 / 手部) ──
  String _analysisType = 'body'; // 'body' 或 'hand'

  // ── 手部分析結果(如果是手部) ──
  HandAnalysisResult? _handResult;

  // ── 使用者輸入動作名稱 ──
  final TextEditingController _actionNameController = TextEditingController();

  // ── 分析進度 ──
  int _totalFrames = 0;
  int _processedFrames = 0;
  int _framesWithPose = 0;

  // ── 多維度分析資料 ──
  final List<List<Offset>> _framePoses = [];
  final List<List<double>> _frameScores = [];
  final List<PoseData> _collectedPoses = [];

  // ── 分析結果 ──
  List<int> _mainJointIndices = [];
  Map<int, double> _jointTotalMovement = {};
  List<double> _actionIntensity = [];
  int _estimatedReps = 0;
  double _symmetryScore = 0;
  double _stabilityScore = 0;

  // ── 引擎 ──
  BodyPoseEngine? _engine;

  @override
  void dispose() {
    _engine?.dispose();
    _actionNameController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════
  //  1. 選影片來源
  // ═══════════════════════════════════════════════════════════════

  void _showVideoSourcePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '選擇影片來源',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1D2E),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading:
                    const Icon(Icons.video_library, color: Color(0xFF4A65FF)),
                title: const Text('內建示範影片'),
                subtitle: Text('${_presetVideos.length} 支可選'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showPresetVideoPicker();
                },
              ),
              const Divider(),
              ListTile(
                leading:
                    const Icon(Icons.folder_open, color: Color(0xFF4CAF50)),
                title: const Text('選我的影片'),
                subtitle: const Text('從相簿選擇 + 手動輸入動作名稱'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickCustomVideo();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPresetVideoPicker() async {
    final picked = await showModalBottomSheet<Map<String, String>>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('選內建示範影片',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              ..._presetVideos.map((v) => ListTile(
                    leading: const Icon(Icons.movie, color: Color(0xFF4A65FF)),
                    title: Text(v['name']!),
                    subtitle: Text('動作類型:${v['actionType']}'),
                    onTap: () => Navigator.pop(ctx, v),
                  )),
            ],
          ),
        ),
      ),
    );

    if (picked == null) return;
    final tempPath = await _copyAssetToTemp(picked['assetPath']!);

    setState(() {
      _selectedVideoPath = tempPath;
      _currentActionType = picked['actionType']!;
      _isPreset = true;
      _resetAnalysisState();
    });
  }

  Future<void> _pickCustomVideo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result == null || result.files.isEmpty) return;

    final actionName = await _askActionName();
    if (actionName == null || actionName.isEmpty) return;

    setState(() {
      _selectedVideoPath = result.files.single.path;
      _currentActionType = actionName;
      _isPreset = false;
      _resetAnalysisState();
    });
  }

  Future<String?> _askActionName() async {
    _actionNameController.text = '';
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('這是什麼動作?'),
        content: TextField(
          controller: _actionNameController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '例如:站姿抬腳、翻掌、側捏',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(ctx, _actionNameController.text.trim()),
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }

  void _resetAnalysisState() {
    _totalFrames = 0;
    _processedFrames = 0;
    _framesWithPose = 0;
    _collectedPoses.clear();
    _framePoses.clear();
    _frameScores.clear();
    _mainJointIndices = [];
    _jointTotalMovement = {};
    _actionIntensity = [];
    _estimatedReps = 0;
    _symmetryScore = 0;
    _stabilityScore = 0;
  }

  Future<String> _copyAssetToTemp(String assetPath) async {
    final bytes = await DefaultAssetBundle.of(context).load(assetPath);
    final tempDir = await getTemporaryDirectory();
    final fileName = assetPath.split('/').last;
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(bytes.buffer.asUint8List());
    return file.path;
  }

  // ═══════════════════════════════════════════════════════════════
  //  2. 開始分析
  // ═══════════════════════════════════════════════════════════════

  Future<void> _startAnalysis() async {
    if (_selectedVideoPath == null) return;

    // 根據分析類型分派
    if (_analysisType == 'hand') {
      await _startHandAnalysis();
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _processedFrames = 0;
      _framesWithPose = 0;
      _collectedPoses.clear();
      _framePoses.clear();
      _frameScores.clear();
    });

    try {
      _engine ??= BodyPoseEngine();
      await _engine!.init();

      // 讀影片實際長度
      final videoCtrl = VideoPlayerController.file(File(_selectedVideoPath!));
      await videoCtrl.initialize();
      final double videoDurationSec =
          videoCtrl.value.duration.inMilliseconds / 1000.0;
      await videoCtrl.dispose();

      // 逐幀設定
      const int fps = 2;
      const int maxAnalyzeSec = 60;
      final double actualAnalyzeSec =
          math.min(videoDurationSec, maxAnalyzeSec.toDouble());
      final int totalFrames = (fps * actualAnalyzeSec).ceil();

      debugPrint('📹 影片長度: ${videoDurationSec.toStringAsFixed(1)} 秒, '
          '將分析前 ${actualAnalyzeSec.toStringAsFixed(1)} 秒 = $totalFrames 幀');

      setState(() => _totalFrames = totalFrames);

      for (int i = 0; i < totalFrames; i++) {
        if (!mounted) return;
        final int timeMs = i * (1000 ~/ fps);

        final Uint8List? jpegBytes = await VideoThumbnail.thumbnailData(
          video: _selectedVideoPath!,
          timeMs: timeMs,
          imageFormat: ImageFormat.JPEG,
          quality: 75,
        );

        if (jpegBytes == null) {
          setState(() => _processedFrames = i + 1);
          continue;
        }

        final img_lib.Image? decoded = img_lib.decodeJpg(jpegBytes);
        if (decoded == null) {
          setState(() => _processedFrames = i + 1);
          continue;
        }

        final Uint8List rgbBytes = _imageToRgbBytes(decoded);

        await _engine!.processExternalFrame(
          rgbBytes,
          decoded.width,
          decoded.height,
          isMirror: false,
        );

        final PoseData pose = _engine!.poseNotifier.value;
        if (pose.keypoints.isNotEmpty) {
          _collectedPoses.add(pose);
          _framePoses.add(List<Offset>.from(pose.keypoints));
          _frameScores.add(List<double>.from(pose.scores));
          setState(() => _framesWithPose++);
        }

        setState(() => _processedFrames = i + 1);
      }

      // 多維度分析
      if (_framePoses.length >= 3) {
        _analyzeMultiDimensional();
        if (mounted) setState(() {});
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('分析完成:$_processedFrames 幀,成功偵測 $_framesWithPose 幀'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分析錯誤:$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  /// 手部影片分析(獨立於全身分析)
  Future<void> _startHandAnalysis() async {
    if (_selectedVideoPath == null) return;

    setState(() {
      _isAnalyzing = true;
      _processedFrames = 0;
      _framesWithPose = 0;
      _handResult = null;
    });

    try {
      final result = await HandAnalysisService.analyzeVideo(
        videoPath: _selectedVideoPath!,
        fps: 3,
        onProgress: (p) {
          if (mounted) {
            setState(() {
              _processedFrames = (p * 100).round();
              _totalFrames = 100;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _handResult = result;
        });

        if (result == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('分析失敗:無法從影片偵測到手部')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('手部分析完成:${result.totalFrames} 幀,'
                  '${result.estimatedReps} 次動作'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分析錯誤:$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  Uint8List _imageToRgbBytes(img_lib.Image img) {
    final int w = img.width;
    final int h = img.height;
    final Uint8List rgb = Uint8List(w * h * 3);
    int idx = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final pixel = img.getPixel(x, y);
        rgb[idx++] = pixel.r.toInt();
        rgb[idx++] = pixel.g.toInt();
        rgb[idx++] = pixel.b.toInt();
      }
    }
    return rgb;
  }

  // ══════════════════════════════════════════════════════════════
  // 多維度特徵萃取(委派給 MotionFeatureExtractor)
  // ══════════════════════════════════════════════════════════════

  void _analyzeMultiDimensional() {
    final result = MotionFeatureExtractor.extractFeatures(
      framePoses: _framePoses,
      frameScores: _frameScores,
    );

    _mainJointIndices = result.mainJointIndices;
    _jointTotalMovement = result.jointTotalMovement;
    _actionIntensity = result.actionIntensity;
    _estimatedReps = result.estimatedReps;
    _symmetryScore = result.symmetryScore;
    _stabilityScore = result.stabilityScore;
  }

  /// 顯示關節名稱(委派)
  String _jointName(int index) => MotionFeatureExtractor.jointName(index);

  // ═══════════════════════════════════════════════════════════════
  //  4. 儲存 JSON 模板
  // ═══════════════════════════════════════════════════════════════

  Future<void> _saveAsTemplate() async {
    // 判斷是否有可儲存的分析結果
    final bool hasBody =
        _analysisType == 'body' && _mainJointIndices.isNotEmpty;
    final bool hasHand = _analysisType == 'hand' && _handResult != null;
    if (!hasBody && !hasHand) return;

    // 讓使用者輸入模板名稱
    final nameCtrl = TextEditingController(text: '$_currentActionType 標準模板');
    final saveName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('儲存為模板'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '模板名稱'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            child: const Text('儲存'),
          ),
        ],
      ),
    );

    if (saveName == null || saveName.isEmpty) return;

    try {
      Map<String, dynamic> data;

      if (hasBody) {
        // ═══ 全身模板 ═══
        data = {
          'modelType': 'body', // ← 新增區分欄位
          'templateName': saveName,
          'actionType': _currentActionType,
          'createdAt': DateTime.now().toIso8601String(),
          'totalFrames': _framePoses.length,
          'estimatedReps': _estimatedReps,
          'symmetryScore': _symmetryScore,
          'stabilityScore': _stabilityScore,
          'mainJoints': _mainJointIndices
              .map((idx) => {
                    'index': idx,
                    'name': _jointName(idx),
                    'movement': _jointTotalMovement[idx] ?? 0,
                  })
              .toList(),
          'actionIntensity': _actionIntensity,
          'framePoses': _framePoses
              .map((frame) => frame
                  .map((offset) => {'x': offset.dx, 'y': offset.dy})
                  .toList())
              .toList(),
          'frameScores': _frameScores,
        };
      } else {
        // ═══ 手部模板 ═══
        data = {
          'modelType': 'hand', // ← 新增區分欄位
          'templateName': saveName,
          'actionType': _currentActionType,
          'createdAt': DateTime.now().toIso8601String(),
          'totalFrames': _handResult!.totalFrames,
          'estimatedReps': _handResult!.estimatedReps,
          'minPinchDistance': _handResult!.minPinchDistance,
          'maxPinchDistance': _handResult!.maxPinchDistance,
          'avgPinchDistance': _handResult!.avgPinchDistance,
          'wristRotationRange': _handResult!.wristRotationRange,
          'avgWristRotation': _handResult!.avgWristRotation,
          'regularityScore': _handResult!.regularityScore,
          'actionIntensity': _handResult!.actionIntensity,
          'mainFingers': _handResult!.mainFingerIndices
              .map((idx) => {
                    'index': idx,
                    'name': HandFeatureExtractor.fingerName(idx),
                    'movement': _handResult!.fingerTotalMovement[idx] ?? 0,
                  })
              .toList(),
        };
      }

      // 存到手機內部目錄
      final dir = await getApplicationDocumentsDirectory();
      final templatesDir = Directory('${dir.path}/templates');
      if (!await templatesDir.exists()) {
        await templatesDir.create(recursive: true);
      }
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${templatesDir.path}/template_$timestamp.json');
      await file.writeAsString(jsonEncode(data));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('模板已儲存(${_analysisType == "hand" ? "手部" : "全身"}):'
                '${file.path.split('/').last}'),
            backgroundColor: const Color(0xFF4CAF50),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('儲存失敗:$e')),
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
//  5. 已存模板管理(顯示清單 + 刪除)
// ═══════════════════════════════════════════════════════════════

  Future<void> _showSavedTemplates() async {
    final templates = await _loadAllTemplates();

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return DraggableScrollableSheet(
            initialChildSize: 0.7,
            maxChildSize: 0.9,
            minChildSize: 0.4,
            expand: false,
            builder: (_, scrollCtrl) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      const Icon(Icons.folder_open, color: Color(0xFF4A65FF)),
                      const SizedBox(width: 8),
                      Text(
                        '已存模板 (${templates.length})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A1D2E),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: templates.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inbox_outlined,
                                  size: 64, color: Color(0xFF9CA3AF)),
                              SizedBox(height: 12),
                              Text(
                                '尚未儲存任何模板',
                                style: TextStyle(
                                    color: Color(0xFF6B7280), fontSize: 14),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: templates.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final t = templates[i];
                            return _buildTemplateCard(t, () async {
                              final ok = await _confirmDelete(
                                  ctx, t['templateName'] ?? '');
                              if (ok == true) {
                                await _deleteTemplate(t['_filePath']);
                                setSheetState(() {
                                  templates.removeAt(i);
                                });
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('已刪除模板'),
                                      backgroundColor: Color(0xFFF44336),
                                    ),
                                  );
                                }
                              }
                            });
                          },
                        ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 讀取所有 JSON 模板(從手機內部目錄)
  Future<List<Map<String, dynamic>>> _loadAllTemplates() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final templatesDir = Directory('${dir.path}/templates');
      if (!await templatesDir.exists()) return [];

      final files = templatesDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList();

      // 依修改時間新到舊排序
      files.sort(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified));

      final List<Map<String, dynamic>> results = [];
      for (final f in files) {
        try {
          final content = await f.readAsString();
          final data = jsonDecode(content) as Map<String, dynamic>;
          data['_filePath'] = f.path;
          results.add(data);
        } catch (e) {
          debugPrint('讀取模板失敗:${f.path} - $e');
        }
      }
      return results;
    } catch (e) {
      debugPrint('列出模板失敗:$e');
      return [];
    }
  }

  /// 刪除模板檔
  Future<void> _deleteTemplate(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('刪除失敗:$e');
    }
  }

  /// 刪除確認 dialog
  Future<bool?> _confirmDelete(BuildContext ctx, String name) async {
    return showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('確定刪除?'),
        content: Text('將永久刪除模板「$name」,無法復原'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF44336),
              foregroundColor: Colors.white,
            ),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
  }

  /// 單一模板卡片
  Widget _buildTemplateCard(Map<String, dynamic> t, VoidCallback onDelete) {
    final name = t['templateName'] ?? '未命名';
    final actionType = t['actionType'] ?? '未知動作';
    final createdAt = t['createdAt'] ?? '';
    final createdShort =
        createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt;
    final reps = t['estimatedReps'] ?? 0;
    final sym = (t['symmetryScore'] ?? 0.0) as num;
    final sta = (t['stabilityScore'] ?? 0.0) as num;
    final frames = t['totalFrames'] ?? 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE0F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1D2E),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$actionType · $createdShort',
                      style:
                          TextStyle(color: Colors.grey.shade600, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon:
                    const Icon(Icons.delete_outline, color: Color(0xFFF44336)),
                onPressed: onDelete,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _miniChip('$reps 次', const Color(0xFF4CAF50)),
              _miniChip('對稱 ${(sym * 100).toStringAsFixed(0)}%',
                  const Color(0xFF4A65FF)),
              _miniChip('穩定 ${(sta * 100).toStringAsFixed(0)}%',
                  const Color(0xFFFF9800)),
              _miniChip('$frames 幀', const Color(0xFF6B7280)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  UI
  // ═══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final bool hasVideo = _selectedVideoPath != null;
    final String fileName = hasVideo ? _selectedVideoPath!.split('/').last : '';

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && _clientService.isConnected) {
          _clientService.sendCommand({'type': 'POP_SCREEN'});
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F6FA),
        appBar: AppBar(
          title: const Text('動作標準分析'),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1A1D2E),
          elevation: 0,
          leading: GestureDetector(
            onTap: () {
              // 🖥️ 電視投放新增:同步返回指令
              if (_clientService.isConnected) {
                _clientService.sendCommand({'type': 'POP_SCREEN'});
              }
              Navigator.of(context).pop();
            },
            child: const Icon(Icons.arrow_back_ios_new, size: 20),
          ),
        ),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '從治療師示範影片,建立動作標準模板',
                  style: TextStyle(
                      color: Color(0xFF1A1D2E),
                      fontSize: 16,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  '選內建影片 or 自己的影片 → 逐幀分析 → 儲存為模板(供病人比對)',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),

                // ── 查看已存模板按鈕 ──
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _showSavedTemplates,
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('查看已存模板',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF4A65FF),
                      side: const BorderSide(color: Color(0xFF4A65FF)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── 選擇分析類型 ──
                const Text(
                  '選擇分析類型',
                  style: TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                        child: _buildAnalysisTypeCard(
                      type: 'body',
                      icon: Icons.accessibility_new,
                      title: '全身動作',
                      subtitle: 'RTMPose 133 點',
                    )),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _buildAnalysisTypeCard(
                      type: 'hand',
                      icon: Icons.back_hand,
                      title: '手部動作',
                      subtitle: 'MediaPipe 21 點',
                    )),
                  ],
                ),

                const SizedBox(height: 24),

                // 選影片區塊
                GestureDetector(
                  onTap: _isAnalyzing ? null : _showVideoSourcePicker,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: hasVideo
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFFDDE0F0),
                        width: hasVideo ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          hasVideo
                              ? Icons.check_circle
                              : Icons.video_call_outlined,
                          color: hasVideo
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFF9CA3AF),
                          size: 48,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          hasVideo ? fileName : '點擊選擇影片',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 14,
                            fontWeight:
                                hasVideo ? FontWeight.w600 : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (hasVideo) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _isPreset
                                  ? const Color(0xFFE0E7FF)
                                  : const Color(0xFFE8F5E9),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${_isPreset ? "內建" : "自選"} · $_currentActionType',
                              style: TextStyle(
                                color: _isPreset
                                    ? const Color(0xFF4A65FF)
                                    : const Color(0xFF2E7D32),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // 分析按鈕
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed:
                        !hasVideo || _isAnalyzing ? null : _startAnalysis,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4A65FF),
                      disabledBackgroundColor: const Color(0xFFEDEFF7),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _isAnalyzing
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5),
                          )
                        : const Text('開始分析',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                  ),
                ),

                const SizedBox(height: 20),

                // 進度
                if (_isAnalyzing || _processedFrames > 0)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFDDE0F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('進度:$_processedFrames / $_totalFrames 幀',
                            style: const TextStyle(
                                color: Color(0xFF1A1D2E),
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text('成功偵測到骨架:$_framesWithPose 幀',
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 12)),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: _totalFrames == 0
                              ? 0
                              : _processedFrames / _totalFrames,
                          backgroundColor: const Color(0xFFEDEFF7),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFF4A65FF)),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 20),

                // 多維度分析結果
                if (_mainJointIndices.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFF4A65FF), width: 1.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.analytics,
                                color: Color(0xFF4A65FF), size: 18),
                            SizedBox(width: 6),
                            Text('動作特徵分析',
                                style: TextStyle(
                                    color: Color(0xFF1A1D2E),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text('偵測的主要活動關節',
                            style: TextStyle(
                                color: Color(0xFF6B7280),
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _mainJointIndices.map((idx) {
                            final movement = _jointTotalMovement[idx] ?? 0;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                  color: const Color(0xFFE0E7FF),
                                  borderRadius: BorderRadius.circular(20)),
                              child: Text(
                                '${_jointName(idx)} (${movement.toStringAsFixed(2)})',
                                style: const TextStyle(
                                    color: Color(0xFF4A65FF),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700),
                              ),
                            );
                          }).toList(),
                        ),
                        const Divider(height: 24),
                        _buildAngleStat('估算動作次數', '$_estimatedReps 次',
                            const Color(0xFF4CAF50)),
                        const SizedBox(height: 8),
                        _buildAngleStat(
                          '左右對稱性',
                          '${(_symmetryScore * 100).toStringAsFixed(0)}%',
                          _symmetryScore > 0.7
                              ? const Color(0xFF4CAF50)
                              : _symmetryScore > 0.4
                                  ? const Color(0xFFFF9800)
                                  : const Color(0xFFF44336),
                        ),
                        const SizedBox(height: 8),
                        _buildAngleStat(
                          '軀幹穩定性',
                          '${(_stabilityScore * 100).toStringAsFixed(0)}%',
                          _stabilityScore > 0.7
                              ? const Color(0xFF4CAF50)
                              : _stabilityScore > 0.4
                                  ? const Color(0xFFFF9800)
                                  : const Color(0xFFF44336),
                        ),
                        const SizedBox(height: 8),
                        _buildAngleStat('分析資料點', '${_framePoses.length} 幀',
                            const Color(0xFF6B7280)),
                        const SizedBox(height: 16),

                        // ── 儲存為模板按鈕 ──
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton.icon(
                            onPressed: _saveAsTemplate,
                            icon: const Icon(Icons.save_alt, size: 18),
                            label: const Text('儲存為模板',
                                style: TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w700)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4CAF50),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '💡 儲存後可作為病人動作比對的參考模板',
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                // ══════════════════════════════════════════════════════════════
                // 手部分析結果(僅在手部分析模式顯示)
                // ══════════════════════════════════════════════════════════════
                if (_handResult != null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFF4A65FF), width: 1.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── 標題 ──
                        const Row(
                          children: [
                            Icon(Icons.back_hand,
                                color: Color(0xFF4A65FF), size: 18),
                            SizedBox(width: 6),
                            Text(
                              '手部動作特徵分析',
                              style: TextStyle(
                                color: Color(0xFF1A1D2E),
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // ── 1. 主要活動手指 ──
                        const Text(
                          '主要活動手指',
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _handResult!.mainFingerIndices.map((idx) {
                            final movement =
                                _handResult!.fingerTotalMovement[idx] ?? 0;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE0E7FF),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${HandFeatureExtractor.fingerName(idx)} (${movement.toStringAsFixed(2)})',
                                style: const TextStyle(
                                  color: Color(0xFF4A65FF),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            );
                          }).toList(),
                        ),

                        const Divider(height: 24),

                        // ── 2. 動作次數 ──
                        _buildAngleStat(
                          '估算動作次數',
                          '${_handResult!.estimatedReps} 次',
                          const Color(0xFF4CAF50),
                        ),
                        const SizedBox(height: 8),

                        // ── 3. 動作規律性 ──
                        _buildAngleStat(
                          '動作規律性',
                          '${(_handResult!.regularityScore * 100).toStringAsFixed(0)}%',
                          _handResult!.regularityScore > 0.7
                              ? const Color(0xFF4CAF50)
                              : _handResult!.regularityScore > 0.4
                                  ? const Color(0xFFFF9800)
                                  : const Color(0xFFF44336),
                        ),
                        const SizedBox(height: 8),

                        // ── 4. 拇指-食指開合距離 ──
                        _buildAngleStat(
                          '開合距離範圍',
                          '${_handResult!.minPinchDistance.toStringAsFixed(3)} → '
                              '${_handResult!.maxPinchDistance.toStringAsFixed(3)}',
                          const Color(0xFF4A65FF),
                        ),
                        const SizedBox(height: 8),
                        _buildAngleStat(
                          '平均開合距離',
                          _handResult!.avgPinchDistance.toStringAsFixed(3),
                          const Color(0xFF6B7280),
                        ),
                        const SizedBox(height: 8),

                        // ── 5. 手腕旋轉角度 ──
                        _buildAngleStat(
                          '手腕旋轉角度範圍',
                          '${_handResult!.wristRotationRange.toStringAsFixed(1)}°',
                          const Color(0xFFFF9800),
                        ),
                        const SizedBox(height: 8),

                        // ── 6. 分析資料點 ──
                        _buildAngleStat(
                          '分析資料點',
                          '${_handResult!.totalFrames} 幀',
                          const Color(0xFF6B7280),
                        ),

                        const SizedBox(height: 12),

                        // ── 說明 ──
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F6FA),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '💡 手部復健指標:主要活動手指、動作次數、'
                            '開合幅度(側捏/抓握指標)、手腕旋轉(翻掌指標)、'
                            '動作規律性(復健穩定度)',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 11,
                              height: 1.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // ── 儲存為模板按鈕(手部) ──
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton.icon(
                            onPressed: _saveAsTemplate,
                            icon: const Icon(Icons.save_alt, size: 18),
                            label: const Text('儲存為手部模板',
                                style: TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w700)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4CAF50),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '💡 儲存後可作為手部訓練病人動作比對的參考模板',
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAngleStat(String label, String value, Color color) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
        ),
        Text(value,
            style: TextStyle(
                color: color, fontSize: 14, fontWeight: FontWeight.w800)),
      ],
    );
  }

  /// 分析類型切換卡
  Widget _buildAnalysisTypeCard({
    required String type,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final bool isSelected = _analysisType == type;
    return GestureDetector(
      onTap: _isAnalyzing
          ? null
          : () {
              setState(() {
                _analysisType = type;
                // 換類型時清空既有選擇
                _selectedVideoPath = null;
                _currentActionType = '';
                _resetAnalysisState();
                _handResult = null;
              });
            },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF4A65FF) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                isSelected ? const Color(0xFF4A65FF) : const Color(0xFFDDE0F0),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: isSelected ? Colors.white : const Color(0xFF6B7280),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: isSelected ? Colors.white : const Color(0xFF1A1D2E),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.8)
                    : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
