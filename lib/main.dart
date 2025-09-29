import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'pages/home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 앱 시작 시 갤러리 권한 요청
  await _requestPermissions();
  
  runApp(const MyApp());
}

/// 앱 시작 시 필요한 권한 요청
Future<void> _requestPermissions() async {
  try {
    // 갤러리 접근 권한 확인 및 요청
    final hasAccess = await Gal.hasAccess();
    if (!hasAccess) {
      await Gal.requestAccess();
      print('📸 갤러리 권한 요청 완료');
    } else {
      print('✅ 갤러리 권한 이미 허용됨');
    }
  } catch (e) {
    print('⚠️ 갤러리 권한 요청 실패: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI PCB Inspector',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.green)),
      home: const HomePage(),
       debugShowCheckedModeBanner: false,
    );
  }
}
 
