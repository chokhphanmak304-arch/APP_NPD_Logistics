import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:url_launcher/url_launcher.dart';

/// 🔔 บริการตรวจสอบเวอร์ชันใหม่ผ่าน Google Play (In-App Update API)
///
/// Google Play จะรู้เองว่ามีเวอร์ชันใหม่ที่ "อนุมัติและเผยแพร่แล้ว" หรือยัง
/// (ใช้ได้เฉพาะแอปที่ติดตั้งจาก Play Store เท่านั้น — debug/sideload จะถูกข้ามไป)
class UpdateService {
  static bool _checkedThisSession = false;

  /// ลิงก์หน้าแอปบน Play Store (ใช้เป็น fallback เปิดหน้าอัปเดต)
  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.npd.npd_transport_app';

  /// 📝 สรุปสิ่งที่ปรับปรุงในเวอร์ชันนี้ (แก้ข้อความนี้ทุกครั้งก่อนปล่อยรุ่นใหม่)
  ///    ไม่ต้องใส่อีโมจิ — แสดงเป็นรายการในป๊อปอัปแจ้งเตือนอัปเดต
  static const List<String> releaseHighlights = [
    'ปรับดีไซน์หน้าหลัก รายได้ และประวัติการจัดส่งให้ทันสมัยขึ้น',
    'แสดงรายได้ตามรอบจ่ายเงิน (25 ถึง 24) พร้อมรายการในแต่ละรอบ',
    'เพิ่มการแจ้งเตือนเมื่อมีงานใหม่',
    'แก้ไขข้อบกพร่องและปรับปรุงความเสถียร',
  ];

  /// ตรวจสอบและแสดง popup ถ้ามีเวอร์ชันใหม่
  /// เรียกครั้งเดียวต่อรอบการเปิดแอป (กันเด้งซ้ำ)
  static Future<void> checkForUpdate(
    BuildContext context, {
    bool force = false,
  }) async {
    if (_checkedThisSession && !force) return;
    _checkedThisSession = true;

    try {
      final info = await InAppUpdate.checkForUpdate();

      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        return;
      }

      if (!context.mounted) return;

      // แสดง popup แบบกำหนดเองก่อน แล้วค่อยเริ่ม flow อัปเดตของ Google
      final shouldUpdate = await _showUpdateDialog(
        context,
        flexibleAllowed: info.flexibleUpdateAllowed,
        immediateAllowed: info.immediateUpdateAllowed,
      );

      if (shouldUpdate != true) return;

      // ใช้ Immediate update ถ้าทำได้ (เต็มจอ ปลอดภัยสุด) ไม่งั้นใช้ Flexible
      // ถ้า in-app update ทำไม่สำเร็จ → เปิดหน้า Play Store แทน
      try {
        if (info.immediateUpdateAllowed) {
          await InAppUpdate.performImmediateUpdate();
        } else if (info.flexibleUpdateAllowed) {
          await InAppUpdate.startFlexibleUpdate();
          await InAppUpdate.completeFlexibleUpdate();
        } else {
          await openPlayStore();
        }
      } catch (e) {
        debugPrint('ℹ️ [UpdateService] in-app update ล้มเหลว เปิด Play Store แทน: $e');
        await openPlayStore();
      }
    } catch (e) {
      // ปกติจะ throw เมื่อ build แบบ debug หรือไม่ได้ติดตั้งจาก Play Store
      debugPrint('ℹ️ [UpdateService] ข้ามการเช็คอัปเดต: $e');
    }
  }

  /// เปิดหน้าแอปบน Play Store (fallback)
  static Future<void> openPlayStore() async {
    try {
      await launchUrl(
        Uri.parse(playStoreUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('ℹ️ [UpdateService] เปิด Play Store ไม่สำเร็จ: $e');
    }
  }

  static Future<bool?> _showUpdateDialog(
    BuildContext context, {
    required bool flexibleAllowed,
    required bool immediateAllowed,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade400, Colors.blue.shade700],
                  ),
                ),
                child: const Icon(
                  Icons.system_update_rounded,
                  size: 44,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'มีเวอร์ชันใหม่พร้อมให้อัปเดต',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                'อัปเดตเพื่อรับฟีเจอร์ใหม่และการแก้ไขล่าสุด '
                'เพื่อประสบการณ์ใช้งานที่ดีที่สุด',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              ),
              if (releaseHighlights.isNotEmpty) ...[
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'สิ่งที่ปรับปรุงในเวอร์ชันนี้',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...releaseHighlights.map(
                        (text) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 5),
                                child: Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade400,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  text,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade800,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('อัปเดตเลย'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              // อนุญาตให้เลื่อนไว้ทีหลังเฉพาะกรณี flexible (ไม่บังคับ)
              if (!immediateAllowed && flexibleAllowed) ...[
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(
                    'ภายหลัง',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
