import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'odoo_service.dart';

/// ✅ Background Location Service - ต้อง @pragma เพื่อ native code access
@pragma('vm:entry-point')
class BackgroundLocationService {
  static final BackgroundLocationService _instance = 
    BackgroundLocationService._internal();
  
  factory BackgroundLocationService() => _instance;
  BackgroundLocationService._internal();

  // Initialize Background Service
  static Future<void> initializeService() async {
    print('🔧 [Background Service] Initializing...');
    
    try {
      final service = FlutterBackgroundService();
      
      // ✅ Configure with correct notification channel
      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: _onStart,
          isForegroundMode: true,
          autoStart: true,
          autoStartOnBoot: true,
          
          // ✅ สำคัญ: ใช้ channel ID เดียวกับ LocationTrackingService.kt
          notificationChannelId: 'npd_location_service',
          initialNotificationTitle: 'NPD Transport',
          initialNotificationContent: 'ติดตามตำแหน่ง...',
        ),
        iosConfiguration: IosConfiguration(
          autoStart: true,
          onForeground: _onStart,
          onBackground: _onIosBackground,
        ),
      );
      
      service.startService();
      print('✅ [Background Service] Initialized with notification channel');
    } catch (e) {
      print('❌ [Background Service] Error: $e');
      rethrow;
    }
  }

  // Background Service Main Function
  @pragma('vm:entry-point')
  static Future<void> _onStart(ServiceInstance service) async {
    print('🚀 [Background Service] Started');

    service.on('stopService').listen((event) {
      service.stopSelf();
    });

    // Timer สำหรับส่งตำแหน่ง
    Timer? updateTimer;
    
    Future<void> startTracking() async {
      updateTimer?.cancel();
      
      // ดึง interval จาก Odoo
      final interval = await _getTrackingInterval();
      final seconds = (interval * 60).toInt();
      
      print('⏱️ [Background] Interval: $interval minutes ($seconds seconds)');
      
      // ส่งแรกเลย
      await _sendLocation(service);
      
      // ตั้ง timer
      updateTimer = Timer.periodic(Duration(seconds: seconds), (timer) async {
        print('📍 [Background] Sending location...');
        await _sendLocation(service);
      });
    }

    // เริ่มติดตาม
    await startTracking();

    // ตรวจสอบ interval ทุก 5 นาที
    Timer.periodic(const Duration(minutes: 5), (timer) async {
      print('🔄 [Background] Checking interval...');
      await startTracking();
    });
  }

  // ดึง tracking interval จาก Odoo
  static Future<double> _getTrackingInterval() async {
    try {
      final odoo = OdooService();
      await odoo.loadSessionFromPrefs();
      final settings = await odoo.getTrackingSettings();
      
      if (settings != null) {
        final interval = settings['tracking_interval'] as double? ?? 1.0;
        return interval;
      }
      return 1.0;
    } catch (e) {
      print('⚠️ [Background] Error getting interval: $e');
      return 1.0;
    }
  }

  // ส่งตำแหน่ง
  static Future<void> _sendLocation(ServiceInstance service) async {
    try {
      // ดึง booking ID
      final prefs = await SharedPreferences.getInstance();
      final bookingId = prefs.getInt('active_booking_id');
      
      print('📍 [Background] Sending location...');
      print('   ✓ Checking booking ID from SharedPreferences...');
      print('   ✓ Booking ID: $bookingId');
      print('   ✓ All prefs keys: ${prefs.getKeys()}');
      
      if (bookingId == null) {
        print('❌ [Background] No booking ID found!');
        print('   💡 Tip: Make sure setActiveBookingId() was called before starting service');
        print('   💡 SharedPreferences keys: ${prefs.getKeys()}');
        return;
      }
      
      print('✅ [Background] Booking ID found: $bookingId');

      // ตรวจสอบ location service
      if (!await Geolocator.isLocationServiceEnabled()) {
        print('⚠️ [Background] Location disabled');
        return;
      }

      // ดึงตำแหน่ง
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('GPS timeout'),
      );

      final speedKmh = position.speed * 3.6;
      
      // ดึง Battery
      final battery = Battery();
      final batteryLevel = await battery.batteryLevel;

      // ดึงที่อยู่
      String? address;
      try {
        final places = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        ).timeout(const Duration(seconds: 10));
        
        if (places.isNotEmpty) {
          final place = places.first;
          address = '${place.street ?? ''}, ${place.locality ?? ''}';
        }
      } catch (e) {
        print('⚠️ [Background] Address error: $e');
      }

      // ส่งไป Odoo
      final odoo = OdooService();
      await odoo.loadSessionFromPrefs();
      
      final response = await odoo.updateLocationWithResponse(
        bookingId: bookingId,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        speed: speedKmh,
        heading: position.heading,
        altitude: position.altitude,
        batteryLevel: batteryLevel.toDouble(),
        address: address,
      );

      print('✅ [Background] Sent: ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}');
      
      // อัพเดท notification
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'NPD Transport - ติดตามตำแหน่ง',
          content: '📍 ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)} | '
                   '🚗 ${speedKmh.toStringAsFixed(0)} km/h',
        );
      }
      
      // ถ้าเซิร์ฟเวอร์บอกจบแล้ว
      if (response['should_stop_tracking'] == true) {
        print('🛑 [Background] Server stopped tracking');
        await stopService();
      }
      
    } catch (e) {
      print('❌ [Background] Error: $e');
    }
  }

  // iOS Background
  @pragma('vm:entry-point')
  static Future<bool> _onIosBackground(ServiceInstance service) async {
    print('🍎 [iOS Background] Running');
    await _sendLocation(service);
    return true;
  }

  // หยุดเซอร์วิส
  static Future<void> stopService() async {
    try {
      final service = FlutterBackgroundService();
      service.invoke('stopService');
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('active_booking_id');
      
      print('🛑 [Background] Stopped');
    } catch (e) {
      print('❌ [Background] Stop error: $e');
    }
  }

  // เซต Booking ID
  static Future<void> setActiveBookingId(int bookingId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('active_booking_id', bookingId);
      print('✅ [Background] Booking ID: $bookingId');
    } catch (e) {
      print('❌ [Background] Set ID error: $e');
    }
  }
}
