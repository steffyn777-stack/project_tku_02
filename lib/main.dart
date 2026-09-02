import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';   // ← 新增
//import 'features/home/home_screen.dart';
import 'features/splash/splash_screen.dart';
import 'features/notification/notification_service.dart';

import 'package:provider/provider.dart';
import 'services/history_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  await NotificationService().init();
  //runApp(const RehabAssistApp());
  runApp(
    ChangeNotifierProvider(
      create: (_) => HistoryService(),
      child: const RehabAssistApp(),
    ),
  );
}

class RehabAssistApp extends StatelessWidget {
  const RehabAssistApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RehabAssist',
      debugShowCheckedModeBanner: false,
      // ↓ 新增這三塊
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh', 'TW'),
        Locale('en', 'US'),
      ],
      locale: const Locale('zh', 'TW'),
      // ↑ 新增結束
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4A65FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      //home: const HomeScreen(),
      home: const SplashScreen(),
    );
  }
}