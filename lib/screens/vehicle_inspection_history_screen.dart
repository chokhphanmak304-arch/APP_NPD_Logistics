import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/driver.dart';
import '../services/odoo_service.dart';
import '../widgets/bottom_nav_bar.dart';

class VehicleInspectionHistoryScreen extends StatefulWidget {
  final Driver driver;

  const VehicleInspectionHistoryScreen({super.key, required this.driver});

  @override
  State<VehicleInspectionHistoryScreen> createState() => _VehicleInspectionHistoryScreenState();
}

class _VehicleInspectionHistoryScreenState extends State<VehicleInspectionHistoryScreen> {
  final OdooService _odooService = OdooService();
  List<Map<String, dynamic>> _historyList = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final history = await _odooService.getVehicleInspectionHistory(widget.driver.id);
      setState(() {
        _historyList = history;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'ไม่สามารถโหลดข้อมูลได้: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('ประวัติการตรวจสอบสภาพรถ', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: _isLoading 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadHistory,
          ),
        ],
      ),
      body: _buildBody(),
      // ✅ Bottom Navigation Bar
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: 0,
        driver: widget.driver,
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.teal),
            SizedBox(height: 16),
            Text('กำลังโหลดข้อมูล...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: TextStyle(color: Colors.red.shade700)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadHistory,
              icon: const Icon(Icons.refresh),
              label: const Text('ลองใหม่'),
            ),
          ],
        ),
      );
    }

    if (_historyList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text('ยังไม่มีประวัติการตรวจสอบ', style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            Text('เมื่อคุณบันทึกการตรวจสอบ จะแสดงที่นี่', style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _historyList.length,
        itemBuilder: (context, index) => _buildHistoryCard(_historyList[index]),
      ),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> item) {
    final state = item['state'] ?? 'draft';
    final stateText = _getStateText(state);
    final stateColor = _getStateColor(state);
    final dateThai = item['inspection_date_thai'] ?? '-';
    final issueCount = item['issue_count'] ?? 0;
    final checkedItems = item['checked_items'] ?? 0;
    final totalItems = item['total_items'] ?? 0;
    // 🆕 แก้ไข: ตรวจสอบว่าเป็น String หรือไม่ (Odoo ส่ง false มาเมื่อไม่มีค่า)
    final licensePlate = (item['license_plate'] is String && item['license_plate'].toString().isNotEmpty) 
        ? item['license_plate'] : '-';
    final categoryName = (item['category_name'] is String && item['category_name'].toString().isNotEmpty) 
        ? item['category_name'] : '-';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showDetailDialog(item),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      item['name'] ?? '-',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal.shade700, fontSize: 13),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: stateColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: stateColor),
                    ),
                    child: Text(stateText, style: TextStyle(color: stateColor, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              // 🆕 ป้ายทะเบียนและประเภทรถ
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    // ป้ายทะเบียน
                    Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.directions_car, size: 16, color: Colors.blue.shade700),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              licensePlate,
                              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900, fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // ประเภทรถ
                    Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.category, size: 16, color: Colors.purple.shade700),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              categoryName,
                              style: TextStyle(color: Colors.purple.shade900, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              
              // Date row
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 8),
                  Text(dateThai, style: TextStyle(color: Colors.grey.shade700)),
                ],
              ),
              const SizedBox(height: 8),
              // Stats row
              Row(
                children: [
                  _buildStatBadge(Icons.check_circle, '$checkedItems/$totalItems', Colors.green),
                  const SizedBox(width: 12),
                  if (issueCount > 0)
                    _buildStatBadge(Icons.warning_amber, '$issueCount ปัญหา', Colors.orange),
                ],
              ),
              
              // General note preview
              if (item['general_note'] != null && item['general_note'].toString().isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.note, size: 16, color: Colors.amber.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item['general_note'].toString(),
                          style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              // View detail hint
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('แตะเพื่อดูรายละเอียด', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey.shade400),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatBadge(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  String _getStateText(String state) {
    switch (state) {
      case 'draft': return 'ร่าง';
      case 'confirmed': return 'ยืนยัน';
      case 'approved': return 'อนุมัติ';
      default: return state;
    }
  }

  Color _getStateColor(String state) {
    switch (state) {
      case 'draft': return Colors.blue;
      case 'confirmed': return Colors.orange;
      case 'approved': return Colors.green;
      default: return Colors.grey;
    }
  }

  Future<void> _showDetailDialog(Map<String, dynamic> item) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final detail = await _odooService.getVehicleInspectionDetail(item['id']);
      if (!mounted) return;
      Navigator.pop(context); // Close loading

      if (detail == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่สามารถโหลดรายละเอียดได้'), backgroundColor: Colors.red),
        );
        return;
      }

      _showDetailBottomSheet(detail);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาด: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showDetailBottomSheet(Map<String, dynamic> detail) {
    final inspectionLines = detail['inspection_lines'] as List? ?? [];
    final maintenanceLines = detail['maintenance_lines'] as List? ?? [];
    // 🆕 แก้ไข: ตรวจสอบว่าเป็น String หรือไม่ (Odoo ส่ง false มาเมื่อไม่มีค่า)
    final licensePlate = (detail['license_plate'] is String && detail['license_plate'].toString().isNotEmpty) 
        ? detail['license_plate'] : '-';
    final categoryName = (detail['category_name'] is String && detail['category_name'].toString().isNotEmpty) 
        ? detail['category_name'] : '-';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(Icons.assignment, color: Colors.teal.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        detail['name'] ?? '-',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(detail['inspection_date_thai'] ?? '-', style: TextStyle(color: Colors.grey.shade600)),
                  ],
                ),
              ),
              // 🆕 ข้อมูลรถ
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            Icon(Icons.directions_car, size: 18, color: Colors.blue.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('ป้ายทะเบียน', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                                  Text(licensePlate, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900, fontSize: 12), overflow: TextOverflow.ellipsis, maxLines: 2),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 30, color: Colors.blue.shade200, margin: const EdgeInsets.symmetric(horizontal: 8)),
                      Expanded(
                        flex: 2,
                        child: Row(
                          children: [
                            Icon(Icons.category, size: 18, color: Colors.purple.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('ประเภทรถ', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                                  Text(categoryName, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple.shade900, fontSize: 12), overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 16),
              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    // รายการตรวจเช็ค
                    if (inspectionLines.isNotEmpty) ...[
                      Text('รายการตรวจเช็ค (ข้อ 1-20)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
                      const SizedBox(height: 8),
                      ...inspectionLines.map((line) => _buildDetailLineItem(line)),
                      const SizedBox(height: 16),
                    ],
                    
                    // รายการบำรุงรักษา
                    if (maintenanceLines.isNotEmpty) ...[
                      Text('รายการบำรุงรักษา (ข้อ 21-24)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
                      const SizedBox(height: 8),
                      ...maintenanceLines.map((line) => _buildMaintenanceLineItem(line)),
                      const SizedBox(height: 16),
                    ],
                    
                    // หมายเหตุ
                    if (detail['general_note'] != null && detail['general_note'].toString().isNotEmpty) ...[
                      Text('หมายเหตุ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade700)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.shade200),
                        ),
                        child: Text(detail['general_note'].toString()),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailLineItem(Map<String, dynamic> line) {
    final isChecked = line['is_checked'] == true;
    final hasNote = line['note'] != null && line['note'].toString().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isChecked ? Colors.green.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isChecked ? Colors.green.shade200 : Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: isChecked ? Colors.green : Colors.grey,
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Text(line['item_no'] ?? '-', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(line['name'] ?? '-', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                    if (line['standard'] != null)
                      Text(line['standard'], style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              Icon(isChecked ? Icons.check_circle : Icons.radio_button_unchecked, 
                   color: isChecked ? Colors.green : Colors.grey, size: 22),
            ],
          ),
          if (hasNote) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(4)),
              child: Row(
                children: [
                  Icon(Icons.warning, size: 14, color: Colors.red.shade700),
                  const SizedBox(width: 4),
                  Expanded(child: Text(line['note'], style: TextStyle(fontSize: 11, color: Colors.red.shade700))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMaintenanceLineItem(Map<String, dynamic> line) {
    final isDue = line['is_due'];
    final isDueText = isDue == 'due' ? 'ครบกำหนด' : (isDue == 'not_due' ? 'ยังไม่ครบกำหนด' : '-');
    final isDueColor = isDue == 'due' ? Colors.red : Colors.green;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(6)),
                alignment: Alignment.center,
                child: Text(line['item_no'] ?? '-', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(line['name'] ?? '-', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isDueColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: isDueColor),
                ),
                child: Text(isDueText, style: TextStyle(fontSize: 11, color: isDueColor, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('เลขไมล์ปัจจุบัน', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                    Text(line['current_mileage']?.toString().isNotEmpty == true ? line['current_mileage'] : '-', 
                         style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('เลขไมล์ครั้งล่าสุด', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                    Text(line['last_change_mileage']?.toString().isNotEmpty == true ? line['last_change_mileage'] : '-',
                         style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
