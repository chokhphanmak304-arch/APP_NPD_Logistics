import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/driver.dart';
import '../models/booking.dart';
import '../models/delivery_history.dart';
import '../models/income_data.dart';
import 'connection_service.dart';
import 'odoo_config_holder.dart';

class OdooService {
  // ✅ ใช้ dynamic configuration แทน hardcoded values
  late String _baseUrl;
  late String _db;
  late String _username;
  late String _password;

  int? _uid;
  String? _sessionId;
  DateTime? _sessionExpiryTime;  // 🔐 เก็บเวลาหมดอายุ session

  // ✅ Constructor ที่ดึง config จาก singleton
  OdooService() {
    final holder = OdooConfigHolder.getInstance();
    final config = holder.getConfig();
    
    if (config != null) {
      _baseUrl = config.baseUrl;
      _db = config.database;
      _username = config.username;
      _password = config.password;
      print('✅ [OdooService] Constructor: Loaded config from singleton');
      print('   Base URL: $_baseUrl');
      print('   Database: $_db');
    } else {
      // ⚠️ Fallback (should not happen if flow is correct)
      print('⚠️ [OdooService] Constructor: No config in singleton, using defaults');
      _baseUrl = 'http://localhost:8078';
      _db = 'Npd_Transport';
      _username = 'Npd_admin';
      _password = '1234';
    }
    
    // ✅ Do NOT initialize authentication here
    // It will be called in loginWithPin() when user enters PIN
    print('✅ [OdooService] Ready for loginWithPin()');
  }

  // ✅ โหลด session ที่บันทึกไว้ (persistent) - เรียกใน initState แบบ async
  Future<void> loadSessionFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('odoo_session_id');
      final uid = prefs.getInt('odoo_uid');
      final expiryStr = prefs.getString('odoo_session_expiry');
      
      if (sessionId != null && uid != null && expiryStr != null) {
        _sessionId = sessionId;
        _uid = uid;
        _sessionExpiryTime = DateTime.parse(expiryStr);
        
        if (_isSessionValid()) {
          print('✅ [OdooService] Loaded valid session from SharedPreferences');
          print('   UID: $_uid');
          print('   Session expires: $_sessionExpiryTime');
        } else {
          print('🔐 [OdooService] Saved session expired, clearing...');
          _sessionId = null;
          _uid = null;
          _sessionExpiryTime = null;
          // ล้างค่าจาก SharedPreferences
          await prefs.remove('odoo_session_id');
          await prefs.remove('odoo_uid');
          await prefs.remove('odoo_session_expiry');
        }
      } else {
        print('ℹ️  [OdooService] No saved session found in SharedPreferences');
      }
    } catch (e) {
      print('⚠️  [OdooService] Failed to load session from SharedPreferences: $e');
    }
  }

  // ✅ ตรวจสอบว่า session ยังใช้ได้หรือไม่
  bool _isSessionValid() {
    if (_sessionId == null || _sessionExpiryTime == null) {
      return false;
    }
    
    // ถ้า session หมดอายุแล้ว
    if (DateTime.now().isAfter(_sessionExpiryTime!)) {
      print('🔐 [Session] Expired at: $_sessionExpiryTime');
      _sessionId = null;
      _sessionExpiryTime = null;
      return false;
    }
    
    return true;
  }

  // ✅ ตรวจสอบและ re-authenticate ถ้าต้อง
  Future<void> _ensureAuthenticated() async {
    if (!_isSessionValid()) {
      print('🔐 [Session] Invalid or expired, re-authenticating...');
      await authenticate();
    }
  }

  // ✅ Refresh session ถ้าใกล้หมดอายุ (ใช้ก่อนการถ่ายภาพ)
  Future<void> refreshSessionIfNeeded() async {
    try {
      if (_sessionExpiryTime == null) {
        print('🔐 [Session] No expiry time, re-authenticating...');
        await authenticate();
        return;
      }
      
      // ถ้า session จะหมดอายุใน 5 นาที ให้ refresh
      final now = DateTime.now();
      final timeUntilExpiry = _sessionExpiryTime!.difference(now);
      
      if (timeUntilExpiry.inMinutes < 5) {
        print('🔐 [Session] Expiring in ${timeUntilExpiry.inMinutes} minutes, refreshing...');
        await authenticate();
      } else {
        print('✅ [Session] Still valid for ${timeUntilExpiry.inMinutes} minutes');
      }
    } catch (e) {
      print('⚠️ [Session] Refresh failed: $e');
      // ไม่ throw error เพราะอาจทำให้แอปเด้ง
    }
  }

  // 🎨 แปลง DateTime เป็น Odoo format (YYYY-MM-DD HH:MM:SS)
  String _formatDateTimeForOdoo(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  /// ✅ ตั้งค่า connection configuration
  /// เรียกใช้ก่อนเขียง login หรือ operation อื่นๆ
  Future<bool> setConnectionConfig(ConnectionConfig config) async {
    try {
      print('🔧 [OdooService] Setting connection config...');
      _baseUrl = config.baseUrl;
      _db = config.database;
      _username = config.username;
      _password = config.password;
      
      print('✅ [OdooService] Config set:');
      print('   Base URL: $_baseUrl');
      print('   Database: $_db');
      print('   Username: $_username');
      
      return true;
    } catch (e) {
      print('❌ [OdooService] Error setting config: $e');
      return false;
    }
  }

  /// ✅ ดึง connection config จาก API และตั้งค่า
  Future<bool> initializeFromApi() async {
    try {
      print('🔄 [OdooService] Initializing from API...');
      final config = await ConnectionService.fetchConnectionConfig();
      
      if (config == null) {
        print('❌ [OdooService] Failed to fetch config from API');
        return false;
      }
      
      return await setConnectionConfig(config);
    } catch (e) {
      print('❌ [OdooService] Error initializing from API: $e');
      return false;
    }
  }

  Future<bool> authenticate() async {
    try {
      print('🔐 [OdooService.authenticate] ========== STARTING AUTHENTICATION ==========');
      print('   URL: $_baseUrl/web/session/authenticate');
      print('   DB: $_db');
      print('   Username: $_username');
      print('   Password: ${_password.replaceAll(RegExp(r'.'), '*')}');
      
      final url = Uri.parse('$_baseUrl/web/session/authenticate');
      final body = jsonEncode({
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {
          'db': _db,
          'login': _username,
          'password': _password,
        },
        'id': 1,
      });
      
      print('📤 [OdooService.authenticate] Sending request to: $url');
      print('📋 [OdooService.authenticate] Request body: $body');
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: body,
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          print('⏱️  [OdooService.authenticate] Request timeout');
          throw Exception('Authentication request timeout');
        },
      );

      print('📥 [OdooService.authenticate] Response status: ${response.statusCode}');
      print('📥 [OdooService.authenticate] Response headers: ${response.headers}');
      print('📥 [OdooService.authenticate] Response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('✓ [OdooService.authenticate] Parsed response: $data');
        
        // ✅ ตรวจสอบ error ใน JSON response
        if (data['error'] != null) {
          final error = data['error'];
          print('❌ [OdooService.authenticate] JSON-RPC Error:');
          print('   Code: ${error['code']}');
          print('   Message: ${error['message']}');
          if (error['data'] != null) {
            print('   Data: ${error['data']}');
          }
          return false;
        }
        
        // ✅ ตรวจสอบผลลัพธ์
        if (data['result'] != null && data['result']['uid'] != null) {
          _uid = data['result']['uid'];
          print('✅ [OdooService.authenticate] Got UID: $_uid');
          
          // ✅ ดึง session_id จาก cookie
          final cookies = response.headers['set-cookie'];
          if (cookies != null) {
            print('📝 [OdooService.authenticate] Cookies: $cookies');
            final sessionCookie = cookies.split(';').firstWhere(
              (cookie) => cookie.contains('session_id='),
              orElse: () => '',
            );
            if (sessionCookie.isNotEmpty) {
              _sessionId = sessionCookie.split('=').skip(1).join('=').trim();
              // 🔐 เก็บเวลาหมดอายุ (7 วัน)
              _sessionExpiryTime = DateTime.now().add(Duration(days: 7));
              print('✅ [OdooService.authenticate] Got session_id: $_sessionId');
              print('🔐 [OdooService.authenticate] Session expires at: $_sessionExpiryTime');
              
              // ✅ เก็บ session ลง SharedPreferences (persistent)
              try {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('odoo_session_id', _sessionId!);
                await prefs.setInt('odoo_uid', _uid!);
                await prefs.setString('odoo_session_expiry', _sessionExpiryTime!.toIso8601String());
                print('💾 [OdooService.authenticate] Session saved to SharedPreferences');
              } catch (e) {
                print('⚠️  [OdooService.authenticate] Failed to save session: $e');
              }
            }
          }
          
          print('🔐 [OdooService.authenticate] ========== AUTHENTICATION SUCCESSFUL ==========');
          return true;
        } else {
          print('❌ [OdooService.authenticate] No UID in response');
          print('   Result: ${data['result']}');
          return false;
        }
      } else {
        print('❌ [OdooService.authenticate] HTTP Status Error: ${response.statusCode}');
        print('   Reason: ${response.reasonPhrase}');
        print('   Body: ${response.body}');
        return false;
      }
    } catch (e) {
      print('❌ [OdooService.authenticate] Exception: $e');
      print('   Type: ${e.runtimeType}');
      print('   Stack: ${StackTrace.current}');
      return false;
    }
  }

  Future<Driver?> loginWithPin(String pin) async {
    try {
      print('🔐 [OdooService.loginWithPin] Starting login with PIN: $pin');
      
      // ✅ ตรวจสอบ configuration ก่อน
      if (_baseUrl.isEmpty || _db.isEmpty) {
        print('❌ [OdooService.loginWithPin] Configuration incomplete');
        print('   _baseUrl: $_baseUrl');
        print('   _db: $_db');
        return null;
      }
      
      // ✅ Authenticate หากยังไม่ได้ทำ
      if (_uid == null) {
        print('🔐 [OdooService.loginWithPin] No UID, authenticating...');
        final authSuccess = await authenticate();
        if (!authSuccess) {
          print('❌ [OdooService.loginWithPin] Authentication failed');
          return null;
        }
        print('✅ [OdooService.loginWithPin] Authentication successful, UID: $_uid');
      }

      // ✅ ค้นหา driver ด้วย PIN
      print('🔍 [OdooService.loginWithPin] Searching driver with PIN: $pin');
      
      final response = await http.post(
        Uri.parse('$_baseUrl/web/dataset/call_kw'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'model': 'vehicle.driver',
            'method': 'search_read',
            'args': [
              [
                ['pin', '=', pin],
                ['active', '=', true]
              ]
            ],
            'kwargs': {
              'fields': [
                'id',
                'name',
                'code',
                'pin',
                'phone',
                'email',
                'active',
                'employment_status',
                'license_number',
                'license_type',
                'branch_id'
              ],
            },
          },
          'id': 2,
        }),
      );

      print('📥 [OdooService.loginWithPin] Response status: ${response.statusCode}');
      print('📄 [OdooService.loginWithPin] Response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // ✅ ตรวจสอบ error จาก Odoo
        if (data['error'] != null) {
          final error = data['error'];
          final errorMsg = error['data']?['message'] ?? error['message'] ?? 'Unknown error';
          print('❌ [OdooService.loginWithPin] Odoo Error: $errorMsg');
          if (error['data']?['debug'] != null) {
            print('🐛 [OdooService.loginWithPin] Debug: ${error['data']['debug']}');
          }
          return null;
        }
        
        // ✅ ตรวจสอบผลลัพธ์
        if (data['result'] != null && data['result'].isNotEmpty) {
          final driverData = data['result'][0];
          print('✅ [OdooService.loginWithPin] Driver found: ${driverData['name']}');
          return Driver.fromJson(driverData);
        } else {
          print('⚠️  [OdooService.loginWithPin] No driver found with PIN: $pin');
          return null;
        }
      } else {
        print('❌ [OdooService.loginWithPin] HTTP Error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ [OdooService.loginWithPin] Error: $e');
      print('   Stack trace: ${e.toString()}');
      return null;
    }
  }

  Future<List<Booking>> getDriverBookings(int driverId) async {
    try {
      print('🔄 [OdooService] Getting bookings for driver: $driverId');
      
      if (_uid == null) {
        print('⚠️  [OdooService] No UID, authenticating...');
        final authSuccess = await authenticate();
        if (!authSuccess) {
          print('❌ [OdooService] Authentication failed');
          return [];
        }
        print('✅ [OdooService] Authentication successful, UID: $_uid');
      }

      print('📤 [OdooService] Sending request to Odoo API...');
      
      // ✅ คำนวณวันเวลาปัจจุบัน (รวมเวลา)
      final now = DateTime.now();
      final nowStr = now.toIso8601String();
      
      print('📅 [OdooService] Current datetime: $nowStr');
      
      final response = await http.post(
        Uri.parse('$_baseUrl/web/dataset/call_kw'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'model': 'vehicle.booking',
            'method': 'search_read',
            'args': [
              [
                ['driver_id', '=', driverId],
                // ✅ แสดงทั้งสถานะ "ยืนยันการจอง" และ "กำลังขนส่ง"
                ['state', 'in', ['confirmed', 'in_progress']],
                // ✅ เงื่อนไข: แสดงงานที่วางแผน <= เวลาปัจจุบัน หรือไม่มีวันที่วางแผน
                '|',  // OR operator
                ['planned_start_date', '=', false],  // หรือไม่มีวันที่วางแผน
                ['planned_start_date', '<=', nowStr],  // หรือวันเวลาที่วางแผน <= ปัจจุบัน
              ]
            ],
            'kwargs': {
              'fields': [
                'id',
                'name',
                'state',
                'pickup_location',
                'destination',
                'distance_km',
                'shipping_cost',
                'total_weight_order', // ✅ เพิ่มน้ำหนักรวม
                'partner_id',
                'delivery_employee_name',
                'planned_start_date',
                'planned_end_date',
                'planned_start_date_t',  // ✅ เพิ่มเวลาออกเดินทางจริง
                'planned_end_date_t',    // ✅ เพิ่มเวลาส่งถึงจริง
                'vehicle_id',
                'note',
                'travel_expenses', // ✅ เพิ่มค่าเที่ยว
                'daily_allowance', // ✅ เพิ่มค่าเบี้ยเลี้ยง
                'estimated_time', // ✅ เพิ่มเวลาโดยประมาณ
                // ✅ เพิ่มพิกัด GPS
                'pickup_latitude',
                'pickup_longitude',
                'destination_latitude',
                'destination_longitude',
              ],
              'order': 'planned_start_date asc',
            },
          },
          'id': 3,
        }),
      );

      print('📥 [OdooService] Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('📦 [OdooService] Response data: ${data.toString().substring(0, min(200, data.toString().length))}...');
        
        // ✅ เช็ค error จาก Odoo ก่อน
        if (data['error'] != null) {
          final error = data['error'];
          final errorMsg = error['data']?['message'] ?? error['message'] ?? 'Unknown error';
          print('❌ [OdooService] Odoo Error: $errorMsg');
          
          // แสดง debug info ถ้ามี
          if (error['data']?['debug'] != null) {
            print('🐛 [OdooService] Debug: ${error['data']['debug']}');
          }
          
          throw Exception('Odoo Error: $errorMsg');
        }
        
        if (data['result'] != null && data['result'] is List) {
          final bookings = (data['result'] as List)
              .map((json) {
                try {
                  return Booking.fromJson(json);
                } catch (e) {
                  print('❌ [OdooService] Error parsing booking: $e');
                  print('📄 [OdooService] JSON: $json');
                  return null;
                }
              })
              .whereType<Booking>()
              .toList();
              
          print('✅ [OdooService] Successfully parsed ${bookings.length} bookings');
          return bookings;
        } else {
          print('⚠️  [OdooService] No result in response or result is not a list');
          print('📄 [OdooService] Full response: $data');
        }
      } else {
        print('❌ [OdooService] HTTP Error: ${response.statusCode}');
        print('📄 [OdooService] Response body: ${response.body}');
      }
      
      return [];
    } catch (e, stackTrace) {
      print('❌ [OdooService] Get bookings error: $e');
      print('📚 [OdooService] Stack trace: $stackTrace');
      return [];
    }
  }

  // ✅ ฟังก์ชันใหม่: ดึงข้อมูล Booking เดี่ยวพร้อม Coordinates
  Future<Booking?> getBookingById(int bookingId) async {
    try {
      print('🔍 [OdooService] Getting booking by ID: $bookingId');
      
      if (_uid == null) {
        print('⚠️  [OdooService] No UID, authenticating...');
        final authSuccess = await authenticate();
        if (!authSuccess) {
          print('❌ [OdooService] Authentication failed');
          return null;
        }
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/web/dataset/call_kw'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'model': 'vehicle.booking',
            'method': 'search_read',
            'args': [
              [
                ['id', '=', bookingId]
              ]
            ],
            'kwargs': {
              'fields': [
                'id',
                'name',
                'state',
                'pickup_location',
                'destination',
                'distance_km',
                'shipping_cost',
                'total_weight_order', // ✅ เพิ่มน้ำหนักรวม
                'partner_id',
                'delivery_employee_name',
                'planned_start_date',
                'planned_end_date',
                'travel_expenses', // ✅ เพิ่มค่าเที่ยว
                'daily_allowance', // ✅ เพิ่มค่าเบี้ยเลี้ยง
                'vehicle_id',
                'note',
                'pickup_latitude',
                'pickup_longitude',
                'destination_latitude',
                'destination_longitude',
              ],
              'limit': 1,
            },
          },
          'id': Random().nextInt(1000000),
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['error'] != null) {
          print('❌ [OdooService] Error: ${data['error']}');
          return null;
        }
        
        if (data['result'] != null && data['result'].isNotEmpty) {
          print('✅ [OdooService] Booking found with coordinates');
          return Booking.fromJson(data['result'][0]);
        }
      }
      
      print('⚠️  [OdooService] Booking not found');
      return null;
    } catch (e) {
      print('❌ [OdooService] Get booking by ID error: $e');
      return null;
    }
  }

  Future<bool> startBooking(int bookingId) async {
    try {
      if (_uid == null) {
        final authSuccess = await authenticate();
        if (!authSuccess) {
          print('Authentication failed');
          return false;
        }
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/web/dataset/call_kw'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'model': 'vehicle.booking',
            'method': 'action_start',
            'args': [[bookingId]],
            'kwargs': {},
          },
          'id': 4,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Start booking error: $e');
      return false;
    }
  }

  Future<bool> completeBooking(int bookingId) async {
    try {
      if (_uid == null) {
        final authSuccess = await authenticate();
        if (!authSuccess) {
          print('Authentication failed');
          return false;
        }
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/web/dataset/call_kw'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'model': 'vehicle.booking',
            'method': 'action_done',
            'args': [[bookingId]],
            'kwargs': {},
          },
          'id': 5,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Complete booking error: $e');
      return false;
    }
  }

  // เริ่มงานพร้อมอัพโหลดรูป
  Future<bool> startJobWithPhoto({
    required int bookingId,
    required String photoPath,
  }) async {
    try {
      print('📸 [StartJobWithPhoto] Starting for booking ID: $bookingId');
      
      // Authenticate if not already
      if (_uid == null) {
        print('🔐 [StartJobWithPhoto] Authenticating...');
        await authenticate();
      }

      // ✅ อ่านรูปภาพจาก file path แล้วแปลงเป็น base64
      print('📁 [StartJobWithPhoto] Reading photo from: $photoPath');
      final photoFile = File(photoPath);
      
      if (!photoFile.existsSync()) {
        print('❌ [StartJobWithPhoto] Photo file not found: $photoPath');
        return false;
      }

      final photoBytes = await photoFile.readAsBytes();
      if (photoBytes.isEmpty) {
        print('❌ [StartJobWithPhoto] Photo file is empty');
        return false;
      }

      final base64Photo = base64Encode(photoBytes);
      print('✅ [StartJobWithPhoto] Photo encoded, size: ${base64Photo.length} characters (original: ${photoBytes.length} bytes)');

      print('🌐 [StartJobWithPhoto] Uploading photo and starting job via Odoo XML-RPC...');
      
      // ใช้ Odoo XML-RPC API โดยตรง
      final response = await http.post(
        Uri.parse('$_baseUrl/web/dataset/call_kw'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'model': 'vehicle.booking',
            'method': 'start_job_with_photo',
            'args': [bookingId, base64Photo],
            'kwargs': {},
          },
          'id': Random().nextInt(1000000),
        }),
      );

      print('📥 [StartJobWithPhoto] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // เช็คว่ามี error หรือไม่
        if (data['error'] != null) {
          final error = data['error'];
          print('❌ [StartJobWithPhoto] Odoo Error: $error');
          print('   Error Code: ${error['code']}');
          print('   Error Message: ${error['message']}');
          if (error['data'] != null) {
            print('   Error Name: ${error['data']['name']}');
            print('   Error Details: ${error['data']['debug']}');
          }
          return false;
        }
        
        // เช็คผลลัพธ์
        if (data['result'] != null) {
          print('✅ [StartJobWithPhoto] Success!');
          print('   Result: ${data['result']}');
          return true;
        } else {
          print('⚠️ [StartJobWithPhoto] No result in response');
          return false;
        }
      }
      
      print('❌ [StartJobWithPhoto] Bad status code: ${response.statusCode}');
      return false;
    } catch (e, stackTrace) {
      print('❌ [StartJobWithPhoto] Error: $e');
      print('📚 [StartJobWithPhoto] Stack trace: $stackTrace');
      return false;
    }
  }

  // ส่งของเสร็จสิ้นพร้อมลายเซ็นและข้อมูลลายน้ำ
  Future<bool> completeDelivery({
    required int bookingId,
    required String deliveryPhotoPath,
    required String signaturePath,
    required String receiverName,
    required bool signedBySelf,
    DateTime? deliveryTimestamp,
    double? deliveryLatitude,
    double? deliveryLongitude,
  }) async {
    try {
      print('📦 [CompleteDelivery] Starting for booking ID: $bookingId');
      
      // Authenticate if not already
      if (_uid == null) {
        print('🔐 [CompleteDelivery] Authenticating...');
        await authenticate();
      }
      
      // อ่านรูปภาพเป็น base64
      print('📁 [CompleteDelivery] Reading delivery photo...');
      final photoFile = File(deliveryPhotoPath);
      if (!photoFile.existsSync()) {
        print('❌ [CompleteDelivery] Photo file not found');
        return false;
      }
      final photoBytes = await photoFile.readAsBytes();
      if (photoBytes.isEmpty) {
        print('❌ [CompleteDelivery] Delivery photo is empty');
        return false;
      }
      final base64Photo = base64Encode(photoBytes);
      print('✅ [CompleteDelivery] Photo encoded, size: ${base64Photo.length} characters');

      // อ่านลายเซ็นเป็น base64
      print('📁 [CompleteDelivery] Reading signature...');
      final sigFile = File(signaturePath);
      if (!sigFile.existsSync()) {
        print('❌ [CompleteDelivery] Signature file not found');
        return false;
      }
      final signatureBytes = await sigFile.readAsBytes();
      if (signatureBytes.isEmpty) {
        print('❌ [CompleteDelivery] Signature is empty');
        return false;
      }
      final base64Signature = base64Encode(signatureBytes);
      print('✅ [CompleteDelivery] Signature encoded, size: ${base64Signature.length} characters');

      print('🌐 [CompleteDelivery] Sending data to server via REST API...');
      
      // ✅ ใช้ REST API endpoint เหมือนไฟล์เก่า (ใช้ JSON body แทน multipart)
      final response = await http.post(
        Uri.parse('$_baseUrl/api/delivery/complete'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'booking_id': bookingId,
            'delivery_photo': base64Photo,
            'receiver_signature': base64Signature,
            'receiver_name': receiverName,
            'signed_by_self': signedBySelf,
            'planned_end_date_t': _formatDateTimeForOdoo(deliveryTimestamp ?? DateTime.now()),  // ✅ เพิ่มเวลาส่งจริง
            if (deliveryTimestamp != null) 'delivery_timestamp': _formatDateTimeForOdoo(deliveryTimestamp),
            if (deliveryLatitude != null) 'delivery_latitude': deliveryLatitude,
            if (deliveryLongitude != null) 'delivery_longitude': deliveryLongitude,
          },
          'id': Random().nextInt(1000000),
        }),
      ).timeout(const Duration(seconds: 30));

      print('📥 [CompleteDelivery] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        print('📦 [CompleteDelivery] Response data: $data');
        
        // ✅ เช็ค 2 format:
        // Format 1: { result: { success: true, ... } } (JSONRPC)
        // Format 2: { success: true, ... } (Direct JSON)
        
        bool success = false;
        String? message;
        
        if (data is Map) {
          // Format 1: JSONRPC with result wrapper
          if (data['result'] != null && data['result'] is Map) {
            success = data['result']['success'] == true;
            message = data['result']['message'] ?? 'Unknown error';
          }
          // Format 2: Direct JSON
          else if (data['success'] != null) {
            success = data['success'] == true;
            message = data['message'] ?? (success ? 'Success' : 'Unknown error');
          }
          // Error response
          else if (data['error'] != null) {
            success = false;
            message = data['error']['message'] ?? 'Server error';
          }
        }
        
        if (success) {
          print('✅ [CompleteDelivery] Success!');
          print('   📍 Response data:');
          print('      - planned_end_date_t: ${data['planned_end_date_t'] ?? data['result']?['planned_end_date_t'] ?? 'N/A'}');
          return true;
        } else {
          print('❌ [CompleteDelivery] Error: $message');
          print('📦 Full response: $data');
          return false;
        }
      }
      
      print('❌ [CompleteDelivery] Bad status code: ${response.statusCode}');
      return false;
    } catch (e, stackTrace) {
      print('❌ [CompleteDelivery] Error: $e');
      print('📚 [CompleteDelivery] Stack trace: $stackTrace');
      return false;
    }
  }

  // เช็คว่ามีงานที่กำลังทำอยู่หรือไม่
  Future<Booking?> getActiveJob(int driverId) async {
    try {
      // Authenticate if not already
      if (_uid == null) {
        await authenticate();
      }
      
      final response = await http.post(
        Uri.parse('$_baseUrl/api/booking/get_active_job'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'params': {
            'driver_id': driverId,
          },
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['result'] != null && data['result']['success'] == true) {
          final jobData = data['result']['data'];
          if (jobData != null) {
            return Booking.fromJson(jobData);
          }
        }
      }
      return null;
    } catch (e) {
      print('❌ Error getting active job: $e');
      return null;
    }
  }

  // ========== Tracking Methods ==========

  // ส่งตำแหน่งไปยัง Odoo - ใช้ Map<String, dynamic> เพื่อคืนข้อมูลเพิ่มเติม
  Future<Map<String, dynamic>> updateLocationWithResponse({
    required int bookingId,
    required double latitude,
    required double longitude,
    double? accuracy,
    double? speed,
    double? heading,
    double? altitude,
    double? batteryLevel,
    String? address,
  }) async {
    try {
      if (_uid == null) {
        await authenticate();
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/api/tracking/update_location'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'params': {
            'booking_id': bookingId,
            'latitude': latitude,
            'longitude': longitude,
            if (accuracy != null) 'accuracy': accuracy,
            if (speed != null) 'speed': speed,
            if (heading != null) 'heading': heading,
            if (altitude != null) 'altitude': altitude,
            if (batteryLevel != null) 'battery_level': batteryLevel,
            if (address != null) 'address': address,
          },
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final result = data['result'] ?? {};
        
        return {
          'success': result['success'] ?? false,
          'message': result['message'] ?? '',
          'should_stop_tracking': result['should_stop_tracking'] ?? false,
          'booking_state': result['booking_state'],
          'final_map_data': result['final_map_data'],
        };
      }
      return {'success': false, 'message': 'Bad status code: ${response.statusCode}'};
    } catch (e) {
      print('❌ Error updating location: $e');
      return {'success': false, 'message': 'Error: $e'};
    }
  }

  // ส่งตำแหน่งไปยัง Odoo (รักษา backward compatibility)
  Future<bool> updateLocation({
    required int bookingId,
    required double latitude,
    required double longitude,
    double? accuracy,
    double? speed,
    double? heading,
    double? altitude,
    double? batteryLevel,
    String? address,
  }) async {
    final result = await updateLocationWithResponse(
      bookingId: bookingId,
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      speed: speed,
      heading: heading,
      altitude: altitude,
      batteryLevel: batteryLevel,
      address: address,
    );
    return result['success'] ?? false;
  }

  // ดึงตำแหน่งล่าสุด
  Future<Map<String, dynamic>?> getLatestLocation(int bookingId) async {
    try {
      if (_uid == null) {
        await authenticate();
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/api/tracking/get_latest'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'params': {
            'booking_id': bookingId,
          },
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['result'] != null && data['result']['success'] == true) {
          return data['result']['data'];
        }
      }
      return null;
    } catch (e) {
      print('❌ Error getting latest location: $e');
      return null;
    }
  }

  // ดึงประวัติการเคลื่อนที่
  Future<List<Map<String, dynamic>>> getTrackingHistory({
    required int bookingId,
    int hours = 24,
  }) async {
    try {
      if (_uid == null) {
        await authenticate();
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/api/tracking/get_history'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'params': {
            'booking_id': bookingId,
            'hours': hours,
          },
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['result'] != null && data['result']['success'] == true) {
          final List<dynamic> historyData = data['result']['data'];
          return historyData.map((e) => e as Map<String, dynamic>).toList();
        }
      }
      return [];
    } catch (e) {
      print('❌ Error getting tracking history: $e');
      return [];
    }
  }

  // ดึงการตั้งค่าการติดตาม
  Future<Map<String, dynamic>?> getTrackingSettings() async {
    try {
      if (_uid == null) {
        await authenticate();
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/api/settings/get'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'params': {},
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['result'] != null && data['result']['success'] == true) {
          return data['result']['data'];
        }
      }
      return null;
    } catch (e) {
      print('❌ Error getting tracking settings: $e');
      return null;
    }
  }

  // อัพเดทการตั้งค่าการติดตาม
  Future<bool> updateTrackingSettings(Map<String, dynamic> settings) async {
    try {
      if (_uid == null) {
        await authenticate();
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/api/settings/update'),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'params': settings,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['result'] != null && data['result']['success'] == true;
      }
      return false;
    } catch (e) {
      print('❌ Error updating tracking settings: $e');
      return false;
    }
  }

  // ✅ ดึงประวัติการจัดส่งของคนขับ
  Future<List<DeliveryHistory>> getDriverDeliveryHistory(int driverId, {
    int limit = 50,
    String? state,
    DateTime? startDate,  // 🆕 เพิ่ม parameter
    DateTime? endDate,    // 🆕 เพิ่ม parameter
  }) async {
    try {
      print('🔄 [OdooService] Fetching delivery history for driver: $driverId');
      print('   Type of driverId: ${driverId.runtimeType}');
      
      if (_uid == null) {
        await authenticate();
      }

      // 🆕 สร้าง domain filter
      List<dynamic> domain = [['driver_id', '=', driverId]];
      
      // 🆕 เพิ่มกรองตามวันที่
      if (startDate != null) {
        final startDateStr = _formatDateTimeForOdoo(startDate);
        domain.add(['completion_date', '>=', startDateStr]);
        print('   📅 Start date filter: $startDateStr');
      }
      
      if (endDate != null) {
        final endDateStr = _formatDateTimeForOdoo(endDate);
        domain.add(['completion_date', '<=', endDateStr]);
        print('   📅 End date filter: $endDateStr');
      }
      
      // เพิ่มกรอง state ถ้ามี
      if (state != null && state != 'all') {
        domain.add(['state', '=', state]);
        print('   🎯 State filter: $state');
      }

      // ใช้ /web/dataset/call_kw API ที่ถูกต้อง (ไม่ต้องส่ง db/uid/password ใหม่)
      final queryBody = {
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {
          'model': 'delivery.history',
          'method': 'search_read',
          'args': [],
          'kwargs': {
            'domain': domain,  // 🆕 ใช้ domain ที่มีการกรองวันที่
            'fields': [
              'id', 'name', 'completion_date', 'partner_name', 
              'driver_id', 'driver_name', 'vehicle_name', 
              'pickup_location', 'destination', 
              'distance_km', 'duration_hours', 
              'shipping_cost', 'travel_expenses', 'daily_allowance',
              'planned_start_date_t', 'planned_end_date_t',
              'state'
            ],
            'limit': limit,
            'order': 'completion_date desc',
          }
        },
        'id': DateTime.now().millisecondsSinceEpoch,
      };
      
      print('   📋 Query limit: $limit');
      print('   🔍 Domain: $domain');

      // Remove trailing slash from base URL if present
      final cleanBaseUrl = _baseUrl.endsWith('/') ? _baseUrl.substring(0, _baseUrl.length - 1) : _baseUrl;
      final url = '$cleanBaseUrl/web/dataset/call_kw';
      print('   🌐 URL: $url');

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode(queryBody),
      );

      print('📡 [OdooService] Response status: ${response.statusCode}');

      if (response.statusCode != 200) {
        print('❌ [OdooService] Status code error: ${response.statusCode}');
        return [];
      }

      final responseData = jsonDecode(response.body);
      print('📦 [OdooService] Full response: $responseData');
      
      if (responseData['error'] != null) {
        print('❌ [OdooService] RPC error: ${responseData['error']}');
        return [];
      }

      final List<dynamic> bookingData = responseData['result'] ?? [];
      print('✅ [OdooService] Found ${bookingData.length} delivery history records for driver $driverId');

      if (bookingData.isEmpty) {
        print('⚠️ No delivery history found');
        return [];
      }

      // Parse booking data to DeliveryHistory objects
      final List<DeliveryHistory> deliveryHistory = [];
      print('🔍 [OdooService] Parsing ${bookingData.length} records...');
      
      for (int i = 0; i < bookingData.length; i++) {
        var booking = bookingData[i];
        try {
          print('   📍 Record $i: ${booking['name']}');
          print('      📦 Raw booking data: $booking');
          
          // ✅ ใช้ DeliveryHistory.fromJson() แทนการสร้าง object โดยตรง
          final delivery = DeliveryHistory.fromJson(booking);
          deliveryHistory.add(delivery);
          
          print('      ✅ Parsed successfully!');
          
        } catch (e, stacktrace) {
          print('   ❌ ERROR parsing record $i:');
          print('      Error: $e');
          print('      Record data: $booking');
          print('      Stacktrace: $stacktrace');
        }
      }

      print('✅ [OdooService] Successfully parsed ${deliveryHistory.length} / ${bookingData.length} delivery records');
      return deliveryHistory;
    } catch (e) {
      print('❌ [OdooService] Error: $e');
      return [];
    }
  }

  // ⏳ TODO: isSessionValid() - ต้องเพิ่ม _sessionExpires variable ก่อน
  // /// ✅ Check if session is still valid
  // Future<bool> isSessionValid() async {
  //   try {
  //     if (_uid == null) return false;
  //     
  //     if (_sessionExpires != null) {
  //       if (DateTime.now().isAfter(_sessionExpires!)) {
  //         print('⚠️ [OdooService] Session expired');
  //         return false;
  //       }
  // ✅ ดึงรายได้เดือนนี้
  Future<double> getCurrentMonthIncome(int driverId) async {
    try {
      print('💰 [OdooService] Fetching current cycle income for driver: $driverId');

      // ✅ รอบจ่ายเงินปัจจุบัน: 25 ของเดือนก่อน ถึง 24 ของเดือนนี้
      //    ถ้าวันนี้ >= 25 จะเข้าสู่รอบของ "เดือนถัดไป" แล้ว
      final now = DateTime.now();
      late DateTime cycleStart;
      late DateTime cycleEnd;
      if (now.day >= 25) {
        cycleStart = DateTime(now.year, now.month, 25);
        cycleEnd = DateTime(now.year, now.month + 1, 24);
      } else {
        cycleStart = DateTime(now.year, now.month - 1, 25);
        cycleEnd = DateTime(now.year, now.month, 24);
      }
      String fmtDate(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      if (_uid == null) {
        await authenticate();
      }

      final queryBody = {
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {
          // ✅ ใช้ vehicle.booking + delivery_date + state=done (ตรงกับที่กรองใน Odoo)
          'model': 'vehicle.booking',
          'method': 'search_read',
          'args': [],
          'kwargs': {
            'domain': [
              ['driver_id', '=', driverId],
              ['state', '=', 'done'],
              ['delivery_date', '>=', fmtDate(cycleStart)],
              ['delivery_date', '<=', fmtDate(cycleEnd)],
            ],
            'fields': ['travel_expenses', 'daily_allowance'],  // ✅ เอาแค่ เที่ยว + เบี้ยเลี้ยง
          }
        },
        'id': DateTime.now().millisecondsSinceEpoch,
      };

      final cleanBaseUrl = _baseUrl.endsWith('/') ? _baseUrl.substring(0, _baseUrl.length - 1) : _baseUrl;
      final url = '$cleanBaseUrl/web/dataset/call_kw';

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode(queryBody),
      );

      if (response.statusCode != 200) {
        print('❌ [OdooService] Failed to fetch current month income');
        return 0.0;
      }

      final responseData = jsonDecode(response.body);
      if (responseData['result'] == null || responseData['result'].isEmpty) {
        print('⚠️  [OdooService] No delivery found this month');
        return 0.0;
      }

      double totalIncome = 0.0;
      for (var record in responseData['result']) {
        final travelExpenses = record['travel_expenses'] != null
            ? (record['travel_expenses'] as num).toDouble()
            : 0.0;
        final dailyAllowance = record['daily_allowance'] != null
            ? (record['daily_allowance'] as num).toDouble()
            : 0.0;
        totalIncome += travelExpenses + dailyAllowance;  // ✅ เอาแค่ เที่ยว + เบี้ยเลี้ยง
      }

      print('✅ [OdooService] Current month income: ${totalIncome.toStringAsFixed(2)} บาท');
      return totalIncome;
    } catch (e) {
      print('❌ [OdooService] Error fetching current month income: $e');
      return 0.0;
    }
  }

  // ✅ ดึง "รายการงาน" ในรอบจ่ายเงินปัจจุบัน (25 เดือนก่อน → 24 เดือนนี้)
  //    คืนค่าเป็น list ของ {name, delivery_date, travel_expenses, daily_allowance}
  Future<List<Map<String, dynamic>>> getCurrentCycleDeliveries(int driverId) async {
    try {
      final now = DateTime.now();
      late DateTime cycleStart;
      late DateTime cycleEnd;
      if (now.day >= 25) {
        cycleStart = DateTime(now.year, now.month, 25);
        cycleEnd = DateTime(now.year, now.month + 1, 24);
      } else {
        cycleStart = DateTime(now.year, now.month - 1, 25);
        cycleEnd = DateTime(now.year, now.month, 24);
      }
      String fmtDate(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      if (_uid == null) {
        await authenticate();
      }

      final queryBody = {
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {
          'model': 'vehicle.booking',
          'method': 'search_read',
          'args': [],
          'kwargs': {
            'domain': [
              ['driver_id', '=', driverId],
              ['state', '=', 'done'],
              ['delivery_date', '>=', fmtDate(cycleStart)],
              ['delivery_date', '<=', fmtDate(cycleEnd)],
            ],
            'fields': ['name', 'delivery_date', 'travel_expenses', 'daily_allowance'],
            'order': 'delivery_date desc',
          }
        },
        'id': DateTime.now().millisecondsSinceEpoch,
      };

      final cleanBaseUrl = _baseUrl.endsWith('/') ? _baseUrl.substring(0, _baseUrl.length - 1) : _baseUrl;
      final url = '$cleanBaseUrl/web/dataset/call_kw';

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode(queryBody),
      );

      if (response.statusCode != 200) {
        return [];
      }

      final responseData = jsonDecode(response.body);
      final result = responseData['result'];
      if (result == null || result is! List) {
        return [];
      }

      return result
          .map<Map<String, dynamic>>((r) => {
                'name': r['name'] ?? '-',
                'delivery_date': r['delivery_date'] ?? '',
                'travel_expenses': r['travel_expenses'] != null
                    ? (r['travel_expenses'] as num).toDouble()
                    : 0.0,
                'daily_allowance': r['daily_allowance'] != null
                    ? (r['daily_allowance'] as num).toDouble()
                    : 0.0,
              })
          .toList();
    } catch (e) {
      print('❌ [OdooService] Error fetching current cycle deliveries: $e');
      return [];
    }
  }

  // ✅ ดึงรายได้รายเดือน
  Future<List<IncomeData>> getMonthlyIncome(int driverId) async {
    try {
      print('💰 [OdooService] Fetching monthly income for driver: $driverId');
      
      if (_uid == null) {
        await authenticate();
      }

      // ✅ ดึงจาก vehicle.booking โดยตรง (แหล่งเดียวกับที่กรองใน Odoo)
      //    ใช้ delivery_date = "วันส่งจริง" (Date เวลาไทย) + สถานะ done = เสร็จสิ้น
      //    เพื่อให้ยอดตรงกับที่กรองในระบบ Odoo เป๊ะ
      final queryBody = {
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {
          'model': 'vehicle.booking',
          'method': 'search_read',
          'args': [],
          'kwargs': {
            'domain': [
              ['driver_id', '=', driverId],
              ['state', '=', 'done'],
              ['delivery_date', '!=', false],
            ],
            'fields': ['delivery_date', 'shipping_cost', 'travel_expenses', 'daily_allowance'],
            'order': 'delivery_date desc',
          }
        },
        'id': DateTime.now().millisecondsSinceEpoch,
      };

      final cleanBaseUrl = _baseUrl.endsWith('/') ? _baseUrl.substring(0, _baseUrl.length - 1) : _baseUrl;
      final url = '$cleanBaseUrl/web/dataset/call_kw';

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode(queryBody),
      );

      if (response.statusCode != 200) {
        print('❌ [OdooService] Failed to fetch income data');
        return [];
      }

      final responseData = jsonDecode(response.body);
      if (responseData['result'] == null || responseData['result'].isEmpty) {
        print('⚠️  [OdooService] No delivery history found');
        return [];
      }

      // จัดกลุ่มตามเดือน
      Map<String, IncomeData> incomeByMonth = {};

      for (var record in responseData['result']) {
        try {
          // ✅ "วันส่งจริง" (delivery_date) เป็น Date เวลาไทยอยู่แล้ว (รูปแบบ YYYY-MM-DD)
          //    ไม่ต้องแปลง timezone จึงไม่มีปัญหาขอบวันคลาดเคลื่อน
          final deliveryRaw = record['delivery_date'];
          if (deliveryRaw is! String || deliveryRaw.isEmpty) {
            continue;
          }
          final date = DateTime.parse(deliveryRaw);

          // ✅ รอบจ่ายเงิน: 25 ของเดือนก่อน ถึง 24 ของเดือนนี้
          //    วันที่ >= 25 ให้นับเป็นรอบของ"เดือนถัดไป"
          //    เช่น 25/05–24/06 = รอบเดือน 6 (มิถุนายน)
          int cycleMonth = date.month;
          int cycleYear = date.year;
          if (date.day >= 25) {
            cycleMonth += 1;
            if (cycleMonth > 12) {
              cycleMonth = 1;
              cycleYear += 1;
            }
          }
          final monthKey = '$cycleYear-${cycleMonth.toString().padLeft(2, '0')}';

          final shippingCost = record['shipping_cost'] != null 
              ? (record['shipping_cost'] as num).toDouble() 
              : 0.0;
          final travelExpenses = record['travel_expenses'] != null
              ? (record['travel_expenses'] as num).toDouble()
              : 0.0;
          final dailyAllowance = record['daily_allowance'] != null
              ? (record['daily_allowance'] as num).toDouble()
              : 0.0;

          if (incomeByMonth.containsKey(monthKey)) {
            final existing = incomeByMonth[monthKey]!;
            incomeByMonth[monthKey] = IncomeData(
              month: existing.month,
              year: existing.year,
              totalShippingCost: existing.totalShippingCost + shippingCost,
              totalTravelExpenses: existing.totalTravelExpenses + travelExpenses,
              totalDailyAllowance: existing.totalDailyAllowance + dailyAllowance,
              totalDeliveries: existing.totalDeliveries + 1,
            );
          } else {
            incomeByMonth[monthKey] = IncomeData(
              month: cycleMonth,
              year: cycleYear,
              totalShippingCost: shippingCost,
              totalTravelExpenses: travelExpenses,
              totalDailyAllowance: dailyAllowance,
              totalDeliveries: 1,
            );
          }
        } catch (e) {
          print('⚠️  Error processing record: $e');
        }
      }

      // เรียงลำดับเดือนจากล่าสุด
      final sortedIncome = incomeByMonth.values.toList()
        ..sort((a, b) {
          final aDate = DateTime(a.year, a.month);
          final bDate = DateTime(b.year, b.month);
          return bDate.compareTo(aDate);
        });

      print('✅ [OdooService] Found ${sortedIncome.length} months of income data');
      for (var income in sortedIncome) {
        print('   📊 ${income.displayText}: ${income.totalIncome.toStringAsFixed(2)} บาท '
            '(ค่าขนส่ง: ${income.totalShippingCost.toStringAsFixed(2)}, '
            'ค่าเที่ยว: ${income.totalTravelExpenses.toStringAsFixed(2)}, '
            'ค่าเบี้ยเลี้ยง: ${income.totalDailyAllowance.toStringAsFixed(2)}) '
            '- ${income.totalDeliveries} ครั้ง');
      }

      return sortedIncome;
    } catch (e) {
      print('❌ [OdooService] Error fetching monthly income: $e');
      return [];
    }
  }

  // ==================== 🚗 Vehicle Inspection ====================
  
  /// 📝 บันทึกรายการตรวจสอบสภาพรถ
  Future<Map<String, dynamic>> submitVehicleInspection({
    required int driverId,
    required String driverName,
    required int? branchId,
    required String inspectionDateThai,
    required List<Map<String, dynamic>> inspectionLines,
    required List<Map<String, dynamic>> maintenanceLines,
    required String generalNote,
    int? vehicleId,  // 🆕 เพิ่ม vehicle_id
    int? categoryId,  // 🆕 เพิ่ม category_id
  }) async {
    try {
      print('🚗 [OdooService] Submitting vehicle inspection...');
      print('   Driver ID: $driverId');
      print('   Driver Name: $driverName');
      print('   Date (Thai): $inspectionDateThai');
      print('   Inspection Lines: ${inspectionLines.length}');
      print('   Maintenance Lines: ${maintenanceLines.length}');

      // ตรวจสอบ session
      if (!_isSessionValid()) {
        print('🔐 [OdooService] Session invalid, re-authenticating...');
        await authenticate();
      }

      // สร้างข้อมูลสำหรับส่งไป Odoo
      final inspectionData = {
        'driver_id': driverId,
        'branch_id': branchId,
        'general_note': generalNote,
        if (vehicleId != null) 'vehicle_id': vehicleId,  // 🆕 เพิ่ม vehicle_id
        if (categoryId != null) 'category_id': categoryId,  // 🆕 เพิ่ม category_id
        'inspection_line_ids': inspectionLines.map((line) => [0, 0, {
          'item_no': line['id'],
          'name': line['title'],
          'standard': line['standard'],
          'is_checked': line['isChecked'] ?? false,
          'note': line['note'] ?? '',
          'image': line['image'],  // 📷 เพิ่ม base64 image
        }]).toList(),
        'maintenance_line_ids': maintenanceLines.map((line) => [0, 0, {
          'item_no': line['id'],
          'name': line['title'],
          'is_due': line['isDue'] == true ? 'due' : (line['isDue'] == false ? 'not_due' : false),
          'current_mileage': line['currentMileage'] ?? '',
          'last_change_mileage': line['lastChangeMileage'] ?? '',
        }]).toList(),
      };

      final response = await http.post(
        Uri.parse('$_baseUrl/web/dataset/call_kw'),
        headers: {
          'Content-Type': 'application/json',
          'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'model': 'vehicle.inspection',
            'method': 'create',
            'args': [inspectionData],
            'kwargs': {},
          },
          'id': Random().nextInt(1000000),
        }),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['result'] != null) {
          print('✅ [OdooService] Vehicle inspection created successfully! ID: ${result['result']}');
          return {
            'success': true,
            'id': result['result'],
            'message': 'บันทึกการตรวจสอบเรียบร้อย',
          };
        } else if (result['error'] != null) {
          print('❌ [OdooService] Error: ${result['error']}');
          return {
            'success': false,
            'message': result['error']['data']?['message'] ?? 'เกิดข้อผิดพลาดในการบันทึก',
          };
        }
      }

      print('❌ [OdooService] HTTP Error: ${response.statusCode}');
      return {
        'success': false,
        'message': 'ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้',
      };
    } catch (e) {
      print('❌ [OdooService] Exception: $e');
      return {
        'success': false,
        'message': 'เกิดข้อผิดพลาด: $e',
      };
    }
  }

  /// 📜 ดึงประวัติการตรวจสอบสภาพรถ
  Future<List<Map<String, dynamic>>> getVehicleInspectionHistory(int driverId) async {
    try {
      print('📜 [OdooService] Fetching vehicle inspection history for driver: $driverId');

      if (!_isSessionValid()) {
        print('🔐 [OdooService] Session invalid, re-authenticating...');
        await authenticate();
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/web/dataset/call_kw'),
        headers: {
          'Content-Type': 'application/json',
          'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'model': 'vehicle.inspection',
            'method': 'search_read',
            'args': [
              [['driver_id', '=', driverId]],
            ],
            'kwargs': {
              'fields': [
                'id', 'name', 'inspection_date', 'inspection_date_thai',
                'driver_name', 'branch_id', 'state', 
                'total_items', 'checked_items', 'issue_count', 'general_note',
                'vehicle_id', 'license_plate', 'category_id', 'category_name'
              ],
              'order': 'inspection_date desc',
              'limit': 50,
            },
          },
          'id': Random().nextInt(1000000),
        }),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['result'] != null) {
          final List<dynamic> data = result['result'];
          print('✅ [OdooService] Found ${data.length} inspection records');
          return data.cast<Map<String, dynamic>>();
        }
      }
      
      print('❌ [OdooService] Failed to fetch history');
      return [];
    } catch (e) {
      print('❌ [OdooService] Exception: $e');
      return [];
    }
  }

  /// 📋 ดึงรายละเอียดการตรวจสอบ
  Future<Map<String, dynamic>?> getVehicleInspectionDetail(int inspectionId) async {
    try {
      print('📋 [OdooService] Fetching inspection detail: $inspectionId');

      if (!_isSessionValid()) {
        await authenticate();
      }

      // ดึงข้อมูลหลัก
      final response = await http.post(
        Uri.parse('$_baseUrl/web/dataset/call_kw'),
        headers: {
          'Content-Type': 'application/json',
          'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'model': 'vehicle.inspection',
            'method': 'read',
            'args': [[inspectionId]],
            'kwargs': {
              'fields': [
                'id', 'name', 'inspection_date', 'inspection_date_thai',
                'driver_name', 'branch_id', 'state', 'general_note',
                'inspection_line_ids', 'maintenance_line_ids',
                'vehicle_id', 'license_plate', 'category_id', 'category_name'
              ],
            },
          },
          'id': Random().nextInt(1000000),
        }),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['result'] != null && result['result'].isNotEmpty) {
          final inspection = result['result'][0];
          
          // ดึงรายการตรวจเช็ค
          if (inspection['inspection_line_ids'] != null && inspection['inspection_line_ids'].isNotEmpty) {
            final linesResponse = await http.post(
              Uri.parse('$_baseUrl/web/dataset/call_kw'),
              headers: {
                'Content-Type': 'application/json',
                'Cookie': 'session_id=$_sessionId',
              },
              body: jsonEncode({
                'jsonrpc': '2.0',
                'method': 'call',
                'params': {
                  'model': 'vehicle.inspection.line',
                  'method': 'read',
                  'args': [inspection['inspection_line_ids']],
                  'kwargs': {
                    'fields': ['item_no', 'name', 'standard', 'is_checked', 'note'],
                  },
                },
                'id': Random().nextInt(1000000),
              }),
            );
            if (linesResponse.statusCode == 200) {
              final linesResult = jsonDecode(linesResponse.body);
              inspection['inspection_lines'] = linesResult['result'] ?? [];
            }
          }
          
          // ดึงรายการบำรุงรักษา
          if (inspection['maintenance_line_ids'] != null && inspection['maintenance_line_ids'].isNotEmpty) {
            final maintResponse = await http.post(
              Uri.parse('$_baseUrl/web/dataset/call_kw'),
              headers: {
                'Content-Type': 'application/json',
                'Cookie': 'session_id=$_sessionId',
              },
              body: jsonEncode({
                'jsonrpc': '2.0',
                'method': 'call',
                'params': {
                  'model': 'vehicle.inspection.maintenance',
                  'method': 'read',
                  'args': [inspection['maintenance_line_ids']],
                  'kwargs': {
                    'fields': ['item_no', 'name', 'is_due', 'current_mileage', 'last_change_mileage'],
                  },
                },
                'id': Random().nextInt(1000000),
              }),
            );
            if (maintResponse.statusCode == 200) {
              final maintResult = jsonDecode(maintResponse.body);
              inspection['maintenance_lines'] = maintResult['result'] ?? [];
            }
          }
          
          print('✅ [OdooService] Got inspection detail');
          return inspection;
        }
      }
      
      return null;
    } catch (e) {
      print('❌ [OdooService] Exception: $e');
      return null;
    }
  }

  // ==================== 🚗 Vehicle List for Inspection ====================
  
  /// 📝 ดึงรายการรถสำหรับเลือกในการตรวจสอบ (กรอง "ไม่มีทะเบียน" ออก)
  Future<List<Map<String, dynamic>>> getVehiclesForInspection() async {
    try {
      print('🚗 [OdooService] Fetching vehicles for inspection...');

      if (!_isSessionValid()) {
        print('🔐 [OdooService] Session invalid, re-authenticating...');
        await authenticate();
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/web/dataset/call_kw'),
        headers: {
          'Content-Type': 'application/json',
          'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'model': 'fleet.vehicle',
            'method': 'search_read',
            'args': [
              [['license_plate', '!=', 'ไม่มีทะเบียน'], ['license_plate', '!=', false]],
            ],
            'kwargs': {
              'fields': ['id', 'name', 'license_plate', 'category_id'],  // 🆕 ดึง category_id โดยตรง
              'order': 'license_plate asc',
            },
          },
          'id': Random().nextInt(1000000),
        }),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['result'] != null) {
          final List<dynamic> vehicles = result['result'];
          print('✅ [OdooService] Found ${vehicles.length} vehicles');
          
          // 🆕 ดึง category_id โดยตรงจาก fleet.vehicle
          List<Map<String, dynamic>> vehiclesWithCategory = [];
          for (var vehicle in vehicles) {
            int? categoryId;
            String categoryName = '';
            
            // category_id เป็น Many2one จะได้ [id, name] หรือ false
            if (vehicle['category_id'] != null && vehicle['category_id'] is List && vehicle['category_id'].length >= 2) {
              categoryId = vehicle['category_id'][0];
              categoryName = vehicle['category_id'][1] ?? '';
              print('   🚗 ${vehicle['license_plate']} -> Category: $categoryName (ID: $categoryId)');
            }
            
            vehiclesWithCategory.add({
              'id': vehicle['id'],
              'name': vehicle['name'],
              'license_plate': vehicle['license_plate'],
              'category_id': categoryId,
              'category_name': categoryName,
            });
          }
          
          return vehiclesWithCategory;
        }
      }
      
      print('❌ [OdooService] Failed to fetch vehicles');
      return [];
    } catch (e) {
      print('❌ [OdooService] Exception: $e');
      return [];
    }
  }

  /// 📝 ดึง category จาก model_id
  Future<Map<String, dynamic>?> _getVehicleCategoryByModelId(int modelId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/web/dataset/call_kw'),
        headers: {
          'Content-Type': 'application/json',
          'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'model': 'fleet.vehicle.model',
            'method': 'read',
            'args': [[modelId]],
            'kwargs': {
              'fields': ['category_id'],
            },
          },
          'id': Random().nextInt(1000000),
        }),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['result'] != null && result['result'].isNotEmpty) {
          final model = result['result'][0];
          if (model['category_id'] != null && model['category_id'] is List && model['category_id'].length > 0) {
            return {
              'id': model['category_id'][0],
              'name': model['category_id'][1],
            };
          }
        }
      }
      return null;
    } catch (e) {
      print('⚠️ [OdooService] Error getting category: $e');
      return null;
    }
  }

  /// 📝 ดึงรายการหมวดหมู่รถทั้งหมด
  Future<List<Map<String, dynamic>>> getVehicleCategories() async {
    try {
      print('📂 [OdooService] Fetching vehicle categories...');

      if (!_isSessionValid()) {
        await authenticate();
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/web/dataset/call_kw'),
        headers: {
          'Content-Type': 'application/json',
          'Cookie': 'session_id=$_sessionId',
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'model': 'fleet.vehicle.model.category',
            'method': 'search_read',
            'args': [[]],
            'kwargs': {
              'fields': ['id', 'name'],
              'order': 'name asc',
            },
          },
          'id': Random().nextInt(1000000),
        }),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['result'] != null) {
          final List<dynamic> categories = result['result'];
          print('✅ [OdooService] Found ${categories.length} categories');
          return categories.cast<Map<String, dynamic>>();
        }
      }
      
      return [];
    } catch (e) {
      print('❌ [OdooService] Exception: $e');
      return [];
    }
  }
}
