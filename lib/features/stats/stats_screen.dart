// lib/features/stats/stats_screen.dart
//
// 數據分頁 — B+C 混搭空殼:
//   上半 · 弱點分析(雷達圖 + 錯誤分佈)
//   下半 · 激勵回饋(成就徽章 + 個人紀錄 + 週對比)
// 目前全部是佔位,等資料層接上再填。

import 'package:flutter/material.dart';
import 'radar_chart_card.dart';
import 'personal_records_card.dart';
import 'week_summary_card.dart';
import 'badges_card.dart';
import 'progress_trend_card.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTopBar(),
              const SizedBox(height: 20),
              const WeekSummaryCard(),
              const SizedBox(height: 28),
              _buildSectionTitle('弱點分析', '看看哪些動作還可以進步'),
              const SizedBox(height: 12),
              const RadarChartCard(),
              const SizedBox(height: 12),
              const ProgressTrendCard(),
              const SizedBox(height: 28),
              _buildSectionTitle('成就與紀錄', '你的努力都被記下來了'),
              const SizedBox(height: 12),
              const BadgesCard(),
              const SizedBox(height: 12),
              const PersonalRecordsCard(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ─── 頂部標題 ─────────────────────────────────────────
  Widget _buildTopBar() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '數據',
          style: TextStyle(
            color: Color(0xFF1A1D2E),
            fontSize: 26,
            fontWeight: FontWeight.w900,
            height: 1.1,
          ),
        ),
        SizedBox(height: 4),
        Text(
          '你的復健表現一目了然',
          style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
        ),
      ],
    );
  }

  // ─── Section 標題 ─────────────────────────────────────
  Widget _buildSectionTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF1A1D2E),
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11),
        ),
      ],
    );
  }
}