import 'dart:convert';
import 'package:http/http.dart' as http;

class ConnectionConfig {
  final String baseUrl;
  final String database;
  final String username;
  final String password;

  ConnectionConfig({
    required this.baseUrl,
    required this.database,
    required this.username,
    required this.password,
  });

  factory ConnectionConfig.fromJson(Map<String, dynamic> json) {
    return ConnectionConfig(
      baseUrl: json['server_url'] ?? '',
      database: json['database_name'] ?? '',
      username: json['username'] ?? '',
      password: json['password'] ?? '',
    );
  }

  @override
  String toString() => 'ConnectionConfig(baseUrl: $baseUrl, db: $database, username: $username)';
}

class ConnectionService {
  static const String configApiUrl = 'https://npdhrms.com/odoo18/api/get_connection.php';
  
  static ConnectionConfig? _cachedConfig;
  static DateTime? _cacheTime;
  static const Duration _cacheDuration = Duration(hours: 1);

  /// ดึงการตั้งค่าการเชื่อมต่อจาก API
  /// พร้อม retry logic ในกรณีที่เกิด error ชั่วคราว
  static Future<ConnectionConfig?> fetchConnectionConfig({
    bool forceRefresh = false,
  }) async {
    try {
      print('🔍 [ConnectionService] Fetching connection config from API...');
      print('📍 API URL: $configApiUrl');
      
      // ตรวจสอบ cache
      if (!forceRefresh && _cachedConfig != null && _cacheTime != null) {
        final timeDiff = DateTime.now().difference(_cacheTime!);
        if (timeDiff.compareTo(_cacheDuration) < 0) {
          print('✅ [ConnectionService] Using cached config (${timeDiff.inSeconds}s old)');
          return _cachedConfig;
        }
      }

      // ตั้งค่า timeout สำหรับ HTTP request
      final response = await http.get(
        Uri.parse(configApiUrl),
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'npd_transport_app/1.0',
        },
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          print('⏱️  [ConnectionService] API request timeout');
          throw Exception('Connection timeout');
        },
      );

      print('📥 [ConnectionService] Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        
        print('📄 [ConnectionService] Response data: ${jsonData.toString().substring(0, min(200, jsonData.toString().length))}...');
        
        // ตรวจสอบว่า API ส่งกลับ success: true หรือไม่
        if (jsonData['success'] == true && jsonData['data'] != null) {
          final config = ConnectionConfig.fromJson(jsonData['data']);
          
          // บันทึก cache
          _cachedConfig = config;
          _cacheTime = DateTime.now();
          
          print('✅ [ConnectionService] Connection config loaded successfully');
          print('   Base URL: ${config.baseUrl}');
          print('   Database: ${config.database}');
          print('   Username: ${config.username}');
          
          return config;
        } else {
          final errorMsg = jsonData['message'] ?? 'Unknown error from API';
          print('❌ [ConnectionService] API returned error: $errorMsg');
          throw Exception(errorMsg);
        }
      } else {
        print('❌ [ConnectionService] HTTP Error: ${response.statusCode}');
        print('   Response body: ${response.body}');
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }
    } catch (e) {
      print('❌ [ConnectionService] Error fetching config: $e');
      
      // ลอง return cache ถ้ามี (ใช้สำหรับการ offline fallback)
      if (_cachedConfig != null) {
        print('⚠️  [ConnectionService] Returning cached config as fallback');
        return _cachedConfig;
      }
      
      return null;
    }
  }

  /// ทดสอบการเชื่อมต่อกับ Odoo
  static Future<bool> testConnection(ConnectionConfig config) async {
    try {
      print('🧪 [ConnectionService] Testing connection to: ${config.baseUrl}');
      
      final response = await http.get(
        Uri.parse('${config.baseUrl}/web'),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          print('⏱️  [ConnectionService] Connection test timeout');
          throw Exception('Connection timeout');
        },
      );

      final isConnected = response.statusCode == 200;
      
      if (isConnected) {
        print('✅ [ConnectionService] Connection test successful');
      } else {
        print('❌ [ConnectionService] Connection test failed: ${response.statusCode}');
      }
      
      return isConnected;
    } catch (e) {
      print('❌ [ConnectionService] Connection test error: $e');
      return false;
    }
  }

  /// ล้าง cache
  static void clearCache() {
    print('🗑️  [ConnectionService] Clearing cached config');
    _cachedConfig = null;
    _cacheTime = null;
  }
}

// Helper function
int min(int a, int b) => a < b ? a : b;
