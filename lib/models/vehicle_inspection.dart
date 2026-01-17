/// 🚗 Model สำหรับข้อมูลการตรวจสอบสภาพรถ
class VehicleInspectionItem {
  final String id;
  final String title;
  final String standard;
  bool isChecked;
  String? note;
  String? imagePath;
  bool requirePhoto;
  bool isMaintenanceItem; // สำหรับข้อ 21-24

  VehicleInspectionItem({
    required this.id,
    required this.title,
    required this.standard,
    this.isChecked = false,
    this.note,
    this.imagePath,
    this.requirePhoto = true,
    this.isMaintenanceItem = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'standard': standard,
    'isChecked': isChecked,
    'note': note,
    'imagePath': imagePath,
    'requirePhoto': requirePhoto,
    'isMaintenanceItem': isMaintenanceItem,
  };
}

/// 🔧 Model สำหรับรายการบำรุงรักษา (ข้อ 21-24)
class MaintenanceItem {
  final String id;
  final String title;
  bool? isDue; // null = ยังไม่เลือก, true = ครบกำหนด, false = ยังไม่ครบกำหนด
  String currentMileage;
  String lastChangeMileage;

  MaintenanceItem({
    required this.id,
    required this.title,
    this.isDue,
    this.currentMileage = '',
    this.lastChangeMileage = '',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'isDue': isDue,
    'currentMileage': currentMileage,
    'lastChangeMileage': lastChangeMileage,
  };
}
