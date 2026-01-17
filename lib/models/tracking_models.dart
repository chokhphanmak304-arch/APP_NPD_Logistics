class TrackingSettings {
  final int trackingRefreshInterval;
  final bool autoCenterMap;
  final bool showRouteHistory;
  final bool showSpeedIndicator;
  final bool notificationEnabled;

  TrackingSettings({
    this.trackingRefreshInterval = 10,
    this.autoCenterMap = true,
    this.showRouteHistory = true,
    this.showSpeedIndicator = true,
    this.notificationEnabled = true,
  });

  factory TrackingSettings.fromJson(Map<String, dynamic> json) {
    return TrackingSettings(
      trackingRefreshInterval: json['tracking_refresh_interval'] ?? 10,
      autoCenterMap: json['auto_center_map'] ?? true,
      showRouteHistory: json['show_route_history'] ?? true,
      showSpeedIndicator: json['show_speed_indicator'] ?? true,
      notificationEnabled: json['notification_enabled'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tracking_refresh_interval': trackingRefreshInterval,
      'auto_center_map': autoCenterMap,
      'show_route_history': showRouteHistory,
      'show_speed_indicator': showSpeedIndicator,
      'notification_enabled': notificationEnabled,
    };
  }
}

class BookingLocation {
  final double latitude;
  final double longitude;
  final DateTime? lastUpdate;

  BookingLocation({
    required this.latitude,
    required this.longitude,
    this.lastUpdate,
  });

  factory BookingLocation.fromJson(Map<String, dynamic> json) {
    return BookingLocation(
      latitude: (json['latitude'] ?? 0.0).toDouble(),
      longitude: (json['longitude'] ?? 0.0).toDouble(),
      lastUpdate: json['last_update'] != null 
          ? DateTime.parse(json['last_update']) 
          : null,
    );
  }
}

class ActiveBooking {
  final int id;
  final String name;
  final String pickupLocation;
  final String destination;
  final String state;
  final String trackingStatus;
  final Map<String, dynamic>? vehicle;
  final Map<String, dynamic>? driver;
  final BookingLocation? currentLocation;
  final DateTime? plannedStartDate;
  final DateTime? plannedEndDate;

  ActiveBooking({
    required this.id,
    required this.name,
    required this.pickupLocation,
    required this.destination,
    required this.state,
    required this.trackingStatus,
    this.vehicle,
    this.driver,
    this.currentLocation,
    this.plannedStartDate,
    this.plannedEndDate,
  });

  factory ActiveBooking.fromJson(Map<String, dynamic> json) {
    return ActiveBooking(
      id: json['id'],
      name: json['name'] ?? '',
      pickupLocation: json['pickup_location'] ?? '',
      destination: json['destination'] ?? '',
      state: json['state'] ?? '',
      trackingStatus: json['tracking_status'] ?? '',
      vehicle: json['vehicle'],
      driver: json['driver'],
      currentLocation: json['current_location'] != null
          ? BookingLocation.fromJson(json['current_location'])
          : null,
      plannedStartDate: json['planned_start_date'] != null
          ? DateTime.parse(json['planned_start_date'])
          : null,
      plannedEndDate: json['planned_end_date'] != null
          ? DateTime.parse(json['planned_end_date'])
          : null,
    );
  }
}

class TrackingHistory {
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double speed;
  final double heading;

  TrackingHistory({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.heading,
  });

  factory TrackingHistory.fromJson(Map<String, dynamic> json) {
    return TrackingHistory(
      timestamp: DateTime.parse(json['timestamp']),
      latitude: (json['latitude'] ?? 0.0).toDouble(),
      longitude: (json['longitude'] ?? 0.0).toDouble(),
      speed: (json['speed'] ?? 0.0).toDouble(),
      heading: (json['heading'] ?? 0.0).toDouble(),
    );
  }
}
