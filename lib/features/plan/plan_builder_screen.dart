import 'package:flutter/material.dart';
import 'exercise.dart';
import 'rehab_plan.dart';

/// 治療師/使用者手動勾選動作、排序、設定組數的頁面
/// 骨折套用範本後可以來這裡微調；中風則直接從這裡從零開始安排
class PlanBuilderScreen extends StatefulWidget {
  final RehabPlan existingPlan;

  const PlanBuilderScreen({super.key, required this.existingPlan});

  @override
  State<PlanBuilderScreen> createState() => _PlanBuilderScreenState();
}

class _PlanBuilderScreenState extends State<PlanBuilderScreen> {
  late List<PlanItem> selectedItems;

  @override
  void initState() {
    super.initState();
    // 複製一份，避免直接改到原本的物件，取消時可以安全丟棄
    selectedItems = widget.existingPlan.items
        .map((i) => PlanItem(
              exerciseId: i.exerciseId,
              order: i.order,
              sets: i.sets,
              repsPerSet: i.repsPerSet,
              done: i.done,
            ))
        .toList();
  }

  bool _isSelected(String exerciseId) =>
      selectedItems.any((i) => i.exerciseId == exerciseId);

  void _toggleExercise(Exercise exercise) {
    setState(() {
      if (_isSelected(exercise.id)) {
        selectedItems.removeWhere((i) => i.exerciseId == exercise.id);
        _reorder();
      } else {
        selectedItems.add(PlanItem(
          exerciseId: exercise.id,
          order: selectedItems.length,
        ));
      }
    });
  }

  void _reorder() {
    for (int i = 0; i < selectedItems.length; i++) {
      selectedItems[i].order = i;
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = selectedItems.removeAt(oldIndex);
      selectedItems.insert(newIndex, item);
      _reorder();
    });
  }

  void _updateSets(String exerciseId, int sets) {
    setState(() {
      final item = selectedItems.firstWhere((i) => i.exerciseId == exerciseId);
      item.sets = sets.clamp(1, 10);
    });
  }

  void _updateReps(String exerciseId, int reps) {
    setState(() {
      final item = selectedItems.firstWhere((i) => i.exerciseId == exerciseId);
      item.repsPerSet = reps.clamp(1, 30);
    });
  }

  void _save() {
    final newPlan = RehabPlan(
      planId: widget.existingPlan.planId,
      createdBy: widget.existingPlan.createdBy,
      date: widget.existingPlan.date,
      condition: widget.existingPlan.condition,
      items: selectedItems,
    );
    Navigator.pop(context, newPlan);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('已選動作（可拖曳排序）'),
                    const SizedBox(height: 12),
                    _buildSelectedList(),
                    const SizedBox(height: 24),
                    _buildSectionTitle('手部動作'),
                    const SizedBox(height: 12),
                    _buildExerciseGrid(ExerciseCategory.hand),
                    const SizedBox(height: 24),
                    _buildSectionTitle('全身動作'),
                    const SizedBox(height: 12),
                    _buildExerciseGrid(ExerciseCategory.fullBody),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDDE0F0)),
              ),
              child: const Icon(Icons.close, color: Color(0xFF374151), size: 18),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              '安排訓練動作',
              style: TextStyle(color: Color(0xFF1A1D2E), fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          GestureDetector(
            onTap: selectedItems.isEmpty ? null : _save,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: selectedItems.isEmpty ? const Color(0xFFDDE0F0) : const Color(0xFF4A65FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('儲存', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String text) {
    return Text(text,
        style: const TextStyle(color: Color(0xFF1A1D2E), fontSize: 16, fontWeight: FontWeight.w800));
  }

  Widget _buildSelectedList() {
    if (selectedItems.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFDDE0F0)),
        ),
        child: const Text('尚未選擇動作，請從下方勾選',
            style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
      );
    }

    final sorted = [...selectedItems]..sort((a, b) => a.order.compareTo(b.order));

    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      onReorder: _onReorder,
      children: sorted.map((item) {
        final exercise = findExerciseById(item.exerciseId);
        return Container(
          key: ValueKey(item.exerciseId),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF4A65FF).withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.drag_handle, color: Color(0xFF9CA3AF), size: 20),
              const SizedBox(width: 8),
              Text(exercise.icon, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(exercise.name,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              _stepperField('組', item.sets, (v) => _updateSets(item.exerciseId, v)),
              const SizedBox(width: 8),
              _stepperField('下', item.repsPerSet, (v) => _updateReps(item.exerciseId, v)),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: Color(0xFF9CA3AF)),
                onPressed: () => _toggleExercise(exercise),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _stepperField(String label, int value, ValueChanged<int> onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => onChanged(value - 1),
          child: const Icon(Icons.remove_circle_outline, size: 18, color: Color(0xFF9CA3AF)),
        ),
        SizedBox(
          width: 28,
          child: Text('$value$label', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
        ),
        GestureDetector(
          onTap: () => onChanged(value + 1),
          child: const Icon(Icons.add_circle_outline, size: 18, color: Color(0xFF4A65FF)),
        ),
      ],
    );
  }

  Widget _buildExerciseGrid(ExerciseCategory category) {
    final exercises = exerciseLibrary.where((e) => e.category == category).toList();
    return Column(
      children: exercises.map((exercise) {
        final selected = _isSelected(exercise.id);
        return GestureDetector(
          onTap: () => _toggleExercise(exercise),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFFF0F2FF) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? const Color(0xFF4A65FF) : const Color(0xFFDDE0F0),
              ),
            ),
            child: Row(
              children: [
                Text(exercise.icon, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(exercise.name,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      Text('${exercise.level} · ${exercise.defaultMinutes} 分鐘',
                          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
                    ],
                  ),
                ),
                Icon(
                  selected ? Icons.check_circle : Icons.circle_outlined,
                  color: selected ? const Color(0xFF4A65FF) : const Color(0xFFDDE0F0),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}