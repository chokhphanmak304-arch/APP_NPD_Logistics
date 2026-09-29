import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ConnectionConfig {
  final String baseUrl;
  final String database;
  final String username;
  final String password;

  const ConnectionConfig({
    required this.baseUrl,
    required this.database,
    required this.username,
    required this.password,
  });

  factory ConnectionConfig.fromJson(Map<String, dynamic> json) {
    return ConnectionConfig(
      // ค่าที่ตั้งใน Odoo มักติด / ปิดท้ายมาด้วย ถ้าไม่ตัดทิ้งที่นี่ URL ทุกเส้น
      // จะกลายเป็น //api/... ซึ่งบาง proxy จัดการไม่เหมือนกัน ตัดที่เดียวจบ
      baseUrl: (json['server_url'] ?? '')
          .toString()
          .replaceAll(RegExp(r'/+$'), ''),
      database: (json['database_name'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      password: (json['password'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'server_url': baseUrl,
        'database_name': database,
        'username': username,
        'password': password,
      };

  bool get isUsable =>
      baseUrl.isNotEmpty && database.isNotEmpty && username.isNotEmpty;

  @override
  String toString() =>
      'ConnectionConfig(baseUrl: $baseUrl, db: $database, username: $username)';
}

/// การตั้งค่าเชื่อมต่อ Odoo ของแอป
///
/// เดิมดึงจาก PHP (npdhrms.com/odoo18/api/get_connection.php) ทุกครั้งที่เปิดแอป
/// แปลว่า PHP ล่มเมื่อไหร่แอปเปิดไม่ได้เลย ทั้งที่ Odoo ยังปกติดี ตอนนี้ตัด
/// ตัวกลางออก ให้ Odoo เป็นเจ้าของค่านี้เอง
///
/// ปัญหาไก่กับไข่: จะถาม Odoo ได้ต้องรู้ที่อยู่ Odoo ก่อน ลำดับจึงเป็น
///   1. ใช้ค่าที่เคยจำไว้ (จาก Odoo รอบก่อน) ถ้าไม่มีก็ใช้ค่าที่ฝังมากับแอป
///   2. ล็อกอินด้วยค่านั้น
///   3. ขอค่าล่าสุดจาก Odoo แล้วจำไว้ใช้รอบหน้า
///
/// ผลคือแก้ค่าที่ Odoo แล้วจะมีผลกับเครื่องนั้นในการเปิดครั้งถัดไป ไม่ใช่ทันที
/// ซึ่งยอมรับได้ เพราะค่านี้แทบไม่เคยเปลี่ยน
class ConnectionService {
  /// ค่าที่ฝังมากับแอป — ใช้เฉพาะตอนยังไม่เคยคุยกับ Odoo สำเร็จสักครั้ง
  /// ค่านี้ตรงกับที่ระบบ PHP เดิมเคยส่งมา
  static const ConnectionConfig builtInConfig = ConnectionConfig(
    baseUrl: 'http://119.59.124.50:8070',
    database: 'NPD_Logistics',
    username: 'Npd_admin',
    password: '1234',
  );

  static const String _prefsKey = 'odoo_connection_config';

  static ConnectionConfig? _cachedConfig;

  /// ค่าที่ควรใช้ตอนนี้ — จากที่จำไว้ก่อน ถ้าไม่มีค่อยใช้ค่าที่ฝังมา
  ///
  /// ไม่ยิงเน็ตเลย จึงไม่มีทางค้างหรือล้มเหลวตอนเปิดแอป
  static Future<ConnectionConfig?> fetchConnectionConfig({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedConfig != null) return _cachedConfig;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final saved = ConnectionConfig.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
        if (saved.isUsable) {
          _cachedConfig = saved;
          print('OK [ConnectionService] ใช้ค่าที่จำไว้จาก Odoo: $saved');
          return saved;
        }
      }
    } catch (e) {
      // อ่านค่าที่จำไว้ไม่ได้ ไม่ใช่เรื่องคอขาดบาดตาย ใช้ค่าที่ฝังมาแทน
      print('[ConnectionService] อ่านค่าที่จำไว้ไม่ได้: $e');
    }

    _cachedConfig = builtInConfig;
    print('[ConnectionService] ใช้ค่าที่ฝังมากับแอป: $builtInConfig');
    return builtInConfig;
  }

  /// บันทึกค่าที่ได้จาก Odoo ไว้ใช้รอบหน้า
  ///
  /// เรียกหลังล็อกอินสำเร็จเท่านั้น ถ้าเขียนค่าผิดลงไปตอนยังไม่ยืนยันตัวตน
  /// แอปจะเปิดไม่ได้อีกเลยจนกว่าจะล้างข้อมูลแอป
  static Future<void> saveConfigFromOdoo(Map<String, dynamic> data) async {
    final config = ConnectionConfig.fromJson(data);
    if (!config.isUsable) {
      print('[ConnectionService] ค่าจาก Odoo ไม่ครบ ไม่บันทึกทับ');
      return;
    }
    if (config.toString() == _cachedConfig?.toString()) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(config.toJson()));
      _cachedConfig = config;
      print('OK [ConnectionService] บันทึกค่าใหม่จาก Odoo แล้ว: $config');
    } catch (e) {
      print('[ConnectionService] บันทึกค่าไม่สำเร็จ: $e');
    }
  }

  /// ทดสอบว่าต่อ Odoo ได้จริงไหม ก่อนปล่อยผู้ใช้เข้าหน้าล็อกอิน
  static Future<bool> testConnection(ConnectionConfig config) async {
    try {
      final response = await http
          .get(Uri.parse('${config.baseUrl}/web/login'))
          .timeout(const Duration(seconds: 10));
      // 200 = หน้าล็อกอิน, 303 = เด้งไปหน้าอื่น ทั้งคู่แปลว่าเซิร์ฟเวอร์ตอบอยู่
      final ok = response.statusCode == 200 || response.statusCode == 303;
      print('[ConnectionService] ทดสอบต่อ ${config.baseUrl} -> '
          '${response.statusCode} (${ok ? 'ผ่าน' : 'ไม่ผ่าน'})');
      return ok;
    } catch (e) {
      print('[ConnectionService] ต่อ ${config.baseUrl} ไม่ได้: $e');
      return false;
    }
  }

  /// ล้างค่าที่จำไว้ กลับไปใช้ค่าที่ฝังมากับแอป
  static Future<void> clearCache() async {
    _cachedConfig = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
    print('[ConnectionService] ล้างค่าที่จำไว้แล้ว');
  }
}
