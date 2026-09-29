import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/booking.dart';
import '../models/driver.dart';
import '../services/odoo_service.dart';
import '../services/tracking_service.dart';
import '../services/camera_protection_service.dart';  // 🛡️ เพิ่มการป้องกัน!
import '../widgets/bottom_nav_bar.dart';
import '../models/product_check.dart';
import '../widgets/product_check_card.dart';

class StartJobScreen extends StatefulWidget {
  final Booking booking;
  final Driver driver;

  const StartJobScreen({
    super.key, 
    required this.booking,
    required this.driver,
  });

  @override
  State<StartJobScreen> createState() => _StartJobScreenState();
}

class _StartJobScreenState extends State<StartJobScreen> with WidgetsBindingObserver {
  final OdooService _odooService = OdooService();
  final TrackingService _trackingService = TrackingService();
  final ImagePicker _picker = ImagePicker();
  
  // รูปสินค้าก่อนออกรถ เก็บได้หลายใบ คนขับต้องถ่ายหลายมุมเวลาของขาด
  // หรือมีรอยเสียหาย รูปเดียวเถียงกันไม่จบว่าของครบตอนออกจากคลังไหม
  final List<File> _photos = [];
  static const int _maxPhotos = 10;

  /// รูปแรก — โค้ดส่วนที่เหลือใช้ตัวนี้เช็คแค่ว่า "มีรูปแล้วหรือยัง"
  File? get _pickedImage => _photos.isEmpty ? null : _photos.first;
  bool _isUploading = false;
  
  // ✅ เพิ่มตรงนี้
  bool _isDisposed = false;
  bool _isPickingImage = false;  // ✅ ป้องกันการถ่ายภาพซ้ำ

  // ตรวจนับสินค้าก่อนถ่ายรูป
  List<ProductCheckLine> _checkLines = [];
  ProductCheckSummary? _checkSummary;

  // เที่ยว "ส่งรถไปช่วยขนส่งอีกสาขา" ไม่มีของให้ตรวจ ใช้หมายเหตุแทน
  // ฝั่ง Odoo เป็นคนบอกว่าเที่ยวไหนใช้แบบไหน แอปไม่เดาเองจากชื่อประเภท
  final TextEditingController _noteController = TextEditingController();
  bool _savingNote = false;

  bool get _needsProductCheck => _checkSummary?.needsProductCheck ?? true;

  /// สิ่งที่ต้องถ่ายในเที่ยวนี้ — เที่ยวช่วยสาขาไม่มีของ ถ่ายรถแทน
  String get _photoSubject => _needsProductCheck ? 'รูปสินค้า' : 'รูปรถ';

  String get _photoHint => _needsProductCheck
      ? 'ให้เห็นสภาพสินค้าชัดเจน ถ้ามีของขาดให้ถ่ายให้เห็นด้วย'
      : 'ถ่ายรถที่จะไปช่วยขนส่ง ให้เห็นป้ายทะเบียนชัดเจน';
  bool _loadingCheck = true;
  bool _savingCheck = false;
  // โหลดรายการไม่ได้ (เน็ตล่ม/เซิร์ฟเวอร์ตอบไม่ได้) ต่างจาก "ใบนี้ไม่มีสินค้า"
  bool _checkLoadFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);  // ✅ เพิ่ม
    _loadProductCheck();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);  // ✅ เพิ่ม
    _isDisposed = true;  // ✅ เพิ่ม
    imageCache.clear();  // ✅ เพิ่ม
    imageCache.clearLiveImages();  // ✅ เพิ่ม
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      print('⏸️ [StartJob] App paused - camera opened');
      // ✅ FIX: ไม่ต้อง cleanup ตอน pause เพราะจะทำตอน resume
    } else if (state == AppLifecycleState.resumed) {
      print('▶️ [StartJob] App resumed - camera closed');
      // ✅ FIX: Cleanup หลังกลับจากกล้อง
      if (!_isDisposed && mounted) {
        try {
          imageCache.clear();
          imageCache.clearLiveImages();
          print('✅ [StartJob] Memory cleaned');
        } catch (e) {
          print('⚠️ [StartJob] Cleanup error: $e');
        }
        // ✅ Refresh session อีกครั้ง
        _odooService.refreshSessionIfNeeded().catchError((e) {
          print('⚠️ [StartJob] Session refresh on resume failed: $e');
        });
      }
    }
  }

  // ================= ตรวจนับสินค้า =================

  Future<void> _loadProductCheck() async {
    final data = await _odooService.getProductCheckLines(widget.booking.id);
    if (_isDisposed || !mounted) return;
    setState(() {
      _loadingCheck = false;
      if (data == null) {
        // ยังไม่รู้ว่ามีสินค้าไหม จึงยังไม่ปลดล็อกกล้อง ให้ผู้ใช้กดลองใหม่
        _checkLoadFailed = true;
        return;
      }
      _checkLoadFailed = false;
      _checkSummary = ProductCheckSummary.fromJson(data['summary'] ?? {});
      // เติมหมายเหตุเดิมให้ คนขับจะได้แก้ต่อไม่ต้องพิมพ์ใหม่
      if (_noteController.text.trim().isEmpty) {
        _noteController.text = _checkSummary?.note ?? '';
      }
      _checkLines = (data['lines'] as List? ?? [])
          .map((e) => ProductCheckLine.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    });
  }

  void _markLine(ProductCheckLine line, bool isCorrect) {
    setState(() {
      line.checkState = isCorrect ? 'correct' : 'incorrect';
      if (isCorrect) {
        line.checkedQuantity = line.quantity;
        line.note = '';
      }
    });
    if (!isCorrect) {
      // กดว่าไม่ถูกต้องแล้วต้องบอกทันทีว่านับได้เท่าไหร่ ไม่งั้นข้อมูลไม่มีประโยชน์
      _askQuantity(line);
    }
  }

  Future<void> _askQuantity(ProductCheckLine line) async {
    final qtyController = TextEditingController(
      text: line.checkedQuantity > 0 ? ProductCheckCard.fmt(line.checkedQuantity) : '',
    );
    final noteController = TextEditingController(text: line.note);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('นับได้เท่าไหร่'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(line.productName,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('สั่งไว้ ${ProductCheckCard.fmt(line.quantity)} ${line.uom}',
                style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            const SizedBox(height: 16),
            TextField(
              controller: qtyController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'จำนวนที่นับได้',
                suffixText: line.uom,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              decoration: InputDecoration(
                labelText: 'หมายเหตุ (ถ้ามี)',
                hintText: 'เช่น ของชำรุด 2 ชิ้น',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ยกเลิก')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('บันทึก')),
        ],
      ),
    );
    if (saved == true && mounted) {
      setState(() {
        line.checkedQuantity =
            double.tryParse(qtyController.text.trim()) ?? 0;
        line.note = noteController.text.trim();
      });
    }
  }

  Future<void> _saveProductCheck() async {
    setState(() => _savingCheck = true);
    final result = await _odooService.saveProductCheck(
      bookingId: widget.booking.id,
      driverId: widget.driver.id,
      lines: _checkLines.map((l) => l.toPayload()).toList(),
    );
    if (_isDisposed || !mounted) return;
    setState(() {
      _savingCheck = false;
      if (result != null) {
        _checkSummary = ProductCheckSummary.fromJson(result['summary'] ?? {});
      }
    });
    if (!mounted) return;
    if (result == null) {
      _showError('บันทึกผลตรวจไม่สำเร็จ ลองใหม่อีกครั้ง');
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_checkSummary?.canTakePhoto == true
            ? 'บันทึกแล้ว ถ่าย$_photoSubjectได้เลย'
            : 'บันทึกแล้ว'),
        backgroundColor: const Color(0xFF16A34A),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// ถ่ายรูปได้เมื่อ Odoo บอกว่าตรวจครบแล้วเท่านั้น
  /// แอปไม่ตัดสินเอง เพื่อไม่ให้ตรรกะอยู่สองที่แล้วเพี้ยนกัน
  bool get _canTakePhoto => _checkSummary?.canTakePhoto ?? false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(_needsProductCheck
              ? 'ตรวจสอบสินค้า/ถ่ายรูปสินค้า'
              : 'หมายเหตุ/ถ่ายรูปรถ'),
        ),
        backgroundColor: const Color(0xFF1E40AF),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF5F6F8),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ข้อมูลงาน
            _buildJobInfoCard(),
            
            const SizedBox(height: 24),
            
            // คำแนะนำ
            _buildInstructionCard(),
            
            const SizedBox(height: 24),
            
            // รูปภาพที่ถ่าย
            if (_pickedImage != null) _buildImagePreview(),
            
            const SizedBox(height: 24),
            
            // ตรวจนับสินค้า / หมายเหตุ — ต้องทำก่อนจึงจะถ่ายรูปได้
            if (_pickedImage == null && _needsProductCheck)
              _buildProductCheckSection(),
            if (_pickedImage == null && !_needsProductCheck)
              _buildHelpBranchNoteSection(),

            if (_pickedImage == null) const SizedBox(height: 24),

            // ปุ่มถ่ายรูป
            if (_pickedImage == null) _buildCameraButtons(),
            
            // ปุ่มแชร์และเริ่มงาน
            if (_pickedImage != null) _buildActionButtons(),
          ],
        ),
      ),
      // ✅ เพิ่ม Bottom Navigation Bar
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: 1, // ชี้ไปที่ "งานของฉัน"
        driver: widget.driver,
      ),
    );
  }

  Widget _buildJobInfoCard() {
    final b = widget.booking;
    final hasCost = (b.shippingCost ?? 0) > 0 ||
        (b.travelExpenses ?? 0) > 0 ||
        (b.dailyAllowance ?? 0) > 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // หัวการ์ด - เลขที่จองเด่นที่สุด เพราะคนขับใช้อ้างอิงตลอดงาน
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: const BoxDecoration(
              color: Color(0xFF1E40AF),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'เลขที่จอง',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.white.withValues(alpha: 0.75),
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  b.name,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ต้นทางกับปลายทางอ่านเป็นคู่ จึงวางติดกันแล้วมีเส้นเชื่อม
                _buildRoute(b.pickupLocation, b.destination),
                const SizedBox(height: 14),
                _buildInfoRow(
                    Icons.person_outline, 'ลูกค้า', b.partnerName ?? '-'),
                if (b.plannedStartDate != null)
                  _buildInfoRow(Icons.schedule_outlined, 'วางแผนออกเดินทาง',
                      _formatDateTime(b.plannedStartDate!)),
                if (b.plannedStartDateT != null)
                  _buildInfoRow(Icons.play_circle_outline, 'ออกเดินทางจริง',
                      _formatDateTime(b.plannedStartDateT!),
                      valueColor: const Color(0xFF16A34A)),
                if (b.estimatedTime != null && b.estimatedTime!.isNotEmpty)
                  _buildInfoRow(Icons.timelapse_outlined, 'เวลาโดยประมาณ',
                      b.estimatedTime!, valueColor: const Color(0xFFB45309)),
              ],
            ),
          ),
          if (hasCost) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ค่าใช้จ่าย',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade600,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if ((b.shippingCost ?? 0) > 0)
                    _buildCostRow('ค่าขนส่ง', b.shippingCost!),
                  if ((b.travelExpenses ?? 0) > 0)
                    _buildCostRow('ค่าเที่ยว', b.travelExpenses!),
                  if ((b.dailyAllowance ?? 0) > 0)
                    _buildCostRow('ค่าเบี้ยเลี้ยง', b.dailyAllowance!),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRoute(String? from, String? to) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                  color: Color(0xFF2563EB), shape: BoxShape.circle),
            ),
            Container(width: 2, height: 30, color: Colors.grey.shade300),
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                  color: Color(0xFF16A34A), shape: BoxShape.circle),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _routeText('รับที่', from),
              const SizedBox(height: 14),
              _routeText('ส่งที่', to),
            ],
          ),
        ),
      ],
    );
  }

  Widget _routeText(String label, String? value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
        const SizedBox(height: 1),
        Text(
          value ?? '-',
          style: const TextStyle(
              fontSize: 14.5, fontWeight: FontWeight.w600, height: 1.25),
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value,
      {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: Colors.grey.shade500),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style:
                        TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCostRow(String label, double amount) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(fontSize: 13.5, color: Colors.grey.shade700)),
          Text(
            amount.toStringAsFixed(2) + ' บาท',
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionCard() {
    return Card(
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.checklist_rounded, color: Colors.blue[700]),
                const SizedBox(width: 8),
                Text(
                  'ขั้นตอนก่อนเริ่มงาน',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // ไล่เป็นขั้นตอน ไม่ใช่หัวข้อย่อยลอย ๆ เพราะลำดับสำคัญ
            // ต้องตรวจนับให้ครบก่อนถึงจะถ่ายรูปได้ และไฮไลต์ขั้นที่ทำอยู่
            // เพื่อไม่ให้คนขับงงว่าทำไมปุ่มกล้องยังกดไม่ได้
            _buildStep(
              number: 1,
              title: _needsProductCheck ? 'ตรวจนับจำนวนสินค้า' : 'ระบุหมายเหตุ',
              detail: _needsProductCheck
                  ? 'กดถูกต้อง/ไม่ถูกต้องให้ครบทุกรายการ แล้วกดบันทึก'
                  : 'เที่ยวนี้ไม่มีสินค้าให้ตรวจ เขียนว่าไปช่วยสาขาไหน ทำอะไรมา',
              done: _canTakePhoto,
              active: !_canTakePhoto,
            ),
            _buildStep(
              number: 2,
              title: 'ถ่าย$_photoSubject',
              detail: _photoHint,
              done: _pickedImage != null,
              active: _canTakePhoto && _pickedImage == null,
              locked: !_canTakePhoto,
            ),
            _buildStep(
              number: 3,
              title: 'เริ่มงาน',
              detail: 'ระบบบันทึกเวลาเริ่มงานให้อัตโนมัติ',
              done: false,
              active: _pickedImage != null,
              locked: _pickedImage == null,
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.photo_library_outlined,
                  size: 18, color: Color(0xFF16A34A)),
              const SizedBox(width: 8),
              Text(
                '$_photoSubject ${_photos.length}/$_maxPhotos รูป',
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (_photos.length > 1)
                TextButton.icon(
                  onPressed: () => setState(_photos.clear),
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text('ลบทั้งหมด'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // รูปแรกใหญ่ที่สุด เพราะเป็นรูปที่ไปโผล่บนหน้าจอ Odoo เป็นหลัก
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              _photos.first,
              width: double.infinity,
              height: 240,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 82,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _photos.length + (_photos.length < _maxPhotos ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                if (index == _photos.length) return _buildAddPhotoTile();
                return _buildPhotoThumb(index);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoThumb(int index) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(_photos[index],
              width: 82, height: 82, fit: BoxFit.cover),
        ),
        Positioned(
          right: -6,
          top: -6,
          child: GestureDetector(
            onTap: () => setState(() => _photos.removeAt(index)),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: Color(0xFFDC2626),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
        Positioned(
          left: 4,
          bottom: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('${index + 1}',
                style: const TextStyle(fontSize: 10, color: Colors.white)),
          ),
        ),
      ],
    );
  }

  Widget _buildAddPhotoTile() {
    return GestureDetector(
      onTap: _isPickingImage ? null : () => _pickImage(ImageSource.camera),
      child: Container(
        width: 82,
        height: 82,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo_outlined,
                size: 22, color: Colors.grey.shade600),
            const SizedBox(height: 4),
            Text('เพิ่มรูป',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
          ],
        ),
      ),
    );
  }

  /// หนึ่งขั้นตอนในคำแนะนำ — เสร็จแล้ว / กำลังทำ / ยังล็อกอยู่
  Widget _buildStep({
    required int number,
    required String title,
    required String detail,
    required bool done,
    required bool active,
    bool locked = false,
    bool isLast = false,
  }) {
    final Color color = done
        ? const Color(0xFF16A34A)
        : active
            ? const Color(0xFF2563EB)
            : Colors.grey.shade400;
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: done || active ? color : Colors.transparent,
              border: Border.all(color: color, width: 1.5),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: done
                  ? const Icon(Icons.check, size: 15, color: Colors.white)
                  : locked
                      ? Icon(Icons.lock_outline, size: 13, color: color)
                      : Text(
                          '$number',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: active ? Colors.white : color,
                          ),
                        ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                    color: locked ? Colors.grey.shade500 : Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: locked ? Colors.grey.shade400 : Colors.grey.shade700,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCheckSection() {
    if (_loadingCheck) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_checkLoadFailed) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: Column(
          children: [
            const Icon(Icons.wifi_off_rounded,
                color: Color(0xFFDC2626), size: 32),
            const SizedBox(height: 8),
            const Text('โหลดรายการสินค้าไม่ได้',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('ตรวจสัญญาณอินเทอร์เน็ตแล้วลองใหม่',
                style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                setState(() => _loadingCheck = true);
                _loadProductCheck();
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('ลองใหม่'),
            ),
          ],
        ),
      );
    }
    // ใบที่ไม่มีรายการสินค้า ไม่ต้องแสดงการ์ดให้รก
    if (_checkLines.isEmpty) return const SizedBox.shrink();
    return ProductCheckCard(
      lines: _checkLines,
      summary: _checkSummary,
      isSaving: _savingCheck,
      onMark: _markLine,
      onEditQuantity: _askQuantity,
      onSave: _saveProductCheck,
    );
  }

  /// ช่องหมายเหตุสำหรับเที่ยวช่วยสาขา — ใช้แทนการตรวจนับสินค้า
  Widget _buildHelpBranchNoteSection() {
    final saved = (_checkSummary?.note ?? '').trim().isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: saved ? const Color(0xFFBBF7D0) : Colors.grey.shade200),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(saved ? Icons.check_circle : Icons.edit_note_outlined,
                  size: 20,
                  color: saved
                      ? const Color(0xFF16A34A)
                      : Colors.grey.shade600),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('หมายเหตุการไปช่วยสาขา',
                    style: TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'เที่ยวนี้เป็นการไปช่วยขนส่งให้สาขาอื่น จึงไม่มีรายการสินค้าให้ตรวจนับ\n'
            'เขียนให้ครบ 3 อย่าง: ไปช่วยสาขาไหน / ขนอะไร / กี่เที่ยว หรือช่วงเวลาไหน\n'
            'ระบบจะตรวจข้อความให้อัตโนมัติหลังกดบันทึก',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            maxLines: 4,
            // ใช้ done ไม่ใช่ newline เพราะแป้นพิมพ์จะได้มีปุ่ม "เสร็จสิ้น"
            // ให้ปิดแป้นได้ ของเดิมเป็นปุ่มขึ้นบรรทัดใหม่ คนขับจึงปิดแป้นไม่ได้
            // แล้วมองไม่เห็นปุ่มบันทึกที่อยู่ใต้แป้นพอดี
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
            decoration: InputDecoration(
              hintText: 'เช่น ไปช่วยสาขาราชบุรีขนนั่งร้านให้หน้างานของสาขาเขา '
                  '2 เที่ยว ตั้งแต่ 9 โมงถึงบ่าย 2',
              hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
              contentPadding: const EdgeInsets.all(12),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: Color(0xFF2563EB), width: 1.6),
              ),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          if ((_checkSummary?.noteAiMessage ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildNoteAiResult(),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _savingNote ? null : _saveHelpBranchNote,
              icon: _savingNote
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_outlined, size: 19),
              label: Text(_savingNote ? 'กำลังบันทึก...' : 'บันทึกหมายเหตุ',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// การ์ดแสดงผล AI ตรวจหมายเหตุ
  Widget _buildNoteAiResult() {
    final s = _checkSummary!;
    final needsRewrite = s.noteNeedsRewrite;
    final accepted = s.noteAccepted;
    final Color bg = needsRewrite
        ? const Color(0xFFFFFBEB)
        : accepted
            ? const Color(0xFFF0FDF4)
            : const Color(0xFFF8FAFC);
    final Color line = needsRewrite
        ? const Color(0xFFFDE68A)
        : accepted
            ? const Color(0xFFBBF7D0)
            : Colors.grey.shade300;
    final IconData icon = needsRewrite
        ? Icons.warning_amber_rounded
        : accepted
            ? Icons.verified_rounded
            : Icons.info_outline;
    final Color iconColor = needsRewrite
        ? const Color(0xFFB45309)
        : accepted
            ? const Color(0xFF16A34A)
            : Colors.grey.shade600;
    final String title = needsRewrite
        ? 'ระบบตรวจแล้ว — ควรเขียนให้ชัดกว่านี้'
        : accepted
            ? 'ระบบตรวจแล้ว — หมายเหตุใช้ได้'
            : 'ผลการตรวจหมายเหตุ';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: iconColor)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(s.noteAiMessage,
              style: TextStyle(
                  fontSize: 12.5, height: 1.35, color: Colors.grey.shade800)),
          if (needsRewrite && s.noteAiExample.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ตัวอย่างที่ควรเขียน',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade600)),
                  const SizedBox(height: 4),
                  Text(s.noteAiExample,
                      style: const TextStyle(fontSize: 13, height: 1.35)),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        // เติมให้แล้วให้คนขับแก้รายละเอียดเอง เร็วกว่าพิมพ์ใหม่
                        setState(() {
                          _noteController.text = s.noteAiExample;
                          _noteController.selection =
                              TextSelection.collapsed(
                                  offset: s.noteAiExample.length);
                        });
                      },
                      icon: const Icon(Icons.edit_note, size: 18),
                      label: const Text('ใช้ข้อความนี้แล้วแก้ต่อ'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF2563EB),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (needsRewrite) ...[
            const SizedBox(height: 8),
            Text(
              'แก้ข้อความด้านบนแล้วกดบันทึกอีกครั้งได้ '
              'ถ้ายืนยันว่าเขียนถูกแล้วก็ถ่ายรูปต่อได้เลย',
              style: TextStyle(
                  fontSize: 12, color: Colors.grey.shade600, height: 1.3),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _saveHelpBranchNote() async {
    final note = _noteController.text.trim();
    if (note.isEmpty) {
      _showError('กรุณาระบุหมายเหตุว่าไปช่วยสาขาทำอะไรมา');
      return;
    }
    setState(() => _savingNote = true);
    try {
      final result = await _odooService.saveHelpBranchNote(
        bookingId: widget.booking.id,
        note: note,
      );
      if (!mounted) return;
      setState(() {
        if (result?['summary'] != null) {
          _checkSummary = ProductCheckSummary.fromJson(
              Map<String, dynamic>.from(result!['summary'] as Map));
        }
        _savingNote = false;
      });
      // ข้อความเต็มของ AI อยู่ในการ์ดใต้ช่องกรอกแล้ว แจ้งซ้ำใน SnackBar
      // จะบังจอและอ่านสองที่เหมือนกัน เหลือแค่บอกสั้น ๆ ว่าบันทึกสำเร็จ
      // แล้วชี้ให้ไปดูการ์ดแทน
      final s = _checkSummary;
      final needsRewrite = s != null && s.noteNeedsRewrite;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(needsRewrite
              ? 'บันทึกแล้ว — ดูคำแนะนำด้านล่าง'
              : 'บันทึกหมายเหตุแล้ว ถ่ายรูปได้เลย'),
          backgroundColor: needsRewrite
              ? const Color(0xFFB45309)
              : const Color(0xFF16A34A),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingNote = false);
      _showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Widget _buildCameraButtons() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        // ล็อกไว้จนกว่า Odoo จะยืนยันว่าตรวจนับครบแล้ว
        onPressed: _canTakePhoto ? () => _pickImage(ImageSource.camera) : null,
        icon: Icon(_canTakePhoto ? Icons.camera_alt : Icons.lock_outline,
            size: 28),
        label: Text(
          _canTakePhoto
              ? 'เปิดกล้องถ่าย$_photoSubject'
              : (_needsProductCheck
                  ? 'ตรวจนับสินค้าให้ครบก่อน'
                  : 'บันทึกหมายเหตุก่อน'),
          style: const TextStyle(fontSize: 18),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue[700],
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade300,
          disabledForegroundColor: Colors.grey.shade600,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        // ปุ่มแชร์รูป
        SizedBox(
          width: double.infinity,
          height: 56,
          child: OutlinedButton.icon(
            onPressed: _shareImage,
            icon: const Icon(Icons.share, size: 24),
            label: const Text(
              'แชร์รูป',
              style: TextStyle(fontSize: 18),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.blue[700],
              side: BorderSide(color: Colors.blue[700]!, width: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        // ปุ่มเริ่มงาน
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: _isUploading ? null : _startJob,
            icon: _isUploading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.play_arrow, size: 28),
            label: Text(
              _isUploading ? 'กำลังเริ่มงาน...' : 'เริ่มงานขนส่ง',
              style: const TextStyle(fontSize: 18),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[600],
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ✅ แก้ไข timeout เป็น 180 วินาที + เพิ่ม session refresh
  Future<void> _pickImage(ImageSource source) async {
    // ✅ FIX: ป้องกันการถ่ายภาพซ้ำๆ
    if (_isPickingImage) {
      print('⚠️ [StartJob] Already picking image, ignoring...');
      return;
    }
    
    if (_isDisposed) {
      print('❌ [StartJob] Widget already disposed');
      return;
    }

    // ✅ FIX: ตั้งค่า flag ป้องกันการกดซ้ำ
    if (mounted) {
      setState(() => _isPickingImage = true);
    }

    try {
      print('📷 [StartJob] Starting photo pick...');
      
      // เดิมลบรูปเก่าทิ้งก่อนถ่ายใหม่เพื่อกัน memory leak ตอนนี้เก็บหลายรูป
      // จึงลบไม่ได้ กันหน่วยความจำด้วยการจำกัดจำนวนรูปแทน
      if (_photos.length >= _maxPhotos) {
        if (mounted) {
          _showError('ถ่ายได้สูงสุด $_maxPhotos รูป ลบรูปเก่าออกก่อน');
        }
        return;
      }
      
      // ✅ Clear cache before opening camera
      imageCache.clear();
      imageCache.clearLiveImages();
      print('✅ [StartJob] Cache cleared before camera');
      
      // ✅ FIX: Refresh session ก่อนเปิดกล้อง
      try {
        await _odooService.refreshSessionIfNeeded();
        print('✅ [StartJob] Session refreshed');
      } catch (e) {
        print('⚠️ [StartJob] Session refresh failed: $e');
      }
      
      PermissionStatus status;
      if (source == ImageSource.camera) {
        print('📷 [StartJob] Requesting camera permission...');
        status = await Permission.camera.request();
      } else {
        print('🖼️ [StartJob] Requesting photo permission...');
        status = await Permission.photos.request();
      }

      print('📷 [StartJob] Permission status: $status');
      
      if (!status.isGranted) {
        if (!_isDisposed && mounted) {
          _showError('กรุณาอนุญาตการเข้าถึง${source == ImageSource.camera ? 'กล้อง' : 'รูปภาพ'}');
        }
        return;
      }

      print('📷 [StartJob] Picking image with quality optimization...');
      
      late XFile? image;
      try {
        // 🛡️ CRITICAL: Wrap ด้วย CameraProtectionService เพื่อป้องกันแอปถูกฆ่า!
        image = await CameraProtectionService.withProtection(() async {
          return await _picker.pickImage(
            source: source,
            maxWidth: 1280,
            maxHeight: 720,
            imageQuality: 75,
            preferredCameraDevice: CameraDevice.rear,
            requestFullMetadata: false,
          );
        }).timeout(
          const Duration(seconds: 180),
          onTimeout: () {
            print('⏱️ [StartJob] Camera timeout after 180s!');
            return null;
          },
        );
      } on PlatformException catch (e) {
        print('❌ [StartJob] PlatformException: $e');
        if (!_isDisposed && mounted) {
          _showError('ไม่สามารถเข้าถึงกล้องได้: ${e.message}');
        }
        return;
      }

      print('📷 [StartJob] Image picked: ${image?.path}');
      
      // ✅ FIX: Refresh session หลังกลับจากกล้อง
      if (!_isDisposed) {
        try {
          await _odooService.refreshSessionIfNeeded();
          print('✅ [StartJob] Session refreshed after camera');
        } catch (e) {
          print('⚠️ [StartJob] Session refresh after camera failed: $e');
        }
      }
      
      if (image != null && !_isDisposed && mounted) {
        final imageFile = File(image.path);
        
        // ✅ Check if file exists
        if (!await imageFile.exists()) {
          print('❌ [StartJob] Image file does not exist');
          if (!_isDisposed && mounted) {
            _showError('ไม่พบไฟล์รูปภาพ กรุณาลองใหม่');
          }
          return;
        }
        
        final fileSize = await imageFile.length();
        
        print('📏 [StartJob] File size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');
        
        // ✅ Check minimum file size (corrupted check)
        if (fileSize < 1000) {
          if (!_isDisposed && mounted) {
            _showError('รูปภาพเสียหายหรือไม่สมบูรณ์ กรุณาลองใหม่');
          }
          return;
        }
        
        if (fileSize > 10 * 1024 * 1024) {
          if (!_isDisposed && mounted) {
            _showError('รูปภาพใหญ่เกินไป (> 10MB)');
          }
          return;
        }
        
        // ✅ Clear cache before setting new image
        imageCache.clear();
        imageCache.clearLiveImages();
        
        if (mounted && !_isDisposed) {
          setState(() {
            _photos.add(imageFile);
            print('OK [StartJob] Photo ${_photos.length}/$_maxPhotos - '
                '${(fileSize / 1024).toStringAsFixed(1)} KB');
          });
        }
      } else if (!_isDisposed) {
        print('⚠️ [StartJob] Image pick cancelled or timed out');
      }
    } catch (e) {
      print('❌ [StartJob] Unexpected error: $e');
      if (!_isDisposed && mounted) {
        _showError('ไม่สามารถถ่ายรูปได้: ${e.toString().substring(0, 100)}');
      }
    } finally {
      // ✅ FIX: ปลดล็อค flag ไม่ว่าจะสำเร็จหรือไม่
      if (!_isDisposed && mounted) {
        setState(() => _isPickingImage = false);
        print('✅ [StartJob] Image picking completed, flag reset');
      }
    }
  }

  Future<void> _shareImage() async {
    if (_pickedImage == null || _isDisposed) return;

    try {
      await Share.shareXFiles(
        [XFile(_pickedImage!.path)],
        text: '$_photoSubject - ${widget.booking.name}',
      );
    } catch (e) {
      if (!_isDisposed && mounted) {
        _showError('ไม่สามารถแชร์รูปได้: ${e.toString()}');
      }
    }
  }

  Future<void> _startJob() async {
    if (_isDisposed || !mounted) {
      print('❌ [StartJob] Widget disposed');
      return;
    }

    if (_pickedImage == null) {
      _showError('กรุณาถ่าย$_photoSubjectก่อน');
      return;
    }

    // เช็คว่าวันที่วางแผนออกเดินทางตรงกับวันปัจจุบันหรือไม่
    if (!widget.booking.canStartJob()) {
      // แสดง popup แจ้งเตือน
      final proceed = await _showDateWarningDialog();
      if (!proceed) {
        return; // ยกเลิกการเริ่มงาน
      }
    }

    if (!_isDisposed && mounted) {
      setState(() => _isUploading = true);
    }

    try {
      print('🚀 [StartJob] Starting job for booking: ${widget.booking.id}');
      
      print('📍 [StartJob] Permission will be requested when tracking starts...');
      
      // ✅ เช็ค session ก่อนอัพโหลด
      // if (!await _odooService.isSessionValid()) {
      //   print('❌ [StartJob] Session expired!');
      //   if (!_isDisposed && mounted) {
      //     _showError('เซสชั่นหมดอายุ กรุณา login ใหม่');
      //   }
      //   if (mounted) {
      //     Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      //   }
      //   return;
      // }
      
      // อัพโหลดรูปและเริ่มงาน
      // อ่านตำแหน่งจริงก่อนส่ง เพื่อให้จุด GPS แรกของเที่ยวเป็นที่ที่คนขับ
      // ยืนอยู่จริง ไม่ใช่พิกัดคลังที่วางแผนไว้
      // จับไม่ติดก็ไม่เป็นไร ฝั่ง Odoo ถอยไปใช้พิกัดคลังเอง ไม่ควรขวางการเริ่มงาน
      Position? startPosition;
      try {
        startPosition = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 12),
          ),
        );
        print('OK [StartJob] ตำแหน่งตอนเริ่มงาน '
            '${startPosition.latitude}, ${startPosition.longitude}');
      } catch (e) {
        print('[StartJob] อ่านตำแหน่งไม่ได้ จะให้ Odoo ใช้พิกัดคลังแทน: $e');
      }

      final success = await _odooService.startJobWithPhoto(
        bookingId: widget.booking.id,
        photoPath: _photos.first.path,
        extraPhotoPaths: _photos.skip(1).map((f) => f.path).toList(),
        driverLatitude: startPosition?.latitude,
        driverLongitude: startPosition?.longitude,
      );

      if (_isDisposed) return;

      if (success && mounted) {
        print('✅ [StartJob] Job started successfully');
        
        print('📍 [StartJob] Starting location tracking (forced)...');
        
        // โหลด settings และแก้ให้เปิด tracking
        await _trackingService.loadSettings();
        
        // เริ่มติดตามตำแหน่ง (บังคับเปิด)
        final trackingStarted = await _trackingService.startTracking(
          widget.booking,
          forceStart: true,  // ✅ บังคับเปิดเสมอ
        );
        
        if (_isDisposed) return;

        if (trackingStarted) {
          print('✅ [StartJob] Tracking started successfully');
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('เริ่มงานและติดตามตำแหน่งแล้ว'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else {
          print('⚠️ [StartJob] Tracking could not be started');
          
          if (mounted) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.orange[700]),
                    const SizedBox(width: 8),
                    const Text('แจ้งเตือน'),
                  ],
                ),
                content: const Text(
                  'เริ่มงานสำเร็จแล้ว\n\n'
                  'แต่ไม่สามารถเริ่มติดตามตำแหน่งได้\n\n'
                  'กรุณาตรวจสอบ:\n'
                  '• เปิด GPS/Location\n'
                  '• อนุญาตสิทธิ์ Location\n'
                  '• มีสัญญาณ GPS',
                  style: TextStyle(fontSize: 14),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('เข้าใจแล้ว'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Geolocator.openLocationSettings();
                    },
                    child: const Text('เปิดการตั้งค่า GPS'),
                  ),
                ],
              ),
            );
          }
        }
        
        // กลับไปหน้างาน
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } else {
        if (!_isDisposed && mounted) {
          _showError('ไม่สามารถเริ่มงานได้');
        }
      }
    } catch (e) {
      print('❌ [StartJob] Error: $e');
      if (!_isDisposed && mounted) {
        _showError('เกิดข้อผิดพลาด: ${e.toString().substring(0, 100)}');
      }
    } finally {
      if (!_isDisposed && mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<bool> _showDateWarningDialog() async {
    final today = DateTime.now();
    final plannedDate = widget.booking.plannedStartDate;
    
    String dateMessage;
    if (plannedDate == null) {
      dateMessage = 'งานนี้ยังไม่มีวันที่วางแผนออกเดินทาง';
    } else {
      final dayDiff = plannedDate.difference(DateTime(today.year, today.month, today.day)).inDays;
      if (dayDiff > 0) {
        dateMessage = 'วันที่วางแผนออกเดินทาง: ${_formatDate(plannedDate)}\n(อีก $dayDiff วัน)';
      } else if (dayDiff < 0) {
        dateMessage = 'วันที่วางแผนออกเดินทาง: ${_formatDate(plannedDate)}\n(เลยมา ${-dayDiff} วันแล้ว)';
      } else {
        dateMessage = 'วันที่วางแผนออกเดินทาง: ${_formatDate(plannedDate)}';
      }
    }

    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange[700], size: 32),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'แจ้งเตือน',
                  style: TextStyle(fontSize: 20),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dateMessage,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange[700]),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'วันที่ไม่ตรงกับวันปัจจุบัน\nคุณต้องการเริ่มงานต่อหรือไม่?',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'ยกเลิก',
                style: TextStyle(fontSize: 16),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[700],
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'ดำเนินการต่อ',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        );
      },
    ) ?? false;
  }

  String _formatDate(DateTime date) {
    const months = [
      'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
      'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year + 543}';
  }

  void _showError(String message) {
    if (_isDisposed || !mounted) {
      print('⚠️ [Error] Widget disposed, skipping error: $message');
      return;
    }
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error, color: Colors.red),
            SizedBox(width: 12),
            Text('ข้อผิดพลาด'),
          ],
        ),
        content: Text(message),
        actions: [
          ElevatedButton(
            onPressed: () {
              if (mounted) Navigator.pop(context);
            },
            child: const Text('ตกลง'),
          ),
        ],
      ),
    );
  }

  // ✅ ฟังก์ชั่นแปลง DateTime เป็นข้อความ
  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')} น.';
  }
}
