class TrackingSettings {
  final bool trackingEnabled;
  final int trackingInterval; // ⚠️ เก็บเป็นวินาที (seconds) - แปลงจากนาทีของ Odoo ใน fromJson
  final bool highAccuracy;
  final bool notifyOnArrival;
  final bool notifyOnDelay;
  final bool notifyOffRoute;
  final int offRouteDistance;
  final bool showSpeed;
  final bool showRoute;
  final String mapType;
  final bool saveHistory;
  final int historyRetentionDays;

  TrackingSettings({
    required this.trackingEnabled,
    required this.trackingInterval,
    required this.highAccuracy,
    required this.notifyOnArrival,
    required this.notifyOnDelay,
    required this.notifyOffRoute,
    required this.offRouteDistance,
    required this.showSpeed,
    required this.showRoute,
    required this.mapType,
    required this.saveHistory,
    required this.historyRetentionDays,
  });

  factory TrackingSettings.fromJson(Map<String, dynamic> json) {
    // ✅ Odoo ส่งค่าเป็นนาที แต่แอปใช้วินาที ต้องแปลง!
    // tracking_interval ใน Odoo = นาที (default 5)
    // tracking_interval ใน App = วินาที
    final intervalMinutes = json['tracking_interval'] ?? 5; // default 5 นาที
    final intervalSeconds = intervalMinutes * 60; // แปลงเป็นวินาที
    
    return TrackingSettings(
      trackingEnabled: json['tracking_enabled'] ?? true,
      trackingInterval: intervalSeconds, // ✅ ใช้ค่าที่แปลงแล้ว (วินาที)
      highAccuracy: json['high_accuracy'] ?? true,
      notifyOnArrival: json['notify_on_arrival'] ?? true,
      notifyOnDelay: json['notify_on_delay'] ?? true,
      notifyOffRoute: json['notify_off_route'] ?? true,
      offRouteDistance: json['off_route_distance'] ?? 500,
      showSpeed: json['show_speed'] ?? true,
      showRoute: json['show_route'] ?? true,
      mapType: json['map_type'] ?? 'roadmap',
      saveHistory: json['save_history'] ?? true,
      historyRetentionDays: json['history_retention_days'] ?? 30,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tracking_enabled': trackingEnabled,
      'tracking_interval': trackingInterval,
      'high_accuracy': highAccuracy,
      'notify_on_arrival': notifyOnArrival,
      'notify_on_delay': notifyOnDelay,
      'notify_off_route': notifyOffRoute,
      'off_route_distance': offRouteDistance,
      'show_speed': showSpeed,
      'show_route': showRoute,
      'map_type': mapType,
      'save_history': saveHistory,
      'history_retention_days': historyRetentionDays,
    };
  }

  // Default settings
  factory TrackingSettings.defaultSettings() {
    return TrackingSettings(
      trackingEnabled: true,
      trackingInterval: 30,
      highAccuracy: true,
      notifyOnArrival: true,
      notifyOnDelay: true,
      notifyOffRoute: true,
      offRouteDistance: 500,
      showSpeed: true,
      showRoute: true,
      mapType: 'roadmap',
      saveHistory: true,
      historyRetentionDays: 30,
    );
  }
}
