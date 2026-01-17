import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../models/driver.dart';
import '../models/vehicle_inspection.dart';
import '../services/odoo_service.dart';
import '../widgets/bottom_nav_bar.dart';
import 'vehicle_inspection_history_screen.dart';

class VehicleInspectionScreen extends StatefulWidget {
  final Driver driver;

  const VehicleInspectionScreen({super.key, required this.driver});

  @override
  State<VehicleInspectionScreen> createState() => _VehicleInspectionScreenState();
}

class _VehicleInspectionScreenState extends State<VehicleInspectionScreen> {
  final ImagePicker _picker = ImagePicker();
  final OdooService _odooService = OdooService();
  final List<VehicleInspectionItem> _inspectionItems = [];
  final List<MaintenanceItem> _maintenanceItems = [];
  final Map<String, TextEditingController> _noteControllers = {};
  final Map<String, TextEditingController> _currentMileageControllers = {};
  final Map<String, TextEditingController> _lastChangeMileageControllers = {};
  final TextEditingController _generalNoteController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _initInspectionItems();
    _initMaintenanceItems();
  }

  void _initMaintenanceItems() {
    final items = [
      MaintenanceItem(id: '21', title: 'รอบเปลี่ยนถ่ายน้ำมันเครื่อง'),
      MaintenanceItem(id: '22', title: 'รอบเปลี่ยนกรองอากาศ'),
      MaintenanceItem(id: '23', title: 'รอบการเปลี่ยนน้ำมันเกียร์'),
      MaintenanceItem(id: '24', title: 'รอบการเปลี่ยนน้ำมันเฟืองท้าย'),
    ];

    for (var item in items) {
      _maintenanceItems.add(item);
      _currentMileageControllers[item.id] = TextEditingController();
      _lastChangeMileageControllers[item.id] = TextEditingController();
    }
  }

  void _initInspectionItems() {
    final items = [
      VehicleInspectionItem(id: '1', title: 'ระดับน้ำมันเครื่อง', standard: 'อยู่ระหว่างขีด Min - Max บนก้านวัด'),
      VehicleInspectionItem(id: '2', title: 'น้ำในหม้อน้ำ / หม้อพัก', standard: 'ระดับอยู่ในขีด Full หรือ Cold'),
      VehicleInspectionItem(id: '3', title: 'น้ำมันเบรก', standard: 'ระดับอยู่ใกล้ Full หรือไม่ต่ำกว่า Min'),
      VehicleInspectionItem(id: '4', title: 'น้ำมันพวงมาลัยพาวเวอร์', standard: 'ต้องไม่ต่ำกว่า Min และไม่เกิน Max'),
      VehicleInspectionItem(id: '5', title: 'น้ำมันไฮดรอลิกเครน', standard: 'อยู่ในช่วง Safe zone (ตามคู่มือเครนแต่ละรุ่น)'),
      VehicleInspectionItem(id: '6', title: 'สภาพสายพานหน้าเครื่อง', standard: 'ไม่หย่อน ไม่แตก ไม่แตกลายงา'),
      VehicleInspectionItem(id: '7', title: 'กรองอากาศ', standard: 'ถอดเป่าลมไม่ให้มีฝุ่น'),
      VehicleInspectionItem(id: '8', title: 'ยางทั้ง 6 ล้อ (รวมอะไหล่)', standard: 'ความดัน รถ 6 ล้อ 90-120 psi / กระบะ 38-42 PSI'),
      VehicleInspectionItem(id: '9', title: 'ไฟส่องสว่างและไฟสัญญาณ', standard: 'ต้องติดครบทุกดวง'),
      VehicleInspectionItem(id: '10', title: 'ระบบเบรก', standard: 'ไม่มีเสียงลมรั่ว/ระยะเหยียบไม่ลึกเกินไป'),
      VehicleInspectionItem(id: '11', title: 'คลัตซ์/เกียร์/เร่ง', standard: 'คลัตซ์ไม่แข็ง/เกียร์เข้าได้/คันเร่งตอบสนองเร็ว'),
      VehicleInspectionItem(id: '12', title: 'ปัดน้ำฝน-น้ำฉีดกระจก', standard: 'ทำงานได้ปกติ ฉีดน้ำได้ปกติ'),
      VehicleInspectionItem(id: '13', title: 'การทำงานของเครน', standard: 'ยกได้/หมุนได้/หุบ-กางได้ ไม่ฝืดหรือกระตุก'),
      VehicleInspectionItem(id: '14', title: 'ขาสมดุล Outrigger', standard: 'กางได้มั่นคง ไม่เอียง ไม่ยุบ'),
      VehicleInspectionItem(id: '15', title: 'ชุดสลิง/ตะขอ/อุปกรณ์', standard: 'ไม่มีรอยขาด สนิม สลักแน่นหนา'),
      VehicleInspectionItem(id: '16', title: 'การรั่วซึมของน้ำมันตามจุดต่างๆ', standard: 'จะต้องแห้งไม่มีน้ำมันหรือของเหลวไหลหยดออกมา'),
      VehicleInspectionItem(id: '16.1', title: 'ใต้ท้องเครื่อง', standard: 'จะต้องแห้งไม่มีน้ำมันหรือของเหลวไหลหยดออกมา'),
      VehicleInspectionItem(id: '16.2', title: 'ชุดเกียร์', standard: 'จะต้องแห้งไม่มีน้ำมันหรือของเหลวไหลหยดออกมา'),
      VehicleInspectionItem(id: '16.3', title: 'เพลาขับ / เฟืองท้าย', standard: 'จะต้องแห้งไม่มีน้ำมันหรือของเหลวไหลหยดออกมา'),
      VehicleInspectionItem(id: '16.4', title: 'กระบอกไฮดรอลิกชุดเครน', standard: 'จะต้องแห้งไม่มีน้ำมันหรือของเหลวไหลหยดออกมา'),
      VehicleInspectionItem(id: '17', title: 'แรงดันไฟแบตเตอรี่', standard: 'ก่อนสตาร์ทแรงดันไฟต้องไม่ต่ำกว่า 12V'),
      VehicleInspectionItem(id: '18', title: 'สัญญาณแตร', standard: 'เสียงดังชัดเจน'),
      VehicleInspectionItem(id: '19', title: 'ระบบแอร์ปรับอากาศ', standard: 'ทำงานปกติ มีความเย็น แอร์ไม่ตัน'),
      VehicleInspectionItem(id: '20', title: 'ควันท่อไอเสีย', standard: 'เร่งเครื่องที่ 1500 รอบควันไม่ดำหรือขาวเกินไปจนผิดสังเกต'),
    ];

    for (var item in items) {
      _inspectionItems.add(item);
      _noteControllers[item.id] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (var controller in _noteControllers.values) {
      controller.dispose();
    }
    for (var controller in _currentMileageControllers.values) {
      controller.dispose();
    }
    for (var controller in _lastChangeMileageControllers.values) {
      controller.dispose();
    }
    _generalNoteController.dispose();
    super.dispose();
  }

  Future<void> _takePhoto(VehicleInspectionItem item) async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (photo != null) {
        setState(() {
          item.imagePath = photo.path;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ไม่สามารถถ่ายรูปได้: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showImagePreview(String imagePath) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.file(File(imagePath)),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('ปิด')),
          ],
        ),
      ),
    );
  }

  Future<void> _submitInspection() async {
    // ตรวจสอบว่าติ๊กถูกครบทุกข้อหรือไม่
    final uncheckedItems = _inspectionItems.where((item) => !item.isChecked).toList();
    final unselectedMaintenance = _maintenanceItems.where((item) => item.isDue == null).toList();
    
    if (uncheckedItems.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('กรุณาตรวจสอบครบทุกข้อ (เหลืออีก ${uncheckedItems.length} ข้อ)'), backgroundColor: Colors.orange),
      );
      return;
    }
    
    if (unselectedMaintenance.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('กรุณาเลือกสถานะข้อ 21-24 ให้ครบ (เหลืออีก ${unselectedMaintenance.length} ข้อ)'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // เก็บข้อมูลหมายเหตุลงใน item
      for (var item in _inspectionItems) {
        item.note = _noteControllers[item.id]?.text;
      }
      
      // เก็บข้อมูลเลขไมล์
      for (var item in _maintenanceItems) {
        item.currentMileage = _currentMileageControllers[item.id]?.text ?? '';
        item.lastChangeMileage = _lastChangeMileageControllers[item.id]?.text ?? '';
      }

      // 🗓️ สร้างวันที่รูปแบบปกติ (เวลาประเทศไทย)
      final now = DateTime.now().toUtc().add(const Duration(hours: 7)); // UTC+7
      final inspectionDateThai = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);

      // 📝 เตรียมข้อมูลรายการตรวจเช็ค (พร้อมรูปภาพ base64)
      final List<Map<String, dynamic>> inspectionLines = [];
      for (var item in _inspectionItems) {
        String? imageBase64;
        if (item.imagePath != null && item.imagePath!.isNotEmpty) {
          try {
            final bytes = await File(item.imagePath!).readAsBytes();
            imageBase64 = base64Encode(bytes);
            print('📷 [Inspection] Item ${item.id}: Image converted to base64 (${bytes.length} bytes)');
          } catch (e) {
            print('⚠️ [Inspection] Item ${item.id}: Failed to read image: $e');
          }
        }
        inspectionLines.add({
          'id': item.id,
          'title': item.title,
          'standard': item.standard,
          'isChecked': item.isChecked,
          'note': item.note ?? '',
          'image': imageBase64,
        });
      }

      // 🔧 เตรียมข้อมูลรายการบำรุงรักษา
      final maintenanceLines = _maintenanceItems.map((item) => {
        'id': item.id,
        'title': item.title,
        'isDue': item.isDue,
        'currentMileage': item.currentMileage,
        'lastChangeMileage': item.lastChangeMileage,
      }).toList();

      // 🚀 ส่งข้อมูลไป Odoo
      final result = await _odooService.submitVehicleInspection(
        driverId: widget.driver.id,
        driverName: widget.driver.name,
        branchId: widget.driver.branchId,
        inspectionDateThai: inspectionDateThai,
        inspectionLines: inspectionLines,
        maintenanceLines: maintenanceLines,
        generalNote: _generalNoteController.text,
      );

      if (mounted) {
        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['message'] ?? 'บันทึกสำเร็จ'), backgroundColor: Colors.green),
          );
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['message'] ?? 'เกิดข้อผิดพลาด'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาด: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final checkedCount = _inspectionItems.where((item) => item.isChecked).length;
    final maintenanceFilledCount = _maintenanceItems.where((item) => item.isDue != null).length;
    final totalItems = _inspectionItems.length + _maintenanceItems.length;
    final completedItems = checkedCount + maintenanceFilledCount;
    final progress = completedItems / totalItems;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('รายการตรวจสอบสภาพรถ', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'ดูประวัติ',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => VehicleInspectionHistoryScreen(driver: widget.driver),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Progress indicator
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('ความคืบหน้า: $completedItems/$totalItems', style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('${(progress * 100).toInt()}%', style: TextStyle(fontWeight: FontWeight.bold, color: progress == 1.0 ? Colors.green : Colors.orange)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    backgroundColor: Colors.grey.shade300,
                    valueColor: AlwaysStoppedAnimation<Color>(progress == 1.0 ? Colors.green : Colors.teal),
                  ),
                ),
              ],
            ),
          ),
          // List of inspection items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                // ข้อ 1-20
                ...List.generate(_inspectionItems.length, (index) => _buildInspectionCard(_inspectionItems[index])),
                
                const SizedBox(height: 16),
                // หัวข้อ รายการบำรุงรักษา
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Text('รายการบำรุงรักษา (ข้อ 21-24)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
                ),
                
                // ข้อ 21-24
                ...List.generate(_maintenanceItems.length, (index) => _buildMaintenanceCard(_maintenanceItems[index])),
                
                const SizedBox(height: 16),
                // หมายเหตุทั่วไป
                _buildGeneralNoteSection(),
                
                const SizedBox(height: 80), // space for button
              ],
            ),
          ),
          // Submit button
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitInspection,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSubmitting
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('บันทึกการตรวจสอบ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
      // ✅ Bottom Navigation Bar
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: 0,
        driver: widget.driver,
      ),
    );
  }

  // 📝 หมายเหตุทั่วไป
  Widget _buildGeneralNoteSection() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 24),
                const SizedBox(width: 8),
                Text('**หมายเหตุ**', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
              ],
            ),
            const SizedBox(height: 4),
            Text('ระบุความผิดปกติอื่นๆที่ตรวจพบ', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
            const SizedBox(height: 12),
            TextField(
              controller: _generalNoteController,
              decoration: InputDecoration(
                hintText: 'กรอกรายละเอียดความผิดปกติอื่นๆ นอกเหนือจาก 24 ข้อ...',
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.orange.shade300)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.orange.shade300)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.orange.shade600, width: 2)),
              ),
              style: const TextStyle(fontSize: 14),
              maxLines: 4,
              textInputAction: TextInputAction.done,
            ),
          ],
        ),
      ),
    );
  }

  // 🔧 Card สำหรับข้อ 21-24 (รายการบำรุงรักษา)
  Widget _buildMaintenanceCard(MaintenanceItem item) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: item.isDue != null ? Colors.green.shade300 : Colors.grey.shade300, width: item.isDue != null ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: item.isDue != null ? Colors.green : Colors.grey.shade300, borderRadius: BorderRadius.circular(8)),
                  alignment: Alignment.center,
                  child: Text(item.id, style: TextStyle(color: item.isDue != null ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
              ],
            ),
            const SizedBox(height: 12),
            // Radio buttons สำหรับ ครบกำหนด / ยังไม่ครบกำหนด
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => item.isDue = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      decoration: BoxDecoration(
                        color: item.isDue == true ? Colors.red.shade100 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: item.isDue == true ? Colors.red : Colors.grey.shade300, width: item.isDue == true ? 2 : 1),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(item.isDue == true ? Icons.check_box : Icons.check_box_outline_blank, color: item.isDue == true ? Colors.red : Colors.grey, size: 20),
                          const SizedBox(width: 6),
                          Text('ครบกำหนด', style: TextStyle(fontSize: 13, fontWeight: item.isDue == true ? FontWeight.bold : FontWeight.normal, color: item.isDue == true ? Colors.red.shade700 : Colors.grey.shade700)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => item.isDue = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      decoration: BoxDecoration(
                        color: item.isDue == false ? Colors.green.shade100 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: item.isDue == false ? Colors.green : Colors.grey.shade300, width: item.isDue == false ? 2 : 1),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(item.isDue == false ? Icons.check_box : Icons.check_box_outline_blank, color: item.isDue == false ? Colors.green : Colors.grey, size: 20),
                          const SizedBox(width: 6),
                          Text('ยังไม่ครบกำหนด', style: TextStyle(fontSize: 13, fontWeight: item.isDue == false ? FontWeight.bold : FontWeight.normal, color: item.isDue == false ? Colors.green.shade700 : Colors.grey.shade700)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // ช่องกรอกเลขไมล์
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ระบุเลขไมล์ปัจจุบัน', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _currentMileageControllers[item.id],
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          hintText: 'เลขไมล์ปัจจุบัน',
                          hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                          filled: true, fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          isDense: true,
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('เลขไมล์ที่เปลี่ยนครั้งล่าสุด', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _lastChangeMileageControllers[item.id],
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          hintText: 'เลขไมล์ครั้งล่าสุด',
                          hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                          filled: true, fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          isDense: true,
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 📋 Card สำหรับข้อ 1-20 (รายการตรวจเช็ค)
  Widget _buildInspectionCard(VehicleInspectionItem item) {
    final isSubItem = item.id.contains('.');
    
    return Card(
      margin: EdgeInsets.only(left: isSubItem ? 24 : 8, right: 8, top: 4, bottom: 4),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: item.isChecked ? Colors.green.shade300 : Colors.grey.shade300, width: item.isChecked ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row with checkbox
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Item number
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: item.isChecked ? Colors.green : Colors.grey.shade300, borderRadius: BorderRadius.circular(8)),
                  alignment: Alignment.center,
                  child: Text(item.id, style: TextStyle(color: item.isChecked ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: isSubItem ? 10 : 12)),
                ),
                const SizedBox(width: 12),
                // Title and standard
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 4),
                      Text(item.standard, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                // Checkbox
                Transform.scale(
                  scale: 1.3,
                  child: Checkbox(
                    value: item.isChecked,
                    activeColor: Colors.green,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    onChanged: (value) => setState(() => item.isChecked = value ?? false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Note field
            TextField(
              controller: _noteControllers[item.id],
              decoration: InputDecoration(
                hintText: 'ระบุอาการชำรุดเสียหายที่ตรวจพบ (ถ้ามี)',
                hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                filled: true, fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.teal)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 13),
              maxLines: 2,
              textInputAction: TextInputAction.done,
            ),
            // Photo section
            if (item.requirePhoto) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _takePhoto(item),
                      icon: Icon(item.imagePath != null ? Icons.check_circle : Icons.camera_alt, size: 18),
                      label: Text(item.imagePath != null ? 'ถ่ายรูปใหม่' : 'ถ่ายภาพรายงาน', style: const TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: item.imagePath != null ? Colors.green : Colors.teal,
                        side: BorderSide(color: item.imagePath != null ? Colors.green : Colors.teal),
                      ),
                    ),
                  ),
                  if (item.imagePath != null) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _showImagePreview(item.imagePath!),
                      child: Container(
                        width: 50, height: 50,
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green, width: 2)),
                        child: ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.file(File(item.imagePath!), fit: BoxFit.cover)),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
