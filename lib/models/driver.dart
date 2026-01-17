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
    };
  }
}
