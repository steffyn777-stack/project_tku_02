// lib/features/analysis/comparison_report_screen.dart
//
// ══════════════════════════════════════════════════════════════════
//  動作品質報告畫面
//
//  顯示:病人動作 vs 治療師模板 的比對結果
//    - 綜合相似度 + 等級
//    - 各項分數(次數、對稱、穩定、關節重合)
//    - 各項差異(病人 - 模板)
//    - 文字建議
//
//  使用方式:
//    Navigator.push → ComparisonReportScreen(
//      patientResult: ...,
//      templateJson: ...,
//    )
// ══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import 'comparison_service.dart';
import 'motion_feature_extractor.dart';

class ComparisonReportScreen extends StatelessWidget {
  final MotionAnalysisResult patientResult;
  final Map<String, dynamic> templateJson;
  final String? patientVideoPath;   // 選用:病人錄影檔路徑

  const ComparisonReportScreen({
    super.key,
    required this.patientResult,
    required this.templateJson,
    this.patientVideoPath,
  });

  @override
  Widget build(BuildContext context) {
    // 執行比對
    final result = ComparisonService.compare(
      patientResult: patientResult,
      templateJson: templateJson,
    );

    final templateName = templateJson['templateName'] ?? '治療師標準模板';
    final actionType = templateJson['actionType'] ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('動作品質報告'),
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
                  const Icon(Icons.compare_arrows,
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
            _buildScoreItem('左右對稱性', result.symmetryScore,
                _symDetail(result)),
            const SizedBox(height: 8),
            _buildScoreItem('軀幹穩定性', result.stabilityScore,
                _staDetail(result)),
            const SizedBox(height: 8),
            _buildScoreItem('主要活動關節符合度',
                result.jointOverlapScore, '前 5 活動關節的重合程度'),
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

  Widget _buildOverallCard(ComparisonResult r) {
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
            '綜合相似度',
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

  Widget _buildPatientSummary(MotionAnalysisResult r) {
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
            '主要活動關節',
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
            children: r.mainJointIndices.map((idx) {
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E7FF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  MotionFeatureExtractor.jointName(idx),
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
          _mini('對稱性',
              '${(r.symmetryScore * 100).toStringAsFixed(0)}%'),
          const SizedBox(height: 6),
          _mini('穩定性',
              '${(r.stabilityScore * 100).toStringAsFixed(0)}%'),
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

  String _repsDetail(ComparisonResult r) {
    if (r.repsDiff == 0) return '次數與治療師相同';
    if (r.repsDiff > 0) return '比治療師多 ${r.repsDiff} 次';
    return '比治療師少 ${r.repsDiff.abs()} 次';
  }

  String _symDetail(ComparisonResult r) {
    final diff = r.symmetryDiff;
    if (diff.abs() < 3) return '與治療師相近';
    if (diff > 0) {
      return '對稱性優於治療師 ${diff.toStringAsFixed(0)}%';
    }
    return '對稱性低於治療師 ${diff.abs().toStringAsFixed(0)}%';
  }

  String _staDetail(ComparisonResult r) {
    final diff = r.stabilityDiff;
    if (diff.abs() < 3) return '與治療師相近';
    if (diff > 0) {
      return '穩定性優於治療師 ${diff.toStringAsFixed(0)}%';
    }
    return '穩定性低於治療師 ${diff.abs().toStringAsFixed(0)}%';
  }
}