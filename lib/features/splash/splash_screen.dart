// lib/features/splash/splash_screen.dart
//
// ══════════════════════════════════════════════════════════════════
//  自訂 Splash 畫面
//
//  流程:
//    1. Android native splash 顯示白底 0.3 秒
//    2. app 起來 → 進入 SplashScreen(這個檔)
//    3. 全屏顯示 splash.png(內含裝飾用進度條)1.5 秒
//    4. 自動跳到首頁
//
//  說明:
//    - 進度條是 splash.png 圖上的裝飾,不會動
//    - 這是最省事的做法,跟 Netflix 首屏設計理念一致
// ══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../home/home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // 1.5 秒後跳首頁
    Future.delayed(const Duration(milliseconds: 1500), _goHome);
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Positioned.fill(
        child: Image.asset(
          'assets/splash/splash.png',
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}