import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'ui/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const WindowOptions windowOptions = WindowOptions(
    size: Size(900, 900),
    center: true,
    backgroundColor: Colors.black,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
    title: "Discord Cloud",
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setTitle("Discord Cloud");
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setResizable(false);
    // 종료 전 정리 작업을 위해 창 닫기 방지 활성화
    await windowManager.setPreventClose(true);
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Discord Cloud',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5865F2),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
