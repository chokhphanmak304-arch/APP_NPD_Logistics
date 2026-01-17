import 'package:flutter/services.dart';

/// Helper class to protect app from being killed during camera usage
/// Especially when screen recording app is running
class CameraProtectionService {
  static const platform = MethodChannel('com.npd.transport/camera');
  
  /// Start foreground service protection before opening camera
  /// Call this BEFORE opening image picker
  static Future<bool> startProtection() async {
    try {
      print('🛡️ [CameraProtection] Starting foreground service');
      final result = await platform.invokeMethod('startForeground');
      print('🛡️ [CameraProtection] Protection started: $result');
      return result == true;
    } catch (e) {
      print('❌ [CameraProtection] Failed to start: $e');
      return false;
    }
  }
  
  /// Stop foreground service protection after camera is closed
  /// Call this AFTER image picker is closed
  static Future<bool> stopProtection() async {
    try {
      print('🛡️ [CameraProtection] Stopping foreground service');
      final result = await platform.invokeMethod('stopForeground');
      print('🛡️ [CameraProtection] Protection stopped: $result');
      return result == true;
    } catch (e) {
      print('❌ [CameraProtection] Failed to stop: $e');
      return false;
    }
  }
  
  /// Convenience method to wrap camera operations with protection
  /// Example:
  /// ```dart
  /// final file = await CameraProtectionService.withProtection(() async {
  ///   return await ImagePicker().pickImage(source: ImageSource.camera);
  /// });
  /// ```
  static Future<T?> withProtection<T>(Future<T?> Function() cameraOperation) async {
    await startProtection();
    
    try {
      final result = await cameraOperation();
      return result;
    } finally {
      // Always stop protection, even if camera operation fails
      await Future.delayed(Duration(milliseconds: 500)); // Give time for camera to close
      await stopProtection();
    }
  }
}
