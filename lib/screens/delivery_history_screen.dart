import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';  // 🆕 เพิ่ม import
import '../models/driver.dart';
import '../models/delivery_history.dart';
import '../services/odoo_service.dart';
import '../widgets/bottom_nav_bar.dart';

class DeliveryHistoryScreen extends StatefulWidget {
  final Driver driver;

  const DeliveryHistoryScreen({super.key, required this.driver});

  @override
  State<DeliveryHistoryScreen> createState() => _DeliveryHistoryScreenState();
}

class _DeliveryHistoryScreenState extends State<DeliveryHistoryScreen> {
  final _odooService = OdooService();
  List<DeliveryHistory> _historyList = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _filterState = 'all'; // all, completed, cancelled
  bool _localeInitialized = false;  // 🆕 เพิ่ม flag

  @override
  void initState() {
    super.initState();
    _initializeLocale();  // 🆕 Initialize locale ก่อน
  }
  
  // 🆕 Initialize Thai locale
  Future<void> _initializeLocale() async {
    try {
      await initializeDateFormatting('th_TH', null);
      setState(() {
        _localeInitialized = true;
      });
      await _loadHistory();  // โหลดข้อมูลหลัง locale พร้อม
    } catch (e) {
      print('❌ [History] Locale initialization error: $e');
      setState(() {
        _localeInitialized = true;  // ให้ทำงานต่อไปได้
      });
      await _loadHistory();
    }
  }

  Future<void> _loadHistory({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      print('🔄 [History] Loading history for driver: ${widget.driver.id}');
      
      // 📅 คำนวณวันแรกและวันสุดท้ายของเดือนปัจจุบัน
      final now = DateTime.now();
      final firstDayOfMonth = DateTime(now.year, now.month, 1);
      final lastDayOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
      
      print('📅 [History] Filter: ${DateFormat('dd/MM/yyyy').format(firstDayOfMonth)} - ${DateFormat('dd/MM/yyyy').format(lastDayOfMonth)}');
      
      final history = await _odooService.getDriverDeliveryHistory(
        widget.driver.id,
        state: _filterState == 'all' ? null : _filterState,
        startDate: firstDayOfMonth,  // 🆕 เพิ่มวันเริ่มต้น
        endDate: lastDayOfMonth,      // 🆕 เพิ่มวันสิ้นสุด
      );

      setState(() {
        _historyList = history;
        _isLoading = false;
        // ✅ DEBUG: ตรวจสอบข้อมูล travel_expenses
        for (var h in history) {
          print('📦 [History] Booking: ${h.name}');
          print('   - travel_expenses: ${h.travelExpenses}');
          print('   - estimated_time: ${h.estimatedTime}');
        }
      });

      print('✅ [History] Loaded ${history.length} records (current month only)');
    } catch (e) {
      print('❌ [History] Error: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 📅 แสดงเดือนปัจจุบัน (ปลอดภัยต่อ locale ที่ยังไม่ initialize)
    final now = DateTime.now();
    String monthName;
    
    if (_localeInitialized) {
      try {
        monthName = DateFormat('MMMM yyyy', 'th_TH').format(now);
      } catch (e) {
        print('⚠️ [History] DateFormat error: $e');
        monthName = DateFormat('MMMM yyyy').format(now);  // Fallback to default locale
      }
    } else {
      monthName = DateFormat('MMMM yyyy').format(now);  // Use default locale while initializing
    }
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📜 ประวัติการจัดส่ง',
              style: const TextStyle(
                fontFamily: 'Kanit',
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            Text(
              '📅 $monthName',
              style: const TextStyle(
                fontFamily: 'Kanit',
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFFFF9800),
        elevation: 1,
        actions: [
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadHistory,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Tabs
          _buildFilterTabs(),
          
          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? _buildErrorView()
                    : _historyList.isEmpty
                        ? _buildEmptyView()
                        : _buildHistoryList(),
          ),
        ],
      ),
      // ✅ Bottom Navigation Bar
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: 2,
        driver: widget.driver,
      ),
    );
  }

  Widget _buildFilterTabs() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildFilterChip('all', 'ทั้งหมด', Icons.list),
          const SizedBox(width: 8),
          _buildFilterChip('completed', 'เสร็จสิ้น', Icons.check_circle),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label, IconData icon) {
    final isSelected = _filterState == value;
    
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _filterState = value;
          });
          _loadHistory();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFFF9800) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? Colors.white : Colors.grey.shade600,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey.shade700,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryList() {
    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _historyList.length,
        itemBuilder: (context, index) {
          final history = _historyList[index];
          return _buildHistoryCard(history);
        },
      ),
    );
  }

  Widget _buildHistoryCard(DeliveryHistory history) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    
    // 🆕 DEBUG print
    print('📦 [HistoryCard] Building card for: ${history.name}');
    print('   - dailyAllowance: ${history.dailyAllowance}');
    print('   - travelExpenses: ${history.travelExpenses}');
    print('   - shippingCost: ${history.shippingCost}');
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _showHistoryDetail(history),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Text(
                    history.getStateIcon(),
                    style: const TextStyle(fontSize: 24),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          history.name,
                          style: const TextStyle(
                            fontFamily: 'Kanit',
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          dateFormat.format(history.completionDate),
                          style: TextStyle(
                            fontFamily: 'Kanit',
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: history.state == 'completed'
                          ? Colors.green.shade50
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: history.state == 'completed'
                            ? Colors.green.shade200
                            : Colors.red.shade200,
                      ),
                    ),
                    child: Text(
                      history.getStateText(),
                      style: TextStyle(
                        fontFamily: 'Kanit',
                        color: history.state == 'completed'
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              
              // Details
              if (history.partnerName != null)
                _buildInfoRow(Icons.business, 'ลูกค้า', history.partnerName!),
              
              if (history.pickupLocation != null)
                _buildInfoRow(Icons.location_on, 'ต้นทาง', history.pickupLocation!),
              
              if (history.destination != null)
                _buildInfoRow(Icons.flag, 'ปลายทาง', history.destination!),
              
              if (history.totalWeightOrder != null && history.totalWeightOrder! > 0)
                _buildInfoRow(
                  Icons.scale,
                  'น้ำหนักรวม',
                  '${history.totalWeightOrder!.toStringAsFixed(2)} กก.',
                  color: Colors.blue.shade700,
                ),
              
              if (history.distanceKm != null)
                _buildInfoRow(
                  Icons.straighten,
                  'ระยะทาง',
                  '${history.distanceKm!.toStringAsFixed(2)} กม.',
                ),
              
              if (history.durationHours != null && history.durationHours! > 0)
                _buildInfoRow(
                  Icons.timer,
                  'ระยะเวลา',
                  '${history.durationHours!.toStringAsFixed(1)} ชม.',
                ),
              
              if (history.shippingCost != null)
                _buildInfoRow(
                  Icons.attach_money,
                  'ค่าขนส่ง',
                  '${history.shippingCost!.toStringAsFixed(2)} บาท',
                  color: Colors.green.shade700,
                ),
              
              // ✅ เพิ่มเวลาออกเดินทางจริง
              if (history.plannedStartDateT != null)
                _buildInfoRow(
                  Icons.directions_car,
                  'ออกเดินทาง',
                  DateFormat('dd/MM/yyyy HH:mm').format(history.plannedStartDateT!),
                  color: Colors.orange.shade700,
                ),
              
              // ✅ เพิ่มเวลาส่งจริง
              if (history.plannedEndDateT != null)
                _buildInfoRow(
                  Icons.check_circle,
                  'ส่งถึง',
                  DateFormat('dd/MM/yyyy HH:mm').format(history.plannedEndDateT!),
                  color: Colors.blue.shade700,
                ),
              
              // ✅ เพิ่มค่าเที่ยว
              if (history.travelExpenses != null)
                _buildInfoRow(
                  Icons.directions_car,  // เปลี่ยนจาก local_gas_station (⛽) เป็น directions_car (🚗)
                  'ค่าเที่ยว',
                  '${history.travelExpenses!.toStringAsFixed(2)} บาท',
                  color: Colors.purple.shade700,
                ),
              // ✅ เพิ่มค่าเบี้ยเลี้ยง
              if (history.dailyAllowance != null)
                _buildInfoRow(
                  Icons.restaurant,
                  'ค่าเบี้ยเลี้ยง',
                  '${history.dailyAllowance!.toStringAsFixed(2)} บาท',
                  color: Colors.orange.shade700,
                ),
              // ✅ เพิ่ม: เวลาโดยประมาณ
              if (history.estimatedTime != null && history.estimatedTime!.isNotEmpty)
                _buildInfoRow(
                  Icons.access_time,
                  'เวลาโดยประมาณ',
                  history.estimatedTime!,
                  color: Colors.teal.shade700,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color ?? Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontFamily: 'Kanit',
                  color: Colors.grey.shade800,
                  fontSize: 13,
                ),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(
                      fontFamily: 'Kanit',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: value,
                    style: TextStyle(
                      fontFamily: 'Kanit',
                      color: color ?? Colors.grey.shade800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showHistoryDetail(DeliveryHistory history) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Text(history.getStateIcon(), style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    history.name,
                    style: const TextStyle(fontSize: 18),
                  ),
                  Text(
                    history.getStateText(),
                    style: TextStyle(
                      fontSize: 12,
                      color: history.state == 'completed'
                          ? Colors.green.shade700
                          : Colors.red.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailSection('ข้อมูลทั่วไป', [
                if (history.partnerName != null)
                  _buildDetailRow('ลูกค้า', history.partnerName!),
                if (history.vehicleName != null)
                  _buildDetailRow('รถ', history.vehicleName!),
                _buildDetailRow(
                  'เสร็จสิ้นเมื่อ',
                  dateFormat.format(history.completionDate),
                ),
              ]),
              
              const SizedBox(height: 16),
              
              _buildDetailSection('เส้นทาง', [
                if (history.pickupLocation != null)
                  _buildDetailRow('ต้นทาง', history.pickupLocation!),
                if (history.destination != null)
                  _buildDetailRow('ปลายทาง', history.destination!),
                if (history.totalWeightOrder != null && history.totalWeightOrder! > 0)
                  _buildDetailRow(
                    'น้ำหนักรวม',
                    '${history.totalWeightOrder!.toStringAsFixed(2)} กก.',
                    valueColor: Colors.blue.shade700,
                  ),
                if (history.distanceKm != null)
                  _buildDetailRow(
                    'ระยะทาง',
                    '${history.distanceKm!.toStringAsFixed(2)} กม.',
                  ),
              ]),
              
              const SizedBox(height: 16),
              
              _buildDetailSection('เวลา', [
                if (history.plannedStartDate != null)
                  _buildDetailRow(
                    'วางแผน',
                    dateFormat.format(history.plannedStartDate!),
                  ),
                if (history.actualPickupTime != null)
                  _buildDetailRow(
                    'รับสินค้า',
                    dateFormat.format(history.actualPickupTime!),
                  ),
                if (history.actualDeliveryTime != null)
                  _buildDetailRow(
                    'ส่งถึง',
                    dateFormat.format(history.actualDeliveryTime!),
                  ),
                if (history.durationHours != null && history.durationHours! > 0)
                  _buildDetailRow(
                    'ระยะเวลารวม',
                    '${history.durationHours!.toStringAsFixed(1)} ชั่วโมง',
                  ),
              ]),
              
              const SizedBox(height: 16),
              
              if (history.shippingCost != null)
                _buildDetailSection('ค่าใช้จ่าย', [
                  _buildDetailRow(
                    'ค่าขนส่ง',
                    '${history.shippingCost!.toStringAsFixed(2)} บาท',
                    valueColor: Colors.green.shade700,
                  ),
                  // ✅ เพิ่มค่าเที่ยว
                  if (history.travelExpenses != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _buildDetailRow(
                        'ค่าเที่ยว',
                        '${history.travelExpenses!.toStringAsFixed(2)} บาท',
                        valueColor: Colors.purple.shade700,
                      ),
                    ),
                  // ✅ เพิ่มค่าเบี้ยเลี้ยง
                  if (history.dailyAllowance != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _buildDetailRow(
                        'ค่าเบี้ยเลี้ยง',
                        '${history.dailyAllowance!.toStringAsFixed(2)} บาท',
                        valueColor: Colors.orange.shade700,
                      ),
                    ),
                  // ✅ เพิ่ม: เวลาโดยประมาณ
                  if (history.estimatedTime != null && history.estimatedTime!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _buildDetailRow(
                        'เวลาโดยประมาณ',
                        history.estimatedTime!,
                        valueColor: Colors.teal.shade700,
                      ),
                    ),
                ]),
              
              const SizedBox(height: 16),
              
              // ✅ เพิ่ม Section เวลาออกเดินทางจริง
              if (history.plannedStartDateT != null)
                _buildDetailSection('เวลาออกเดินทาง', [
                  _buildDetailRow(
                    'เวลาจริง',
                    DateFormat('dd/MM/yyyy HH:mm').format(history.plannedStartDateT!),
                    valueColor: Colors.orange.shade700,
                  ),
                ]),
              
              // ✅ เพิ่ม Section เวลาส่งจริง
              if (history.plannedEndDateT != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: _buildDetailSection('เวลาส่งถึง', [
                    _buildDetailRow(
                      'เวลาจริง',
                      DateFormat('dd/MM/yyyy HH:mm').format(history.plannedEndDateT!),
                      valueColor: Colors.blue.shade700,
                    ),
                  ]),
                ),
              
              if (history.receiverName != null) ...[
                const SizedBox(height: 16),
                _buildDetailSection('ผู้รับ', [
                  _buildDetailRow('ชื่อผู้รับ', history.receiverName!),
                ]),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ปิด'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFFFF9800),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: valueColor ?? Colors.grey.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 100,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 24),
          Text(
            'ยังไม่มีประวัติการจัดส่ง',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _filterState == 'all'
                ? 'ประวัติจะแสดงหลังจากเสร็จสิ้นงาน'
                : _filterState == 'completed'
                    ? 'ยังไม่มีงานที่เสร็จสิ้น'
                    : 'ยังไม่มีงานที่ยกเลิก',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'เกิดข้อผิดพลาด',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.red.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadHistory,
            icon: const Icon(Icons.refresh),
            label: const Text('ลองอีกครั้ง'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF9800),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
