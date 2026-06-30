import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 🔔 บริการแจ้งเตือนงานใหม่ขึ้นแถบแจ้งเตือนของมือถือ
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'new_jobs_channel';
  static const String _channelName = 'งานใหม่';
  static const String _channelDesc = 'แจ้งเตือนเมื่อมีงานจัดส่งใหม่';

  static bool _initialized = false;

  /// เรียกครั้งเดียวตอนเริ่มแอป
  static Future<void> init() async {
    if (_initialized) return;

    const androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    await _plugin.initialize(initSettings);

    // สร้าง channel (Android 8+)
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _initialized = true;
  }

  /// ขอสิทธิ์แจ้งเตือน (Android 13+)
  static Future<void> requestPermission() async {
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('ℹ️ [NotificationService] requestPermission: $e');
    }
  }

  /// แสดงแจ้งเตือนงานใหม่
  /// [addedCount] = จำนวนงานที่เพิ่มขึ้น, [totalCount] = จำนวนคิวที่ต้องส่งทั้งหมด
  static Future<void> showNewJob(int addedCount, int totalCount) async {
    if (!_initialized) await init();

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const details = NotificationDetails(android: androidDetails);

    final body = totalCount > 0
        ? 'คุณมีงานที่ต้องส่งทั้งหมด $totalCount งาน'
        : 'มีงานจัดส่งใหม่เข้ามา';

    await _plugin.show(
      0, // id เดิม = แทนที่ของเก่า ไม่สแปม
      addedCount > 1 ? 'มีงานใหม่ $addedCount งาน' : 'มีงานใหม่',
      body,
      details,
    );
  }
}
