import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';

class PermissionHandler {
  // ตรวจสอบสิทธิ Location และขอหากจำเป็น
  static Future<bool> requestLocationPermission(BuildContext context) async {
    try {
      print('🔐 [PermissionHandler] Checking location permission...');
      
      // ขั้นที่ 1: เช็คว่า service เปิดหรือไม่
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('❌ [PermissionHandler] Location service is disabled');
        if (context.mounted) {
          _showLocationServiceDialog(context);
        }
        return false;
      }
      print('✅ [PermissionHandler] Location service is enabled');
      
      // ขั้นที่ 2: เช็ค permission status
      LocationPermission permission = await Geolocator.checkPermission();
      print('📊 [PermissionHandler] Current permission: $permission');
      
      // ✅ ถ้าเปิดแล้ว ไม่ต้องแสดง dialog
      if (permission == LocationPermission.whileInUse || 
          permission == LocationPermission.always) {
        print('✅ [PermissionHandler] Permission already granted: $permission');
        return true;
      }
      
      // ขั้นที่ 3: ถ้ายังไม่ได้อนุญาต ให้ขอ
      if (permission == LocationPermission.denied) {
        print('⚠️ [PermissionHandler] Permission denied, requesting...');
        if (context.mounted) {
          _showPermissionDialog(context);
        }
        
        permission = await Geolocator.requestPermission();
        print('📊 [PermissionHandler] Permission result: $permission');
        
        if (permission == LocationPermission.denied) {
          print('❌ [PermissionHandler] User denied permission');
          return false;
        }
      }
      
      // ขั้นที่ 4: ถ้าปฏิเสธถาวร
      if (permission == LocationPermission.deniedForever) {
        print('❌ [PermissionHandler] Permission permanently denied');
        if (context.mounted) {
          _showPermanentlyDeniedDialog(context);
        }
        return false;
      }
      
      // ✅ สำเร็จ
      print('✅ [PermissionHandler] Permission granted successfully: $permission');
      return true;
      
    } catch (e) {
      print('❌ [PermissionHandler] Error: $e');
      return false;
    }
  }

  // Dialog: ขออนุญาต Location
  static void _showPermissionDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.location_on, color: Colors.blue, size: 24),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ขออนุญาตเข้าถึงตำแหน่ง',
                  style: TextStyle(fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'แอปนี้ต้องการ:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 12),
                _buildPermissionItem(
                  icon: Icons.check_circle,
                  title: '"อนุญาตตลอดเวลา"',
                  description: 'Allow all the time',
                  isGranted: true,
                ),
                const SizedBox(height: 8),
                _buildPermissionItem(
                  icon: Icons.info,
                  title: 'เหตุผล',
                  description: 'เพื่อติดตามตำแหน่งรถขนส่งแบบเรียลไทม์',
                  isGranted: false,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Geolocator.requestPermission();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: const Text(
                'อนุญาต',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ],
        );
      },
    );
  }

  // Dialog: Location Service ปิด
  static void _showLocationServiceDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.location_off, color: Colors.orange, size: 24),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'เปิดบริการตำแหน่ง',
                  style: TextStyle(fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: const Text(
              'กรุณาเปิดบริการตำแหน่ง (Location Services) เพื่อให้แอปสามารถติดตามตำแหน่งรถขนส่งได้',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ปิด', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Geolocator.openLocationSettings();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              child: const Text(
                'เปิดการตั้งค่า',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ],
        );
      },
    );
  }

  // Dialog: Permission ปฏิเสธถาวร
  static void _showPermanentlyDeniedDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning, color: Colors.red, size: 24),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ไม่สามารถเข้าถึงตำแหน่ง',
                  style: TextStyle(fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: const Text(
              'คุณได้ปฏิเสธการเข้าถึงตำแหน่งแบบถาวร\n\n'
              'กรุณาไปที่ การตั้งค่า > แอป > NPD Logistics > สิทธิ์ แล้วอนุญาต "ตำแหน่ง"',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ปิด', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Geolocator.openAppSettings();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              child: const Text(
                'เปิดการตั้งค่าแอป',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ],
        );
      },
    );
  }

  // Widget: แสดง permission item
  static Widget _buildPermissionItem({
    required IconData icon,
    required String title,
    required String description,
    required bool isGranted,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Icon(
              icon,
              color: isGranted ? Colors.green : Colors.blue,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    height: 1.3,
                  ),
                  softWrap: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
