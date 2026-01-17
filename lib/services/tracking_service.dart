import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/tracking_settings.dart';
import '../models/booking.dart';
import 'odoo_service.dart';
import 'background_location_service.dart';

class TrackingService {
  final OdooService _odooService = OdooService();
  
  Timer? _trackingTimer;
  TrackingSettings? _settings;
  Booking? _currentBooking;
  bool _isTracking = false;
  Position? _lastPosition;
  DateTime? _lastUpdateTime;

  // Singleton pattern
  static final TrackingService _instance = TrackingService._internal();
  factory TrackingService() => _instance;
  TrackingService._internal();

  bool get isTracking => _isTracking;
  TrackingSettings? get settings => _settings;
  Position? get lastPosition => _lastPosition;
  DateTime? get lastUpdateTime => _lastUpdateTime;

  // ดึงการตั้งค่าจาก Odoo
  Future<TrackingSettings?> loadSettings() async {
    try {
      print('📡 [Tracking] Loading settings from Odoo...');
      final settingsData = await _odooService.getTrackingSettings();
      
      if (settingsData != null) {
        _settings = TrackingSettings.fromJson(settingsData);
        print('✅ [Tracking] Settings loaded: ${_settings!.trackingEnabled ? "Enabled" : "Disabled"}');
        print('   - Interval: ${_settings!.trackingInterval}s (${(_settings!.trackingInterval / 60).toStringAsFixed(1)} minutes from Odoo)');
        print('   - High Accuracy: ${_settings!.highAccuracy}');
        return _settings;
      } else {
        print('⚠️ [Tracking] No settings found, using defaults');
        _settings = TrackingSettings.defaultSettings();
        return _settings;
      }
    } catch (e) {
      print('❌ [Tracking] Error loading settings: $e');
      _settings = TrackingSettings.defaultSettings();
      return _settings;
    }
  }

  // เริ่มติดตามตำแหน่ง
  Future<bool> startTracking(Booking booking, {bool forceStart = false}) async {
    if (_isTracking) {
      print('⚠️ [Tracking] Already tracking');
      return true;
    }

    try {
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('🚀 [Tracking] Starting tracking service');
      print('   📦 Booking: ${booking.name} (ID: ${booking.id})');
      print('   🔧 Force Start: $forceStart');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      
      _currentBooking = booking;

      // โหลดการตั้งค่า
      print('📋 [Tracking] Loading settings from Odoo...');
      await loadSettings();

      // ✅ ถ้า forceStart = true ให้บังคับเปิด tracking เสมอ (ข้ามการตั้งค่า Odoo)
      if (forceStart) {
        print('🔧 [Tracking] Force start enabled - overriding Odoo settings');
        if (_settings == null) {
          print('   ⚠️ No settings found, using defaults');
          _settings = TrackingSettings.defaultSettings();
        }
        
        print('   📝 Original settings: trackingEnabled = ${_settings!.trackingEnabled}');
        
        // บังคับให้ tracking enabled
        _settings = TrackingSettings(
          trackingEnabled: true,  // ✅ บังคับเปิดเสมอ
          trackingInterval: _settings!.trackingInterval,
          highAccuracy: _settings!.highAccuracy,
          notifyOnArrival: _settings!.notifyOnArrival,
          notifyOnDelay: _settings!.notifyOnDelay,
          notifyOffRoute: _settings!.notifyOffRoute,
          offRouteDistance: _settings!.offRouteDistance,
          showSpeed: _settings!.showSpeed,
          showRoute: _settings!.showRoute,
          mapType: _settings!.mapType,
          saveHistory: _settings!.saveHistory,
          historyRetentionDays: _settings!.historyRetentionDays,
        );
        
        print('   ✅ Settings overridden: trackingEnabled = true');
        print('   ⏱️  Interval: ${_settings!.trackingInterval}s (${(_settings!.trackingInterval / 60).toStringAsFixed(1)} minutes)');
        print('   🎯 High Accuracy: ${_settings!.highAccuracy}');
      } else {
        // ถ้าไม่ได้ force start ให้เช็คการตั้งค่าปกติ
        print('📋 [Tracking] Checking Odoo settings...');
        if (_settings == null || !_settings!.trackingEnabled) {
          print('❌ [Tracking] Tracking is disabled in Odoo settings');
          print('   💡 Tip: Use forceStart=true to override settings');
          return false;
        }
        
        print('   ✅ Tracking enabled in settings');
        print('   ⏱️  Interval: ${_settings!.trackingInterval}s (${(_settings!.trackingInterval / 60).toStringAsFixed(1)} minutes from Odoo)');
        print('   🎯 High Accuracy: ${_settings!.highAccuracy}');
      }

      // ตรวจสอบ permission
      print('🔐 [Tracking] Checking location permissions...');
      final hasPermission = await _checkLocationPermission();
      if (!hasPermission) {
        print('❌ [Tracking] Location permission denied or not granted');
        print('   💡 Make sure user granted "Allow all the time" permission');
        return false;
      }
      print('   ✅ Location permission granted');

      // ส่งตำแหน่งครั้งแรก
      print('📍 [Tracking] Sending initial location...');
      await _sendCurrentLocation();

      // ตั้งค่า timer สำหรับส่งตำแหน่งอัตโนมัติ
      print('⏰ [Tracking] Setting up location update timer');
      print('   ⏱️  Update every ${_settings!.trackingInterval} seconds (${(_settings!.trackingInterval / 60).toStringAsFixed(1)} minutes)');
      
      _trackingTimer = Timer.periodic(
        Duration(seconds: _settings!.trackingInterval),
        (_) {
          print('⏰ [Tracking] Timer tick - sending location update');
          _sendCurrentLocation();
        },
      );

      _isTracking = true;
      
      // ✅ เริ่ม Background Service เพื่อส่งตำแหน่งต่อเนื่อง (รวมเมื่อ app ออกไป background)
      try {
        await BackgroundLocationService.setActiveBookingId(booking.id);
        await BackgroundLocationService.initializeService();
        print('✅ [Tracking] Background service started - ติดตามตำแหน่ง 24/7');
      } catch (e) {
        print('⚠️ [Tracking] Background service error: $e');
        print('   Continuing with foreground tracking only');
      }
      
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('✅ [Tracking] Tracking started successfully!');
      print('   📦 Booking: ${booking.name}');
      print('   ⏱️  Updates every: ${_settings!.trackingInterval}s (${(_settings!.trackingInterval / 60).toStringAsFixed(1)} minutes from Odoo)');
      print('   🎯 High Accuracy: ${_settings!.highAccuracy}');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      
      return true;
      
    } catch (e, stackTrace) {
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('❌ [Tracking] ERROR starting tracking');
      print('   Error: $e');
      print('   Stack trace: $stackTrace');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      return false;
    }
  }

  // หยุดติดตามตำแหน่ง
  void stopTracking() {
    if (!_isTracking) {
      print('⚠️ [Tracking] Not tracking');
      return;
    }

    print('🛑 [Tracking] Stopping tracking...');
    
    // หยุด background service
    BackgroundLocationService.stopService();
    
    _trackingTimer?.cancel();
    _trackingTimer = null;
    _isTracking = false;
    _currentBooking = null;
    _lastPosition = null;
    _lastUpdateTime = null;
    print('✅ [Tracking] Tracking stopped');
  }

  // ส่งตำแหน่งปัจจุบัน
  Future<void> _sendCurrentLocation() async {
    if (_currentBooking == null || _settings == null) {
      print('⚠️ [Tracking] Cannot send location - missing booking or settings');
      return;
    }

    // ✅ ตรวจสอบ: ถ้า booking เสร็จสิ้น ให้หยุดติดตาม
    if (_currentBooking!.state == 'done' || _currentBooking!.state == 'cancelled') {
      print('🛑 [Tracking] Booking is ${_currentBooking!.state} - stopping tracking automatically');
      stopTracking();
      return;
    }

    try {
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('📍 [Tracking] Getting current GPS position...');
      print('   📦 Booking: ${_currentBooking!.name} (ID: ${_currentBooking!.id})');
      print('   🎯 Accuracy Mode: ${_settings!.highAccuracy ? "HIGH" : "MEDIUM"}');
      print('   📊 State: ${_currentBooking!.state}');
      
      // ดึงตำแหน่งปัจจุบัน
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: _settings!.highAccuracy 
          ? LocationAccuracy.high 
          : LocationAccuracy.medium,
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('GPS timeout after 5 seconds');
        },
      );

      _lastPosition = position;
      _lastUpdateTime = DateTime.now();

      // แปลงความเร็วจาก m/s เป็น km/h
      final speedKmh = position.speed * 3.6;

      print('   ✅ GPS Position obtained:');
      print('   🌐 Lat: ${position.latitude.toStringAsFixed(6)}');
      print('   🌐 Lng: ${position.longitude.toStringAsFixed(6)}');
      print('   🎯 Accuracy: ${position.accuracy.toStringAsFixed(1)}m');
      print('   🚗 Speed: ${speedKmh.toStringAsFixed(1)} km/h');
      print('   🧭 Heading: ${position.heading.toStringAsFixed(0)}°');
      print('   🏔️  Altitude: ${position.altitude.toStringAsFixed(0)}m');

      // ดึงข้อมูล battery
      final battery = Battery();
      final batteryLevel = await battery.batteryLevel;
      print('   🔋 Battery: $batteryLevel%');

      // ดึงที่อยู่ (optional)
      String? address;
      try {
        print('   📮 Getting address from coordinates...');
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        ).timeout(
          const Duration(seconds: 10),
          onTimeout: () => <Placemark>[],
        );
        
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          address = '${place.street ?? ''}, ${place.subLocality ?? ''}, ${place.locality ?? ''}';
          print('   ✅ Address: $address');
        } else {
          print('   ⚠️  No address found for coordinates');
        }
      } catch (e) {
        print('   ⚠️  Could not get address: $e');
      }

      print('');
      print('📤 [Tracking] Sending location to Odoo API...');
      print('   🌐 Endpoint: /api/tracking/update_location');
      print('   📦 Booking ID: ${_currentBooking!.id}');
      
      // ส่งตำแหน่งไปยัง Odoo และรับข้อมูลเพิ่มเติม
      final response = await _odooService.updateLocationWithResponse(
        bookingId: _currentBooking!.id,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        speed: speedKmh,
        heading: position.heading,
        altitude: position.altitude,
        batteryLevel: batteryLevel.toDouble(),
        address: address,
      );

      print('   📡 Response received:');
      print('      - Success: ${response['success']}');
      print('      - Message: ${response['message']}');
      print('      - Should stop: ${response['should_stop_tracking']}');
      
      if (response['success'] == true) {
        print('   ✅ Location sent successfully to Odoo!');
        print('   ⏰ Update time: ${DateTime.now().toString()}');
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      } else if (response['should_stop_tracking'] == true) {
        print('   🛑 Server indicated booking is DONE');
        print('   📍 Saving final map with ${response['final_map_data']?['tracking_count'] ?? 0} tracking points');
        print('   💾 Stopping tracking automatically...');
        _saveFinalMap(response['final_map_data']);
        stopTracking();
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      } else {
        print('   ❌ Failed to send location to Odoo');
        print('   💡 Check: Network connection, Odoo server, authentication');
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      }
      
    } on TimeoutException catch (e) {
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('⏱️  [Tracking] GPS TIMEOUT');
      print('   Error: $e');
      print('   💡 GPS might be weak or blocked');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    } catch (e, stackTrace) {
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('❌ [Tracking] ERROR sending location');
      print('   Error: $e');
      print('   Stack trace: $stackTrace');
      print('   💡 Possible causes:');
      print('      - GPS permission revoked');
      print('      - Network connection lost');
      print('      - Odoo server unreachable');
      print('      - Authentication expired');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    }
  }

  // บันทึกแผนที่สุดท้าย
  void _saveFinalMap(Map<String, dynamic>? mapData) {
    if (mapData == null) {
      print('⚠️ [Tracking] No map data to save');
      return;
    }
    
    try {
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('💾 [Tracking] Saving final map for booking: ${_currentBooking?.name}');
      print('   📍 Tracking points: ${mapData['tracking_count'] ?? 0}');
      
      final startPoint = mapData['start_point'] as Map<String, dynamic>?;
      final endPoint = mapData['end_point'] as Map<String, dynamic>?;
      final route = mapData['route'] as List<dynamic>?;
      
      if (startPoint != null) {
        print('   📍 Start: ${startPoint['address']}');
        print('      (${startPoint['latitude']}, ${startPoint['longitude']})');
      }
      
      if (endPoint != null) {
        print('   📍 End: ${endPoint['address']}');
        print('      (${endPoint['latitude']}, ${endPoint['longitude']})');
      }
      
      if (route != null && route.isNotEmpty) {
        print('   📊 Route points: ${route.length}');
      }
      
      // TODO: บันทึกแผนที่เป็นไฟล์ JSON หรือเก็บใน local database
      // สามารถบันทึกตำแหน่ง: /sdcard/Android/data/[package_name]/cache/
      // หรือใช้ SharedPreferences
      
      print('   ✅ Final map data prepared for display/export');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    } catch (e) {
      print('❌ [Tracking] Error saving final map: $e');
    }
  }

  // ตรวจสอบ permission
  Future<bool> _checkLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print('❌ [Tracking] Location services are disabled');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        print('❌ [Tracking] Location permissions are denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      print('❌ [Tracking] Location permissions are permanently denied');
      return false;
    }

    print('✅ [Tracking] Location permission granted');
    return true;
  }

  // ส่งตำแหน่งทันที (Manual update)
  Future<bool> sendLocationNow() async {
    if (_currentBooking == null) {
      print('❌ [Tracking] No active booking');
      return false;
    }

    await _sendCurrentLocation();
    return true;
  }

  // ดึงตำแหน่งล่าสุดจาก Odoo
  Future<Map<String, dynamic>?> getLastTrackedLocation() async {
    if (_currentBooking == null) {
      print('❌ [Tracking] No active booking');
      return null;
    }

    return await _odooService.getLatestLocation(_currentBooking!.id);
  }

  // เช็คสถานะการติดตาม
  String getTrackingStatus() {
    if (!_isTracking) {
      return 'ไม่ได้ติดตาม';
    }

    if (_lastUpdateTime == null) {
      return 'กำลังเริ่มต้น...';
    }

    final timeSinceUpdate = DateTime.now().difference(_lastUpdateTime!);
    if (timeSinceUpdate.inSeconds < 60) {
      return 'อัปเดตล่าสุด ${timeSinceUpdate.inSeconds} วินาทีที่แล้ว';
    } else if (timeSinceUpdate.inMinutes < 60) {
      return 'อัปเดตล่าสุด ${timeSinceUpdate.inMinutes} นาทีที่แล้ว';
    } else {
      return 'อัปเดตล่าสุด ${timeSinceUpdate.inHours} ชั่วโมงที่แล้ว';
    }
  }

  // Cleanup
  void dispose() {
    stopTracking();
  }

  // ❌ getUserSettings และ updateUserSettings ไม่ใช้แล้ว 
  // ใช้การตั้งค่าจาก Odoo18 โดยตรง

  // ดึงประวัติการติดตาม
  Future<List<Map<String, dynamic>>> getTrackingHistory({
    required int bookingId,
    int hours = 24,
  }) async {
    try {
      return await _odooService.getTrackingHistory(
        bookingId: bookingId,
        hours: hours,
      );
    } catch (e) {
      print('❌ [Tracking] Error getting tracking history: $e');
      return [];
    }
  }

  // อัปเดตตำแหน่ง (manual)
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
    try {
      return await _odooService.updateLocation(
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
    } catch (e) {
      print('❌ [Tracking] Error updating location: $e');
      return false;
    }
  }

  // อัปเดตสถานะการติดตาม
  Future<bool> updateTrackingStatus(bool enabled) async {
    try {
      if (enabled && _currentBooking != null) {
        return await startTracking(_currentBooking!);
      } else if (!enabled) {
        stopTracking();
        return true;
      }
      return false;
    } catch (e) {
      print('❌ [Tracking] Error updating tracking status: $e');
      return false;
    }
  }
}
