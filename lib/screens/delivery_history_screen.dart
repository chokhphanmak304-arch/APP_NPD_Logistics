import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
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
  String _filterState = 'all';
  bool _localeInitialized = false;

  static const Color _accent = Color(0xFFF57C00);
  static const Color _accentLight = Color(0xFFFF9800);

  @override
  void initState() {
    super.initState();
    _initializeLocale();
  }

  Future<void> _initializeLocale() async {
    try {
      await initializeDateFormatting('th_TH', null);
      setState(() => _localeInitialized = true);
      await _loadHistory();
    } catch (e) {
      print('❌ [History] Locale initialization error: $e');
      setState(() => _localeInitialized = true);
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
      final now = DateTime.now();
      final firstDayOfMonth = DateTime(now.year, now.month, 1);
      final lastDayOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

      final history = await _odooService.getDriverDeliveryHistory(
        widget.driver.id,
        state: _filterState == 'all' ? null : _filterState,
        startDate: firstDayOfMonth,
        endDate: lastDayOfMonth,
      );

      setState(() {
        _historyList = history;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ [History] Error: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  String get _monthLabel {
    final now = DateTime.now();
    if (_localeInitialized) {
      try {
        return DateFormat('MMMM yyyy', 'th_TH').format(now);
      } catch (_) {
        return DateFormat('MMMM yyyy').format(now);
      }
    }
    return DateFormat('MMMM yyyy').format(now);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: Column(
        children: [
          _buildHeader(),
          _buildFilterTabs(),
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
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: 2,
        driver: widget.driver,
      ),
    );
  }

  // ===================== Header =====================
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 0, 12, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_accentLight, _accent],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ประวัติการจัดส่ง',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.event, color: Colors.white70, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        _monthLabel,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Icon(Icons.refresh, color: Colors.white),
              onPressed: _isLoading ? null : _loadHistory,
            ),
          ],
        ),
      ),
    );
  }

  // ===================== Filter Tabs =====================
  Widget _buildFilterTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        children: [
          _buildFilterChip('all', 'ทั้งหมด', Icons.list_rounded),
          const SizedBox(width: 10),
          _buildFilterChip('completed', 'เสร็จสิ้น', Icons.check_circle_rounded),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label, IconData icon) {
    final isSelected = _filterState == value;
    return Expanded(
      child: Material(
        color: isSelected ? _accent : Colors.white,
        borderRadius: BorderRadius.circular(14),
        elevation: isSelected ? 0 : 1,
        shadowColor: Colors.black.withOpacity(0.06),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            setState(() => _filterState = value);
            _loadHistory();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 18,
                    color: isSelected ? Colors.white : Colors.grey.shade500),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey.shade700,
                    fontSize: 13,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===================== List =====================
  Widget _buildHistoryList() {
    return RefreshIndicator(
      color: _accent,
      onRefresh: _loadHistory,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        itemCount: _historyList.length,
        itemBuilder: (context, index) => _buildHistoryCard(_historyList[index]),
      ),
    );
  }

  Widget _buildHistoryCard(DeliveryHistory history) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final isCompleted = history.state == 'completed';
    final statusColor = isCompleted ? const Color(0xFF179E5B) : Colors.red;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showHistoryDetail(history),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // หัวการ์ด
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(history.getStateIcon(),
                          style: const TextStyle(fontSize: 20)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            history.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dateFormat.format(history.completionDate),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        history.getStateText(),
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ข้อมูลสำคัญ
                if (history.partnerName != null)
                  _infoLine(Icons.business_rounded, history.partnerName!),
                if (history.pickupLocation != null)
                  _infoLine(Icons.trip_origin_rounded, history.pickupLocation!,
                      color: const Color(0xFF3B82F6)),
                if (history.destination != null)
                  _infoLine(Icons.place_rounded, history.destination!,
                      color: Colors.red.shade400),

                const SizedBox(height: 12),
                // แถบค่าใช้จ่าย
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (history.travelExpenses != null)
                      _moneyChip('ค่าเที่ยว', history.travelExpenses!,
                          const Color(0xFF3B82F6)),
                    if (history.dailyAllowance != null)
                      _moneyChip('เบี้ยเลี้ยง', history.dailyAllowance!,
                          const Color(0xFFFF9800)),
                    if (history.shippingCost != null)
                      _moneyChip('ค่าขนส่ง', history.shippingCost!,
                          const Color(0xFF179E5B)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoLine(IconData icon, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color ?? Colors.grey.shade500),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _moneyChip(String label, double amount, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$label ${amount.toStringAsFixed(0)} ฿',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  // ===================== Detail Dialog =====================
  void _showHistoryDetail(DeliveryHistory history) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Text(history.getStateIcon(), style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(history.name, style: const TextStyle(fontSize: 18)),
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
                _buildDetailRow('เสร็จสิ้นเมื่อ',
                    dateFormat.format(history.completionDate)),
              ]),
              const SizedBox(height: 16),
              _buildDetailSection('เส้นทาง', [
                if (history.pickupLocation != null)
                  _buildDetailRow('ต้นทาง', history.pickupLocation!),
                if (history.destination != null)
                  _buildDetailRow('ปลายทาง', history.destination!),
                if (history.totalWeightOrder != null &&
                    history.totalWeightOrder! > 0)
                  _buildDetailRow(
                    'น้ำหนักรวม',
                    '${history.totalWeightOrder!.toStringAsFixed(2)} กก.',
                    valueColor: Colors.blue.shade700,
                  ),
                if (history.distanceKm != null)
                  _buildDetailRow('ระยะทาง',
                      '${history.distanceKm!.toStringAsFixed(2)} กม.'),
              ]),
              const SizedBox(height: 16),
              _buildDetailSection('เวลา', [
                if (history.plannedStartDate != null)
                  _buildDetailRow(
                      'วางแผน', dateFormat.format(history.plannedStartDate!)),
                if (history.actualPickupTime != null)
                  _buildDetailRow(
                      'รับสินค้า', dateFormat.format(history.actualPickupTime!)),
                if (history.actualDeliveryTime != null)
                  _buildDetailRow('ส่งถึง',
                      dateFormat.format(history.actualDeliveryTime!)),
                if (history.durationHours != null &&
                    history.durationHours! > 0)
                  _buildDetailRow('ระยะเวลารวม',
                      '${history.durationHours!.toStringAsFixed(1)} ชั่วโมง'),
              ]),
              const SizedBox(height: 16),
              if (history.shippingCost != null)
                _buildDetailSection('ค่าใช้จ่าย', [
                  _buildDetailRow(
                    'ค่าขนส่ง',
                    '${history.shippingCost!.toStringAsFixed(2)} บาท',
                    valueColor: Colors.green.shade700,
                  ),
                  if (history.travelExpenses != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _buildDetailRow(
                        'ค่าเที่ยว',
                        '${history.travelExpenses!.toStringAsFixed(2)} บาท',
                        valueColor: Colors.purple.shade700,
                      ),
                    ),
                  if (history.dailyAllowance != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _buildDetailRow(
                        'ค่าเบี้ยเลี้ยง',
                        '${history.dailyAllowance!.toStringAsFixed(2)} บาท',
                        valueColor: Colors.orange.shade700,
                      ),
                    ),
                  if (history.estimatedTime != null &&
                      history.estimatedTime!.isNotEmpty)
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
              if (history.plannedStartDateT != null)
                _buildDetailSection('เวลาออกเดินทาง', [
                  _buildDetailRow(
                    'เวลาจริง',
                    DateFormat('dd/MM/yyyy HH:mm')
                        .format(history.plannedStartDateT!),
                    valueColor: Colors.orange.shade700,
                  ),
                ]),
              if (history.plannedEndDateT != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: _buildDetailSection('เวลาส่งถึง', [
                    _buildDetailRow(
                      'เวลาจริง',
                      DateFormat('dd/MM/yyyy HH:mm')
                          .format(history.plannedEndDateT!),
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
            color: _accent,
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
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
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
    return ListView(
      children: [
        const SizedBox(height: 100),
        Icon(Icons.history_rounded, size: 90, color: Colors.grey.shade300),
        const SizedBox(height: 20),
        Center(
          child: Text(
            'ยังไม่มีประวัติการจัดส่ง',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: Text(
            _filterState == 'all'
                ? 'ประวัติจะแสดงหลังจากเสร็จสิ้นงาน'
                : 'ยังไม่มีงานที่เสร็จสิ้น',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
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
              _errorMessage ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadHistory,
            icon: const Icon(Icons.refresh),
            label: const Text('ลองอีกครั้ง'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
