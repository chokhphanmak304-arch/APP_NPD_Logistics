class DeliveryHistory {
  final int id;
  final String name;
  final DateTime completionDate;
  final String? partnerName;
  final String? driverName;
  final String? vehicleName;
  final String? pickupLocation;
  final String? destination;
  final double? distanceKm;
  final double? durationHours;
  final double? shippingCost;
  final double? totalWeightOrder; // น้ำหนักรวม (กก.)
  final String state; // completed, cancelled
  final DateTime? plannedStartDate;
  final DateTime? actualPickupTime;
  final DateTime? actualDeliveryTime;
  final String? receiverName;
  final String? pickupPhoto;
  final String? deliveryPhoto;
  final String? receiverSignature;
  // ✅ เพิ่มฟิวด์ใหม่
  final DateTime? plannedStartDateT; // เวลาออกเดินทางจริง
  final DateTime? plannedEndDateT;   // เวลาส่งจริง
  final double? travelExpenses; // ค่าเที่ยว
  final double? dailyAllowance; // ค่าเบี้ยเลี้ยง
  final String? estimatedTime; // ✅ เวลาโดยประมาณ

  DeliveryHistory({
    required this.id,
    required this.name,
    required this.completionDate,
    this.partnerName,
    this.driverName,
    this.vehicleName,
    this.pickupLocation,
    this.destination,
    this.distanceKm,
    this.durationHours,
    this.shippingCost,
    this.totalWeightOrder,
    required this.state,
    this.plannedStartDate,
    this.actualPickupTime,
    this.actualDeliveryTime,
    this.receiverName,
    this.pickupPhoto,
    this.deliveryPhoto,
    this.receiverSignature,
    // ✅ เพิ่มพารามิเตอร์ใหม่
    this.plannedStartDateT,
    this.plannedEndDateT,
    this.travelExpenses,
    this.dailyAllowance,
    this.estimatedTime,
  });

  factory DeliveryHistory.fromJson(Map<String, dynamic> json) {
    print('🆕 [DeliveryHistory.fromJson] Starting to parse: ${json['name']}');
    print('   Input JSON keys: ${json.keys.toList()}');
    print('   daily_allowance from JSON: ${json['daily_allowance']}');
    
    // Helper function to safely convert to String
    String? _safeString(dynamic value) {
      if (value == null || value == false) return null;
      if (value is String) return value;
      return value.toString();
    }
    
    // Helper function for required String fields
    String _requiredString(dynamic value, String fieldName) {
      if (value == null || value == false) {
        print('⚠️ Warning: Required field "$fieldName" is null or false, using "Unknown"');
        return 'Unknown';
      }
      if (value is String) return value;
      return value.toString();
    }
    
    // 🆕 Helper สำหรับ parse driver_name ที่อาจเป็น array หรือ string
    String? _parseDriverName(dynamic driverIdField, dynamic driverNameField) {
      // ลองใช้จาก driver_id array ก่อน [id, name]
      if (driverIdField is List && driverIdField.length > 1) {
        return driverIdField[1].toString();
      }
      // ถ้าไม่ได้ ใช้จาก driver_name
      return _safeString(driverNameField);
    }
    
    // 🆕 Helper function to parse DateTime and convert from UTC to Thailand timezone
    DateTime? _parseDateTime(dynamic value) {
      if (value == null || value == false) return null;
      try {
        // Odoo ส่งมาเป็น ISO format เช่น "2025-11-21T13:00:25" (UTC)
        // ต้องแปลงเป็น Thailand time (UTC+7)
        final dateString = value as String;
        
        // Parse as UTC ด้วยการเพิ่ม 'Z'
        DateTime utcDate;
        if (dateString.contains('T') && !dateString.endsWith('Z')) {
          // ISO format "2025-11-21T13:00:25" → เพิ่ม Z ให้เป็น UTC
          utcDate = DateTime.parse(dateString + 'Z');
        } else if (dateString.contains(' ') && !dateString.contains('T')) {
          // Format "2025-11-21 13:00:25" → แปลงเป็น ISO แล้วเพิ่ม Z
          final isoFormat = dateString.replaceAll(' ', 'T');
          utcDate = DateTime.parse(isoFormat + 'Z');
        } else {
          // อื่น ๆ parse ตรง ๆ
          utcDate = DateTime.parse(dateString);
        }
        
        // Convert UTC to Thailand timezone (UTC+7)
        final bangkokDate = utcDate.add(const Duration(hours: 7));
        
        print('🕐 Parse: $dateString → UTC: $utcDate → Bangkok (+7): $bangkokDate');
        
        return bangkokDate;
      } catch (e) {
        print('⚠️ Error parsing date: $value, error: $e');
        return null;
      }
    }

    // 🆕 สร้าง result object
    final result = DeliveryHistory(
      id: json['id'] as int,
      name: _requiredString(json['name'], 'name'),
      completionDate: _parseDateTime(json['completion_date']) ?? DateTime.now(),
      partnerName: _safeString(json['partner_name']),
      driverName: _parseDriverName(json['driver_id'], json['driver_name']),  // ✅ ใช้ helper
      vehicleName: _safeString(json['vehicle_name']),
      pickupLocation: _safeString(json['pickup_location']),
      destination: _safeString(json['destination']),
      distanceKm: json['distance_km'] != null 
          ? (json['distance_km'] as num).toDouble() 
          : null,
      durationHours: json['duration_hours'] != null
          ? (json['duration_hours'] as num).toDouble()
          : null,
      shippingCost: json['shipping_cost'] != null
          ? (json['shipping_cost'] as num).toDouble()
          : null,
      totalWeightOrder: json['total_weight_order'] != null && json['total_weight_order'] != false
          ? (json['total_weight_order'] as num).toDouble()
          : null,
      state: _requiredString(json['state'], 'state'),
      plannedStartDate: _parseDateTime(json['planned_start_date']),
      actualPickupTime: _parseDateTime(json['actual_pickup_time']),
      actualDeliveryTime: _parseDateTime(json['actual_delivery_time']),
      receiverName: _safeString(json['receiver_name']),
      pickupPhoto: _safeString(json['pickup_photo']),
      deliveryPhoto: _safeString(json['delivery_photo']),
      receiverSignature: _safeString(json['receiver_signature']),
      // ✅ เพิ่มการ parse ฟิวด์ใหม่
      plannedStartDateT: _parseDateTime(json['planned_start_date_t']),
      plannedEndDateT: _parseDateTime(json['planned_end_date_t']),
      travelExpenses: json['travel_expenses'] != null
          ? (json['travel_expenses'] as num).toDouble()
          : null,
      dailyAllowance: json['daily_allowance'] != null
          ? (json['daily_allowance'] as num).toDouble()
          : null,
      estimatedTime: json['estimated_time'] != null && json['estimated_time'] != false
          ? (json['estimated_time'] as String)
          : null,
    );
    
    // 🆕 DEBUG: Print ค่าเบี้ยเลี้ยง
    print('💰 [DeliveryHistory] Parsed:');
    print('   - Name: ${result.name}');
    print('   - Travel Expenses: ${result.travelExpenses}');
    print('   - Daily Allowance: ${result.dailyAllowance}');
    print('   - Shipping Cost: ${result.shippingCost}');
    print('   - daily_allowance from JSON: ${json['daily_allowance']}');
    print('   - Type of daily_allowance: ${json['daily_allowance']?.runtimeType}');
    
    return result;
  }
  String toString() {
    return '''DeliveryHistory(
      id: $id,
      name: $name,
      travel_expenses: $travelExpenses,
      daily_allowance: $dailyAllowance,
      planned_start_date_t: $plannedStartDateT,
      planned_end_date_t: $plannedEndDateT,
    )''';
  }

  String getStateText() {
    switch (state) {
      case 'completed':
        return '✅ เสร็จสิ้น';
      case 'cancelled':
        return '❌ ยกเลิก';
      default:
        return state;
    }
  }

  String getStateIcon() {
    switch (state) {
      case 'completed':
        return '✅';
      case 'cancelled':
        return '❌';
      default:
        return '📦';
    }
  }
}
