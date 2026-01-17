class Booking {
  final int id;
  final String name; // เลขที่จอง
  final String state;
  final String? pickupLocation;
  final String? destination;
  final double? distanceKm;
  final double? shippingCost;
  final double? totalWeightOrder; // น้ำหนักรวม (กก.)
  final String? partnerName;
  final String? deliveryEmployeeName;
  final DateTime? plannedStartDate; // วันเวลาที่วางแผนออกเดินทาง (UTC+7)
  final DateTime? plannedEndDate;
  final DateTime? plannedStartDateT; // ✅ เวลาออกเดินทางจริง (บันทึกจากแอป)
  final DateTime? plannedEndDateT;   // ✅ เวลาส่งถึงจริง (บันทึกจากแอป)
  final DateTime? actualStartDateTime; // วันเวลาออกเดินทางจริง (เวลาปัจจุบัน)
  final double? travelExpenses; // ค่าเที่ยว
  final double? dailyAllowance; // ค่าเบี้ยเลี้ยง
  final String? estimatedTime; // ✅ เวลาโดยประมาณ (เช่น "2 ชั่วโมง 30 นาที")
  final String? vehicleName;
  final String? note;
  final String? pickupPhoto;
  final String? deliveryPhoto;
  final String? receiverSignature;
  final String? receiverName;
  
  // GPS Coordinates
  final double? pickupLatitude;
  final double? pickupLongitude;
  final double? destinationLatitude;
  final double? destinationLongitude;

  Booking({
    required this.id,
    required this.name,
    required this.state,
    this.pickupLocation,
    this.destination,
    this.distanceKm,
    this.shippingCost,
    this.totalWeightOrder,
    this.partnerName,
    this.deliveryEmployeeName,
    this.plannedStartDate,
    this.plannedEndDate,
    this.plannedStartDateT,
    this.plannedEndDateT,
    this.actualStartDateTime,
    this.travelExpenses,
    this.dailyAllowance,
    this.estimatedTime,
    this.vehicleName,
    this.note,
    this.pickupPhoto,
    this.deliveryPhoto,
    this.receiverSignature,
    this.receiverName,
    this.pickupLatitude,
    this.pickupLongitude,
    this.destinationLatitude,
    this.destinationLongitude,
  });

  factory Booking.fromJson(Map<String, dynamic> json) {
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

    // Helper function to convert UTC datetime to Thailand Time (UTC+7)
    DateTime? _convertToThailandTime(String? dateTimeString) {
      if (dateTimeString == null || dateTimeString.isEmpty) return null;
      try {
        // Parse as UTC
        final utcDateTime = DateTime.parse(dateTimeString);
        // Add 7 hours to convert to Thailand time (UTC+7)
        final localTime = utcDateTime.add(const Duration(hours: 7));
        print('✅ [Booking] Converted: $dateTimeString → $localTime (UTC+7)');
        return localTime;
      } catch (e) {
        print('⚠️ [Booking] Error converting datetime "$dateTimeString": $e');
        return null;
      }
    }

    return Booking(
      id: json['id'] as int,
      name: json['name'] != null && json['name'] != false 
          ? json['name'].toString() 
          : 'New',
      state: json['state'] != null && json['state'] != false 
          ? json['state'].toString() 
          : 'draft',
      pickupLocation: _safeString(json['pickup_location']),
      destination: _safeString(json['destination']),
      distanceKm: json['distance_km'] != null && json['distance_km'] != false
          ? (json['distance_km'] as num).toDouble() 
          : null,
      shippingCost: json['shipping_cost'] != null && json['shipping_cost'] != false
          ? (json['shipping_cost'] as num).toDouble()
          : null,
      totalWeightOrder: json['total_weight_order'] != null && json['total_weight_order'] != false
          ? (json['total_weight_order'] as num).toDouble()
          : null,
      partnerName: json['partner_id'] is List 
          ? _safeString((json['partner_id'] as List)[1])
          : _safeString(json['partner_id']),
      deliveryEmployeeName: _safeString(json['delivery_employee_name']),
      plannedStartDate: json['planned_start_date'] != null && json['planned_start_date'] != false && json['planned_start_date'] is String
          ? _convertToThailandTime(json['planned_start_date'])
          : null,
      plannedEndDate: json['planned_end_date'] != null && json['planned_end_date'] != false && json['planned_end_date'] is String
          ? _convertToThailandTime(json['planned_end_date'])
          : null,
      plannedStartDateT: json['planned_start_date_t'] != null && json['planned_start_date_t'] != false && json['planned_start_date_t'] is String
          ? _convertToThailandTime(json['planned_start_date_t'])
          : null,
      plannedEndDateT: json['planned_end_date_t'] != null && json['planned_end_date_t'] != false && json['planned_end_date_t'] is String
          ? _convertToThailandTime(json['planned_end_date_t'])
          : null,
      actualStartDateTime: null, // ✅ ตั้งเป็น null - จะเซตเวลาปัจจุบันเมื่อเริ่มงานที่แอป
      travelExpenses: json['travel_expenses'] != null && json['travel_expenses'] != false
          ? (json['travel_expenses'] as num).toDouble()
          : null,
      dailyAllowance: json['daily_allowance'] != null && json['daily_allowance'] != false
          ? (json['daily_allowance'] as num).toDouble()
          : null,
      estimatedTime: json['estimated_time'] != null && json['estimated_time'] != false
          ? (json['estimated_time'] as String)
          : null,
      vehicleName: json['vehicle_id'] is List
          ? _safeString((json['vehicle_id'] as List)[1])
          : _safeString(json['vehicle_id']),
      note: _safeString(json['note']),
      pickupPhoto: _safeString(json['pickup_photo']),
      deliveryPhoto: _safeString(json['delivery_photo']),
      receiverSignature: _safeString(json['receiver_signature']),
      receiverName: _safeString(json['receiver_name']),
      pickupLatitude: json['pickup_latitude'] != null && json['pickup_latitude'] != false
          ? (json['pickup_latitude'] as num).toDouble()
          : null,
      pickupLongitude: json['pickup_longitude'] != null && json['pickup_longitude'] != false
          ? (json['pickup_longitude'] as num).toDouble()
          : null,
      destinationLatitude: json['destination_latitude'] != null && json['destination_latitude'] != false
          ? (json['destination_latitude'] as num).toDouble()
          : null,
      destinationLongitude: json['destination_longitude'] != null && json['destination_longitude'] != false
          ? (json['destination_longitude'] as num).toDouble()
          : null,
    );
  }

  String getStateText() {
    switch (state) {
      case 'draft':
        return '📝 ร่าง';
      case 'confirmed':
        return '✅ ยืนยันการจอง';
      case 'in_progress':
        return '🚚 กำลังขนส่ง';
      case 'done':
        return '✔️ เสร็จสิ้น';
      case 'cancelled':
        return '❌ ยกเลิก';
      default:
        return state;
    }
  }

  // เช็คว่าสามารถเริ่มงานได้หรือไม่
  // ✅ เช็คว่าสามารถเริ่มงานได้หรือไม่ (แก้ไขเงื่อนไข: <= วันนี้)
  bool canStartJob() {
    // ต้องเป็นสถานะ confirmed
    if (state != 'confirmed') return false;
    
    // ถ้าไม่มีวันที่วางแผน → เริ่มได้เลย
    if (plannedStartDate == null) return true;
    
    // ✅ วันที่วางแผนต้อง <= วันปัจจุบัน (ถึงกำหนดหรือล่าช้าแล้ว)
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);  // เอาแค่วันที่ ไม่เอาเวลา
    final plannedDay = DateTime(
      plannedStartDate!.year,
      plannedStartDate!.month,
      plannedStartDate!.day,
    );
    
    // คืนค่า true ถ้า plannedDay <= today
    return plannedDay.isBefore(today.add(const Duration(days: 1)));  // วันที่วางแผน < พรุ่งนี้ = วันที่วางแผน <= วันนี้
  }

  // เช็คว่าเป็นงานที่กำลังทำอยู่หรือไม่
  bool isInProgress() {
    return state == 'in_progress';
  }
}
