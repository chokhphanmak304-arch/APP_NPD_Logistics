class IncomeData {
  final int month;
  final int year;
  final double totalShippingCost;   // ค่าขนส่ง
  final double totalTravelExpenses; // ค่าเที่ยว
  final double totalDailyAllowance; // ค่าเบี้ยเลี้ยง
  final int totalDeliveries;        // จำนวนครั้ง

  double get totalIncome => totalTravelExpenses + totalDailyAllowance;  // ✅ เอาแค่ เที่ยว + เบี้ยเลี้ยง

  IncomeData({
    required this.month,
    required this.year,
    required this.totalShippingCost,
    required this.totalTravelExpenses,
    required this.totalDailyAllowance,
    required this.totalDeliveries,
  });

  String get monthName {
    const months = [
      'มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน',
      'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม'
    ];
    return months[month - 1];
  }

  // ✅ รอบจ่ายเงิน: วันที่ 25 ของเดือนก่อน ถึง วันที่ 24 ของเดือนนี้
  // เช่น รอบ "มิถุนายน" = 25/05 ถึง 24/06
  DateTime get periodStart => DateTime(year, month - 1, 25);
  DateTime get periodEnd => DateTime(year, month, 24);

  // แสดงช่วงวันที่ของรอบ เช่น "25 พ.ค. – 24 มิ.ย. 2025"
  String get periodText {
    const shortMonths = [
      'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
      'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'
    ];
    final start = periodStart;
    final end = periodEnd;
    final startStr = '${start.day} ${shortMonths[start.month - 1]}';
    // ✅ ปี พ.ศ. = ค.ศ. + 543
    final endStr = '${end.day} ${shortMonths[end.month - 1]} ${end.year + 543}';
    return '$startStr – $endStr';
  }

  // ✅ ปี พ.ศ. = ค.ศ. + 543
  String get displayText => '$monthName ${year + 543}';

  @override
  String toString() => 'IncomeData(month: $month, year: $year, totalIncome: $totalIncome)';
}