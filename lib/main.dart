import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/connection_verification_screen.dart';
import 'services/odoo_service.dart';

void main() async {
  // ✅ Initialize WidgetsBinding ก่อนใช้ SystemChrome
  WidgetsFlutterBinding.ensureInitialized();
  
  // 🔒 Lock orientation ให้เป็น Portrait เท่านั้น
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  
  // ✅ ขอสิทธิ์เข้าถึงตำแหน่งตั้งแต่เริ่มต้น (รอให้เสร็จ)
  await _requestInitialPermissions();
  
  // ✅ โหลด session จาก SharedPreferences ถ้ามี
  final odooService = OdooService();
  await odooService.loadSessionFromPrefs();
  
  runApp(const NPDTransportApp());
}

// ✅ ฟังก์ชันขออนุญาติตั้งแต่เริ่มต้น
Future<void> _requestInitialPermissions() async {
  try {
    print('🔐 [Main] Requesting initial permissions...');
    
    // ขออนุญาติกล้อง
    await Permission.camera.request();
    
    // ขออนุญาติเข้าถึงรูปภาพ
    await Permission.photos.request();
    
    // ขออนุญาติตำแหน่ง
    await Permission.location.request();
    
    // ขออนุญาติตำแหน่งพื้นหลัง (Android)
    await Permission.locationAlways.request();
    
    // ขออนุญาติแจ้งเตือน
    await Permission.notification.request();
    
    print('✅ [Main] Permission requests completed');
  } catch (e) {
    print('⚠️ [Main] Error requesting permissions: $e');
  }
}

class NPDTransportApp extends StatelessWidget {
  const NPDTransportApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NPD Logistics',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Kanit',
        primaryColor: const Color(0xFF2196F3),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2196F3),
          primary: const Color(0xFF2196F3),
          secondary: const Color(0xFFFF9800),
        ),
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: true,
      ),
      // ✅ แสดง ConnectionVerificationScreen ก่อน LoginScreen
      home: const ConnectionVerificationScreen(),
    );
  }
}
