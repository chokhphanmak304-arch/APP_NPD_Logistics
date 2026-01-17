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

  String get displayText => '$monthName $year';

  @override
  String toString() => 'IncomeData(month: $month, year: $year, totalIncome: $totalIncome)';
}