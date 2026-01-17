import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class GpsService {
  static final GpsService _instance = GpsService._internal();
  factory GpsService() => _instance;
  GpsService._internal();

  // เช็คและขอ Permission
  Future<bool> checkAndRequestPermissions() async {
    print('📍 [GPS] Checking location permissions...');
    
    // เช็ค Permission สำหรับ Location
    var locationStatus = await Permission.location.status;
    
    if (locationStatus.isDenied) {
      print('🔓 [GPS] Requesting location permission...');
      locationStatus = await Permission.location.request();
    }
    
    if (locationStatus.isPermanentlyDenied) {
      print('❌ [GPS] Location permission permanently denied');
      await openAppSettings();
      return false;
    }

    if (!locationStatus.isGranted) {
      print('❌ [GPS] Location permission not granted');
      return false;
    }
    
    print('✅ [GPS] Location permission granted');

    // ✅ สำหรับ Android - ขอ Permission สำหรับ Background Location
    // ต้องขออนุญาตแยกหลังจากได้ Location Permission แล้ว
    try {
      var backgroundStatus = await Permission.locationAlways.status;
      
      if (backgroundStatus.isDenied) {
        print('🔓 [GPS] Requesting background location permission...');
        backgroundStatus = await Permission.locationAlways.request();
      }
      
      if (backgroundStatus.isPermanentlyDenied) {
        print('⚠️ [GPS] Background location permission permanently denied');
        // ไม่ return false เพราะ app ยังใช้งานได้แบบ foreground
      } else if (backgroundStatus.isGranted) {
        print('✅ [GPS] Background location permission granted');
      } else {
        print('⚠️ [GPS] Background location permission denied (app can still track in foreground)');
      }
    } catch (e) {
      print('⚠️ [GPS] Error requesting background location: $e');
      // Continue anyway as foreground tracking should still work
    }

    return locationStatus.isGranted;
  }

  // เช็คว่า GPS เปิดอยู่หรือไม่
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  // รับตำแหน่งปัจจุบัน
  Future<Position?> getCurrentPosition() async {
    try {
      // เช็คว่าเปิด Location Service หรือไม่
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      // เช็ค Permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return null;
      }

      // รับตำแหน่งปัจจุบัน
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10, // อัพเดทเมื่อเคลื่อนที่ 10 เมตร
        ),
      );
    } catch (e) {
      print('❌ Error getting current position: $e');
      return null;
    }
  }

  // Stream สำหรับติดตามตำแหน่งแบบ Real-time
  Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // อัพเดทเมื่อเคลื่อนที่ 10 เมตร
        timeLimit: Duration(seconds: 5),
      ),
    );
  }

  // คำนวณระยะทางระหว่าง 2 จุด (เมตร)
  double calculateDistance(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {
    return Geolocator.distanceBetween(startLat, startLng, endLat, endLng);
  }

  // คำนวณความเร็ว (km/h)
  double calculateSpeed(Position position) {
    // speed อยู่ในหน่วย m/s แปลงเป็น km/h
    return position.speed * 3.6;
  }
}
