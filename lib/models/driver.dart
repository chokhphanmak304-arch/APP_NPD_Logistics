class Driver {
  final int id;
  final String name;
  final String code;
  final String pin;
  final String phone;
  final String? email;
  final bool active;
  final String employmentStatus;
  final String licenseNumber;
  final String licenseType;
  final int? branchId;
  final String? branchName;

  /// รูปโปรไฟล์เป็น base64 ของฟิลด์ image_256 บน vehicle.driver ใน Odoo
  /// (ฟิลด์เดียวกับหน้า "ผู้ขับขี่" รูปจึงตรงกันทั้งสองฝั่งเสมอ)
  /// null = ยังไม่เคยใส่รูป ให้แอปแสดงไอคอนคนแทน
  final String? imageBase64;

  Driver({
    required this.id,
    required this.name,
    required this.code,
    required this.pin,
    required this.phone,
    this.email,
    required this.active,
    required this.employmentStatus,
    required this.licenseNumber,
    required this.licenseType,
    this.branchId,
    this.branchName,
    this.imageBase64,
  });

  factory Driver.fromJson(Map<String, dynamic> json) {
    // Helper function to safely convert to String
    String _safeString(dynamic value) {
      if (value == null || value == false) return '';
      if (value is String) return value;
      return value.toString();
    }
    
    // Helper function for nullable String
    String? _safeStringNullable(dynamic value) {
      if (value == null || value == false) return null;
      if (value is String) return value;
      return value.toString();
    }

    return Driver(
      id: json['id'] ?? 0,
      name: _safeString(json['name']),
      code: _safeString(json['code']),
      pin: _safeString(json['pin']),
      phone: _safeString(json['phone']),
      email: _safeStringNullable(json['email']),
      active: json['active'] == true,
      employmentStatus: _safeString(json['employment_status']),
      licenseNumber: _safeString(json['license_number']),
      licenseType: _safeString(json['license_type']),
      branchId: json['branch_id'] is List ? json['branch_id'][0] : json['branch_id'],
      branchName: json['branch_id'] is List && json['branch_id'].length > 1 ? json['branch_id'][1] : null,
      // Odoo ส่ง false (ไม่ใช่ null) เมื่อฟิลด์ binary ว่าง _safeStringNullable
      // แปลงให้เป็น null ให้แล้ว รับทั้ง image_256 และชื่อ image ธรรมดา
      imageBase64: _safeStringNullable(json['image_256'] ?? json['image']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'code': code,
      'pin': pin,
      'phone': phone,
      'email': email,
      'active': active,
      'employment_status': employmentStatus,
      'license_number': licenseNumber,
      'license_type': licenseType,
      'branch_id': branchId,
      'branch_name': branchName,
      'image_256': imageBase64,
    };
  }

  /// ใช้ตอนคนขับเปลี่ยนรูปแล้วต้องอัปเดตหน้าจอทันที โดยไม่ต้อง login ใหม่
  /// ส่ง clearImage: true เมื่อสั่งลบรูป เพราะ imageBase64: null เฉย ๆ
  /// แยกไม่ออกจาก "ไม่ได้ส่งค่ามา"
  Driver copyWith({String? imageBase64, bool clearImage = false}) {
    return Driver(
      id: id,
      name: name,
      code: code,
      pin: pin,
      phone: phone,
      email: email,
      active: active,
      employmentStatus: employmentStatus,
      licenseNumber: licenseNumber,
      licenseType: licenseType,
      branchId: branchId,
      branchName: branchName,
      imageBase64: clearImage ? null : (imageBase64 ?? this.imageBase64),
    );
  }
}
