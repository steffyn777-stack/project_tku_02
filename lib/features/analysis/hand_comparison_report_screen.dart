// lib/features/analysis/hand_comparison_report_screen.dart
//
// ══════════════════════════════════════════════════════════════════
//  手部動作品質報告畫面
//
//  顯示:病人手部動作 vs 治療師手部模板 比對結果
// ══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import 'hand_comparison_service.dart';
import 'hand_feature_extractor.dart';

class HandComparisonReportScreen extends StatelessWidget {
  final HandAnalysisResult patientResult;
  final Map<String, dynamic> templateJson;
  final String? patientVideoPath;

  const HandComparisonReportScreen({
    super.key,
    required this.patientResult,
    required this.templateJson,
    this.patientVideoPath,
  });

  @override
  Widget build(BuildContext context) {
    final result = HandComparisonService.compare(
      patientResult: patientResult,
      templateJson: templateJson,
    );

    final templateName = templateJson['templateName'] ?? '手部標準模板';
    final actionType = templateJson['actionType'] ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('手部動作品質報告'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1D2E),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 對比對象標籤 ──
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDDE0F0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.back_hand,
                      color: Color(0xFF4A65FF), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '對比模板:$templateName',
                          style: const TextStyle(
                            color: Color(0xFF1A1D2E),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (actionType.toString().isNotEmpty)
                          Text(
                            '動作類型:$actionType',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── 綜合相似度大卡片 ──
            _buildOverallCard(result),
            const SizedBox(height: 20),

            // ── 分項評分 ──
            _buildSectionTitle('分項評分'),
            const SizedBox(height: 10),
            _buildScoreItem('動作次數', result.repsScore, _repsDetail(result)),
            const SizedBox(height: 8),
            _buildScoreItem('手指開合幅度', result.pinchRangeScore,
                _pinchDetail(result)),
            const SizedBox(height: 8),
            _buildScoreItem('手腕旋轉範圍', result.wristRotationScore,
                _wristDetail(result)),
            const SizedBox(height: 8),
            _buildScoreItem('動作規律性', result.regularityScore,
                _regularityDetail(result)),
            const SizedBox(height: 8),
            _buildScoreItem('主要活動手指符合度', result.fingerOverlapScore,
                '前 3 活動手指的重合程度'),
            const SizedBox(height: 24),

            // ── 建議清單 ──
            _buildSectionTitle('分析建議'),
            const SizedBox(height: 10),
            ...result.suggestions.map((tip) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFDDE0F0)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(Icons.lightbulb_outline,
                              color: Color(0xFFFF9800), size: 18),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tip,
                            style: TextStyle(
                              color: Colors.grey.shade800,
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )),

            const SizedBox(height: 24),

            // ── 病人特徵摘要 ──
            _buildSectionTitle('本次訓練特徵'),
            const SizedBox(height: 10),
            _buildPatientSummary(patientResult),

            const SizedBox(height: 32),

            // ── 返回按鈕 ──
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.check),
                label: const Text('完成',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A65FF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════

  Widget _buildOverallCard(HandComparisonResult r) {
    final color = _scoreColor(r.overallScore);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            '手部動作綜合相似度',
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                r.overallScore.toStringAsFixed(0),
                style: TextStyle(
                  color: color,
                  fontSize: 56,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '/ 100',
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              r.grade,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreItem(String label, double score, String detail) {
    final color = _scoreColor(score);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE0F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF1A1D2E),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${score.toStringAsFixed(0)} 分',
                style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (score / 100).clamp(0.0, 1.0),
              backgroundColor: const Color(0xFFEDEFF7),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF1A1D2E),
        fontSize: 15,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _buildPatientSummary(HandAnalysisResult r) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE0F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
            children: r.mainFingerIndices.map((idx) {
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E7FF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  HandFeatureExtractor.fingerName(idx),
                  style: const TextStyle(
                    color: Color(0xFF4A65FF),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            }).toList(),
          ),
          const Divider(height: 20),
          _mini('動作次數', '${r.estimatedReps} 次'),
          const SizedBox(height: 6),
          _mini('開合幅度',
              '${r.minPinchDistance.toStringAsFixed(3)} → ${r.maxPinchDistance.toStringAsFixed(3)}'),
          const SizedBox(height: 6),
          _mini('手腕旋轉範圍', '${r.wristRotationRange.toStringAsFixed(1)}°'),
          const SizedBox(height: 6),
          _mini('動作規律性',
              '${(r.regularityScore * 100).toStringAsFixed(0)}%'),
        ],
      ),
    );
  }

  Widget _mini(String label, String value) {
    return Row(
      children: [
        Text(label,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
        const Spacer(),
        Text(value,
            style: const TextStyle(
                color: Color(0xFF1A1D2E),
                fontSize: 13,
                fontWeight: FontWeight.w700)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  Helpers
  // ═══════════════════════════════════════════════════════════════

  Color _scoreColor(double score) {
    if (score >= 80) return const Color(0xFF4CAF50);
    if (score >= 60) return const Color(0xFF4A65FF);
    if (score >= 40) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
  }

  String _repsDetail(HandComparisonResult r) {
    if (r.repsDiff == 0) return '次數與治療師相同';
    if (r.repsDiff > 0) return '比治療師多 ${r.repsDiff} 次';
    return '比治療師少 ${r.repsDiff.abs()} 次';
  }

  String _pinchDetail(HandComparisonResult r) {
    final diff = r.pinchRangeDiff;
    if (diff.abs() < 0.02) return '與治療師相近';
    if (diff > 0) {
      return '開合幅度優於治療師 ${diff.toStringAsFixed(2)}';
    }
    return '開合幅度不足 ${diff.abs().toStringAsFixed(2)}';
  }

  String _wristDetail(HandComparisonResult r) {
    final diff = r.wristRotationDiff;
    if (diff.abs() < 5) return '與治療師相近';
    if (diff > 0) {
      return '手腕旋轉範圍優於治療師 ${diff.toStringAsFixed(0)}°';
    }
    return '手腕旋轉範圍不足 ${diff.abs().toStringAsFixed(0)}°';
  }

  String _regularityDetail(HandComparisonResult r) {
    final diff = r.regularityDiff;
    if (diff.abs() < 3) return '與治療師相近';
    if (diff > 0) {
      return '規律性優於治療師 ${diff.toStringAsFixed(0)}%';
    }
    return '規律性低於治療師 ${diff.abs().toStringAsFixed(0)}%';
  }
}