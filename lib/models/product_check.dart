/// รายการสินค้าที่คนขับต้องตรวจนับก่อนถ่ายรูปและออกรถ
///
/// ฝั่ง Odoo เป็นคนตัดสินว่าตรวจครบหรือยัง (can_take_photo) แอปไม่คำนวณเอง
/// ถ้าคำนวณสองที่แล้วแก้ข้างเดียว จะเพี้ยนกันโดยไม่มีใครรู้
class ProductCheckLine {
  final int lineId;
  final String productName;
  final double quantity;
  final String uom;
  final double weight;

  /// pending = ยังไม่ตรวจ, correct = ถูกต้อง, incorrect = ไม่ถูกต้อง
  String checkState;
  double checkedQuantity;
  String note;

  ProductCheckLine({
    required this.lineId,
    required this.productName,
    required this.quantity,
    required this.uom,
    required this.weight,
    this.checkState = 'pending',
    this.checkedQuantity = 0,
    this.note = '',
  });

  factory ProductCheckLine.fromJson(Map<String, dynamic> json) {
    return ProductCheckLine(
      lineId: json['line_id'] ?? 0,
      productName: json['product_name'] ?? '',
      quantity: (json['quantity'] ?? 0).toDouble(),
      uom: json['uom'] ?? '',
      weight: (json['weight'] ?? 0).toDouble(),
      checkState: json['check_state'] ?? 'pending',
      checkedQuantity: (json['checked_quantity'] ?? 0).toDouble(),
      note: json['check_note'] ?? '',
    );
  }

  bool get isChecked => checkState != 'pending';
  bool get isCorrect => checkState == 'correct';
  bool get isIncorrect => checkState == 'incorrect';

  /// ผลต่างที่คนขับเห็น — แสดงเฉพาะตอนกดว่าไม่ถูกต้อง
  double get diff => isIncorrect ? checkedQuantity - quantity : 0;

  Map<String, dynamic> toPayload() => {
        'line_id': lineId,
        'is_correct': isCorrect,
        if (!isCorrect) 'checked_quantity': checkedQuantity,
        if (note.isNotEmpty) 'note': note,
      };
}

/// สรุปผลตรวจของทั้งใบ — ค่าที่ใช้เปิด/ปิดปุ่มกล้อง
class ProductCheckSummary {
  final int bookingId;
  final String bookingName;
  final String checkState;
  final int checked;
  final int total;
  final int mismatch;
  final bool canTakePhoto;

  ProductCheckSummary({
    required this.bookingId,
    required this.bookingName,
    required this.checkState,
    required this.checked,
    required this.total,
    required this.mismatch,
    required this.canTakePhoto,
  });

  factory ProductCheckSummary.fromJson(Map<String, dynamic> json) {
    return ProductCheckSummary(
      bookingId: json['booking_id'] ?? 0,
      bookingName: json['booking_name'] ?? '',
      checkState: json['check_state'] ?? 'pending',
      checked: json['checked'] ?? 0,
      total: json['total'] ?? 0,
      mismatch: json['mismatch'] ?? 0,
      canTakePhoto: json['can_take_photo'] ?? false,
    );
  }

  /// ไม่มีรายการสินค้าให้ตรวจ ก็ไม่ต้องแสดงการ์ดตรวจนับให้รก
  bool get hasLines => total > 0;

  String get progressText => '$checked จาก $total รายการ';
}
