import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:signature/signature.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/booking.dart';
import '../models/driver.dart';
import '../services/odoo_service.dart';
import '../services/tracking_service.dart';
import '../services/camera_protection_service.dart';  // 🛡️ เพิ่มการป้องกัน!
import '../widgets/bottom_nav_bar.dart';

// ✅ Global cleanup function
Future<void> _cleanupImageCache() async {
  try {
    imageCache.clearLiveImages();
    imageCache.clear();
    
    final tempDir = await getTemporaryDirectory();
    final files = tempDir.listSync();
    for (var file in files) {
      if (file is File && file.path.contains('signature_')) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
  } catch (e) {
    print('📝 Cleanup error: $e');
  }
}

class DeliveryCompletionScreen extends StatefulWidget {
  final Booking booking;
  final Driver? driver;

  const DeliveryCompletionScreen({
    super.key,
    required this.booking,
    this.driver,
  });

  @override
  State<DeliveryCompletionScreen> createState() => _DeliveryCompletionScreenState();
}

class _DeliveryCompletionScreenState extends State<DeliveryCompletionScreen> 
    with WidgetsBindingObserver {
  final OdooService _odooService = OdooService();
  final TrackingService _trackingService = TrackingService();
  final ImagePicker _picker = ImagePicker();
  final SignatureController _signatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  final TextEditingController _receiverNameController = TextEditingController();
  // ตำแหน่งผู้รับ บังคับกรอกเสมอ ไม่ว่าจะเซ็นเองหรือเซ็นแทน เพราะของหายแล้ว
  // ชื่ออย่างเดียวตามตัวคนไม่ได้ ต้องรู้ว่าเขาอยู่ในฐานะอะไรถึงรับของได้
  final TextEditingController _receiverPositionController =
      TextEditingController();
  
  // รูปหลักฐานการส่ง เก็บได้หลายใบ ลูกค้าบางรายต้องการรูปของที่วางหน้างาน
  // หลายมุม และรูปเดียวไม่พอยืนยันตอนมีปัญหาของเสียหายย้อนหลัง
  final List<File> _deliveryPhotos = [];
  static const int _maxPhotos = 10;

  /// รูปแรก — โค้ดส่วนที่เหลือใช้เช็คแค่ว่ามีรูปแล้วหรือยัง
  File? get _deliveryPhoto =>
      _deliveryPhotos.isEmpty ? null : _deliveryPhotos.first;
  File? _watermarkedPhoto;
  Position? _currentPosition;
  bool _isSubmitting = false;
  bool _signedBySelf = false;
  bool _isDisposed = false;  // ✅ Track disposal
  bool _isPickingImage = false;  // ✅ ป้องกันการถ่ายภาพซ้ำ

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);  // ✅ Add lifecycle observer
    
    _signatureController.addListener(() {
      if (mounted && !_isDisposed) {
        setState(() {
          print('🔍 [Signature] Changed - points: ${_signatureController.points.length}');
        });
      }
    });
    
    _receiverNameController.addListener(_onReceiverFieldChanged);
    _receiverPositionController.addListener(_onReceiverFieldChanged);
    
    _fetchCurrentLocation();
  }

  /// ปุ่มยืนยันเปิด/ปิดตามความครบของช่อง จึงต้องวาดใหม่ทุกครั้งที่พิมพ์
  void _onReceiverFieldChanged() {
    if (mounted && !_isDisposed) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);  // ✅ Remove observer
    _isDisposed = true;
    _cleanupMemory();
    _signatureController.dispose();
    _receiverNameController.dispose();
    _receiverPositionController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      print('⏸️ [DeliveryScreen] App paused - camera opened');
      // ✅ FIX: ไม่ต้อง cleanup ตอน pause เพราะจะทำตอน resume
    } else if (state == AppLifecycleState.resumed) {
      print('▶️ [DeliveryScreen] App resumed - camera closed');
      // ✅ FIX: Cleanup หลังกลับจากกล้อง
      if (!_isDisposed && mounted) {
        _cleanupMemory();
        // ✅ Refresh session อีกครั้ง
        _odooService.refreshSessionIfNeeded().catchError((e) {
          print('⚠️ [DeliveryScreen] Session refresh on resume failed: $e');
        });
      }
    }
  }

  void _cleanupMemory() {
    try {
      if (!_isDisposed && mounted) {
        imageCache.clear();
        imageCache.clearLiveImages();
        print('✅ [DeliveryScreen] Memory cleaned');
      }
    } catch (e) {
      print('⚠️ [DeliveryScreen] Cleanup error: $e');
    }
  }

  Future<void> _fetchCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted && !_isDisposed) {
        setState(() => _currentPosition = position);
      }
    } catch (e) {
      print('❌ GPS Error: $e');
    }
  }

  /// 🎨 เพิ่มลายน้ำลงในรูป (ที่ด้านล่าง)
  Future<File?> _addWatermarkToImage(File imageFile) async {
    try {
      print('🎨 [Watermark] เริ่มสร้างลายน้ำ...');
      
      final imageBytes = await imageFile.readAsBytes();
      print('🎨 [Watermark] Image size: ${imageBytes.length / 1024 / 1024} MB');
      
      var originalImage = img.decodeImage(imageBytes);
      
      if (originalImage == null) {
        print('❌ [Watermark] ไม่สามารถอ่านรูปภาพ');
        return null;
      }

      print('🎨 [Watermark] Original size: ${originalImage.width}x${originalImage.height}');
      if (originalImage.width > 1920 || originalImage.height > 1080) {
        print('📉 [Watermark] Resizing image...');
        originalImage = img.copyResize(
          originalImage,
          width: 1920,
          height: 1080,
          maintainAspect: true,
        );
        print('✅ [Watermark] Resized to: ${originalImage.width}x${originalImage.height}');
      }

      final now = DateTime.now();
      final timeText = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      final dateText = '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${(now.year + 543).toString()}';
      
      final locationText = _currentPosition != null 
          ? 'LAT: ${_currentPosition!.latitude.toStringAsFixed(4)} | LNG: ${_currentPosition!.longitude.toStringAsFixed(4)}'
          : 'LAT: N/A | LNG: N/A';

      print('📝 [Watermark] Time: $timeText');
      print('📝 [Watermark] Date: $dateText');
      print('📝 [Watermark] Location: $locationText');

      final watermarkHeight = 140;
      final newHeight = originalImage.height + watermarkHeight;
      
      final newImage = img.Image(
        width: originalImage.width,
        height: newHeight,
      );

      img.compositeImage(newImage, originalImage, dstY: 0);

      img.fillRect(
        newImage,
        x1: 0,
        y1: originalImage.height,
        x2: newImage.width,
        y2: newHeight,
        color: img.ColorInt8.rgba(10, 10, 10, 255),
      );

      img.drawLine(
        newImage,
        x1: 0,
        y1: originalImage.height,
        x2: newImage.width,
        y2: originalImage.height,
        color: img.ColorInt8.rgba(255, 193, 7, 255),
      );

      _drawCheckmark(newImage, 20, originalImage.height + 15);

      img.drawLine(
        newImage,
        x1: 50,
        y1: originalImage.height + 10,
        x2: 50,
        y2: originalImage.height + 130,
        color: img.ColorInt8.rgba(100, 100, 100, 200),
      );

      final newImageBytes = img.encodePng(newImage);

      final tempDir = await getTemporaryDirectory();
      final watermarkedFile = File(
        '${tempDir.path}/watermarked_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await watermarkedFile.writeAsBytes(newImageBytes);

      print('✅ [Watermark] สร้างลายน้ำสำเร็จ');
      
      return watermarkedFile;
    } catch (e) {
      print('❌ [Watermark] เกิดข้อผิดพลาด: $e');
      _showError('ไม่สามารถสร้างลายน้ำ: $e');
      return null;
    }
  }

  void _drawCheckmark(img.Image image, int x, int y) {
    final size = 20;
    final color = img.ColorInt8.rgba(76, 175, 80, 255);
    
    img.drawRect(
      image,
      x1: x,
      y1: y,
      x2: x + size,
      y2: y + size,
      color: color,
      thickness: 2,
    );
    
    img.drawLine(
      image,
      x1: x + 6,
      y1: y + 10,
      x2: x + 10,
      y2: y + 15,
      color: color,
    );
    
    img.drawLine(
      image,
      x1: x + 10,
      y1: y + 15,
      x2: x + 16,
      y2: y + 5,
      color: color,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isHelpBranch ? 'จบงานช่วยสาขา' : 'ส่งของถึงแล้ว'),
        backgroundColor: const Color(0xFF15803D),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF5F6F8),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildJobInfoCard(),
            const SizedBox(height: 18),
            _buildStep(1, _photoStepTitle, _deliveryPhoto != null,
                _buildPhotoSection()),
            const SizedBox(height: 18),
            _buildStep(2, 'ข้อมูล$_receiverLabel', _receiverInfoComplete,
                _buildReceiverFields()),
            const SizedBox(height: 18),
            _buildStep(3, 'ลายเซ็น$_receiverLabel', _signatureController.isNotEmpty,
                _buildSignatureSection()),
            const SizedBox(height: 22),
            _buildActionButtons(),
          ],
        ),
      ),
      bottomNavigationBar: widget.driver != null
          ? CustomBottomNavBar(
              currentIndex: 1,
              driver: widget.driver!,
            )
          : null,
    );
  }

  /// เที่ยวช่วยสาขาไม่มีผู้รับสินค้า แต่มีคนของสาขาปลายทางรับรองแทน
  bool get _isHelpBranch => widget.booking.isHelpBranch;

  String get _receiverLabel => _isHelpBranch ? 'ผู้รับรอง' : 'ผู้รับ';

  String get _photoStepTitle => _isHelpBranch
      ? 'ถ่ายรูปงานที่ไปช่วย'
      : 'ถ่ายรูปหลักฐานการส่ง';

  String get _photoHint => _isHelpBranch
      ? 'ถ่ายงานที่ไปช่วย ณ สาขาปลายทาง ให้เห็นว่าไปถึงจริง'
      : 'ให้เห็นสภาพสินค้าและจุดที่วางของ';

  /// เกณฑ์เดียวที่ใช้ตัดสินว่าข้อมูลผู้รับครบ ใช้ร่วมกันทั้งไฟ ปุ่ม และ
  /// การตรวจก่อนส่ง จะได้ไม่มีทางที่จอบอกว่าครบแต่ปุ่มยังกดไม่ได้
  bool get _receiverInfoComplete =>
      _receiverNameController.text.trim().isNotEmpty &&
      _receiverPositionController.text.trim().isNotEmpty;

  /// กล่องขั้นตอน — เลขลำดับกับไฟเขียวบอกว่าเหลืออะไรต้องทำ
  Widget _buildStep(int number, String title, bool done, Widget child) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: done ? const Color(0xFFBBF7D0) : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: done
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFE5E7EB),
                    shape: BoxShape.circle,
                  ),
                  child: done
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : Text(
                          '$number',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade700,
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildJobInfoCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF15803D),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'เลขที่จอง',
            style: TextStyle(
              fontSize: 11.5,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            widget.booking.name,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          _jobLine(Icons.place_outlined, 'ปลายทาง',
              widget.booking.destination ?? '-'),
          const SizedBox(height: 8),
          _jobLine(Icons.person_outline, 'ลูกค้า',
              widget.booking.partnerName ?? '-'),
        ],
      ),
    );
  }

  Widget _jobLine(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.75)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.1,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPhotoSection() {
    if (_deliveryPhotos.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(_photoHint,
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
          ),
          SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          onPressed: () => _pickDeliveryPhoto(ImageSource.camera),
          icon: const Icon(Icons.camera_alt_outlined, size: 20),
          label: const Text('เปิดกล้องถ่ายรูป',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF15803D),
            foregroundColor: Colors.white,
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'ถ่ายแล้ว ${_deliveryPhotos.length}/$_maxPhotos รูป',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            const Spacer(),
            if (_deliveryPhotos.length > 1)
              TextButton.icon(
                onPressed: () => setState(_deliveryPhotos.clear),
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
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(_deliveryPhotos.first,
              width: double.infinity, height: 190, fit: BoxFit.cover),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 78,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _deliveryPhotos.length +
                (_deliveryPhotos.length < _maxPhotos ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              if (index == _deliveryPhotos.length) {
                return GestureDetector(
                  onTap: _isPickingImage
                      ? null
                      : () => _pickDeliveryPhoto(ImageSource.camera),
                  child: Container(
                    width: 78,
                    height: 78,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo_outlined,
                            size: 21, color: Colors.grey.shade600),
                        const SizedBox(height: 4),
                        Text('เพิ่มรูป',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade700)),
                      ],
                    ),
                  ),
                );
              }
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(_deliveryPhotos[index],
                        width: 78, height: 78, fit: BoxFit.cover),
                  ),
                  Positioned(
                    right: -6,
                    top: -6,
                    child: GestureDetector(
                      onTap: () =>
                          setState(() => _deliveryPhotos.removeAt(index)),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Color(0xFFDC2626),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close,
                            size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _shareDeliveryPhoto,
            icon: const Icon(Icons.share_outlined, size: 19),
            label: const Text('แชร์รูปแรก'),
            style: TextButton.styleFrom(foregroundColor: Colors.grey.shade700),
          ),
        ),
      ],
    );
  }

  Widget _buildReceiverFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _receiverField(
          controller: _receiverNameController,
          label: 'ชื่อ$_receiverLabel',
          hint: _signedBySelf
              ? 'ชื่อคนที่เซ็นแทน'
              : (_isHelpBranch
                  ? 'ชื่อคนของสาขาที่ไปช่วย'
                  : 'ชื่อผู้รับสินค้า'),
          icon: Icons.person_outline,
        ),
        const SizedBox(height: 12),
        _receiverField(
          controller: _receiverPositionController,
          label: 'ตำแหน่ง$_receiverLabel',
          hint: _isHelpBranch
              ? 'เช่น หัวหน้าสาขา พนักงานคลัง'
              : 'เช่น เจ้าของบ้าน ยาม หัวหน้าช่าง',
          icon: Icons.badge_outlined,
        ),
        if (_signedBySelf) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline,
                    size: 18, color: Color(0xFFB45309)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'เซ็นรับแทน — ระบุให้ชัดว่าใครเซ็นและอยู่ในฐานะอะไร '
                    'ข้อมูลนี้ใช้ยืนยันย้อนหลังเมื่อมีปัญหาเรื่องของ',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF92400E)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// ช่องกรอกที่บังคับทั้งคู่ ขอบแดงขึ้นทันทีที่ว่าง จะได้ไม่ต้องกดปุ่มแล้ว
  /// ค่อยรู้ว่าขาดอะไร (ของเดิมเตือนเฉพาะตอนเปิดสวิตช์เซ็นรับแทน)
  Widget _receiverField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
  }) {
    final bool empty = controller.text.trim().isEmpty;
    final Color line =
        empty ? const Color(0xFFFCA5A5) : const Color(0xFFD1D5DB);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(width: 4),
            const Text('*',
                style: TextStyle(fontSize: 13, color: Color(0xFFDC2626))),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          textCapitalization: TextCapitalization.words,
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(fontSize: 14, color: Colors.grey.shade400),
            prefixIcon: Icon(icon, size: 20, color: Colors.grey.shade500),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            filled: true,
            fillColor: empty ? const Color(0xFFFEF2F2) : Colors.white,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: line, width: 1.4),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: Color(0xFF15803D), width: 1.8),
            ),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _buildSignatureSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: SwitchListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            title: Text(
                _isHelpBranch
                    ? 'ไม่เจอผู้รับรอง — ให้คนอื่นเซ็นแทน'
                    : 'ไม่เจอลูกค้า — ให้คนอื่นเซ็นรับแทน',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            activeThumbColor: const Color(0xFF15803D),
            value: _signedBySelf,
            onChanged: (value) {
              setState(() {
                _signedBySelf = value;
                // ล้างทั้งสองช่อง เพราะคนที่เซ็นเปลี่ยนคนแล้ว ถ้าเหลือค่าเดิม
                // ไว้จะกลายเป็นชื่อลูกค้าคู่กับตำแหน่งของยาม
                _receiverNameController.clear();
                _receiverPositionController.clear();
              });
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                'ให้ผู้รับเซ็นในกรอบด้านล่าง',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
              ),
            ),
            if (_signatureController.isNotEmpty)
              TextButton.icon(
                onPressed: _signatureController.clear,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('ล้างลายเซ็น'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey.shade700,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 190,
          decoration: BoxDecoration(
            border: Border.all(
              color: _signatureController.isNotEmpty
                  ? const Color(0xFFBBF7D0)
                  : const Color(0xFFFCA5A5),
              width: 1.4,
            ),
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Signature(
                controller: _signatureController,
                backgroundColor: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    final hasPhoto = _deliveryPhoto != null;
    final hasSignature = _signatureController.isNotEmpty;
    final hasName = _receiverNameController.text.trim().isNotEmpty;
    final hasPosition = _receiverPositionController.text.trim().isNotEmpty;
    final isReadyToSubmit = hasPhoto && hasSignature && hasName && hasPosition;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!isReadyToSubmit) ...[
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ยังขาดอยู่',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.orange.shade900,
                  ),
                ),
                const SizedBox(height: 8),
                _buildChecklistItem(
                    _isHelpBranch ? 'รูปงานที่ไปช่วย' : 'รูปหลักฐานการส่ง',
                    hasPhoto),
                _buildChecklistItem('ชื่อ$_receiverLabel', hasName),
                _buildChecklistItem('ตำแหน่ง$_receiverLabel', hasPosition),
                _buildChecklistItem('ลายเซ็น$_receiverLabel', hasSignature),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        SizedBox(
          height: 54,
          child: ElevatedButton.icon(
            onPressed:
                (!isReadyToSubmit || _isSubmitting) ? null : _completeDelivery,
            icon: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline, size: 22),
            label: Text(
              _isSubmitting
                  ? 'กำลังบันทึก...'
                  : (_isHelpBranch ? 'ยืนยันจบงาน' : 'ยืนยันส่งของเสร็จสิ้น'),
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF15803D),
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
              disabledForegroundColor: Colors.grey.shade600,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChecklistItem(String label, bool isComplete) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            isComplete
                ? Icons.check_circle
                : Icons.radio_button_unchecked,
            color: isComplete ? const Color(0xFF16A34A) : Colors.grey.shade400,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              color: isComplete ? Colors.grey.shade500 : Colors.grey.shade800,
              decoration: isComplete ? TextDecoration.lineThrough : null,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDeliveryPhoto(ImageSource source) async {
    if (_deliveryPhotos.length >= _maxPhotos) {
      _showError('ถ่ายได้สูงสุด $_maxPhotos รูป ลบรูปเก่าออกก่อน');
      return;
    }
    // ✅ FIX: ป้องกันการถ่ายภาพซ้ำๆ
    if (_isPickingImage) {
      print('⚠️ [DeliveryScreen] Already picking image, ignoring...');
      return;
    }
    
    if (_isDisposed) {
      print('❌ [DeliveryScreen] Widget already disposed');
      return;
    }

    // ✅ FIX: ตั้งค่า flag ป้องกันการกดซ้ำ
    setState(() => _isPickingImage = true);

    try {
      print('📷 [DeliveryScreen] Starting photo pick...');
      
      // ไม่ลบรูปเก่าแล้ว เพราะหน้านี้เก็บได้หลายใบ
      // คุมหน่วยความจำด้วยการจำกัดจำนวนรูปด้านบนแทน
      
      // ✅ Clear cache before opening camera
      imageCache.clear();
      imageCache.clearLiveImages();
      print('✅ [DeliveryScreen] Cache cleared before camera');
      
      // ✅ FIX: Refresh session ก่อนเปิดกล้อง
      try {
        await _odooService.refreshSessionIfNeeded();
        print('✅ [DeliveryScreen] Session refreshed');
      } catch (e) {
        print('⚠️ [DeliveryScreen] Session refresh failed: $e');
      }
      
      // ✅ FIX 1: Only request CAMERA permission
      // image_picker handles temp file creation automatically
      PermissionStatus cameraStatus = PermissionStatus.denied;
      
      if (source == ImageSource.camera) {
        print('📷 [DeliveryScreen] Requesting camera permission...');
        cameraStatus = await Permission.camera.request();
      } else {
        print('🖼️ [DeliveryScreen] Requesting photo permission...');
        cameraStatus = await Permission.photos.request();
      }

      print('📷 [DeliveryScreen] Camera Permission status: $cameraStatus');
      
      // ✅ FIXED: Only check camera permission, not storage
      if (!cameraStatus.isGranted) {
        if (!_isDisposed && mounted) {
          String permissionMsg = source == ImageSource.camera ? 'กล้อง' : 'รูปภาพ';
          _showError('กรุณาอนุญาตการเข้าถึง: $permissionMsg');
        }
        return;
      }

      print('📷 [DeliveryScreen] Picking image with quality optimization...');
      
      late XFile? image;
      try {
        // 🛡️ CRITICAL: Wrap ด้วย CameraProtectionService เพื่อป้องกันแอปถูกฆ่า!
        image = await CameraProtectionService.withProtection(() async {
          return await _picker.pickImage(
            source: source, 
            maxWidth: 1920,
            maxHeight: 1080,
            imageQuality: 85,
            preferredCameraDevice: CameraDevice.rear,
            requestFullMetadata: false,
          );
        }).timeout(
          const Duration(seconds: 180),
          onTimeout: () {
            print('⏱️ [DeliveryScreen] Camera timeout after 180s!');
            return null;
          },
        );
      } on PlatformException catch (e) {
        print('❌ [DeliveryScreen] PlatformException: ${e.code} - ${e.message}');
        if (!_isDisposed && mounted) {
          String errorMsg = 'ไม่สามารถเข้าถึงกล้องได้';
          if (e.code == 'camera_access_denied') {
            errorMsg = 'การเข้าถึงกล้องถูกปฏิเสธ กรุณาเปิดอนุญาตในการตั้งค่า';
          } else if (e.code == 'photo_access_denied') {
            errorMsg = 'การเข้าถึงรูปภาพถูกปฏิเสธ';
          }
          _showError(errorMsg);
        }
        return;
      } catch (e) {
        print('❌ [DeliveryScreen] Image picker error: $e');
        if (!_isDisposed && mounted) {
          _showError('ไม่สามารถเปิดกล้องได้: ${e.toString().substring(0, 50)}');
        }
        return;
      }

      print('📷 [DeliveryScreen] Image picked: ${image?.path}');
      
      // ✅ FIX: Refresh session หลังกลับจากกล้อง
      if (!_isDisposed) {
        try {
          await _odooService.refreshSessionIfNeeded();
          print('✅ [DeliveryScreen] Session refreshed after camera');
        } catch (e) {
          print('⚠️ [DeliveryScreen] Session refresh after camera failed: $e');
        }
      }
      
      // ✅ FIX 3: Proper disposed check after async operation
      if (_isDisposed) {
        print('❌ [DeliveryScreen] Widget disposed after image pick');
        if (image != null) {
          try {
            final tempFile = File(image.path);
            if (await tempFile.exists()) {
              await tempFile.delete();
            }
          } catch (e) {
            print('⚠️ [DeliveryScreen] Could not clean temp file: $e');
          }
        }
        return;
      }
      
      if (image != null) {
        try {
          final imageFile = File(image.path);
          
          // Check if file exists before reading
          if (!await imageFile.exists()) {
            print('❌ [DeliveryScreen] Image file does not exist');
            if (!_isDisposed && mounted) {
              _showError('ไม่พบไฟล์รูปภาพ');
            }
            return;
          }
          
          final fileSize = await imageFile.length();
          print('📏 [DeliveryScreen] File size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');
          
          // Check file size
          if (fileSize > 15 * 1024 * 1024) {
            if (!_isDisposed && mounted) {
              _showError('รูปภาพใหญ่เกินไป (> 15MB) กรุณาเลือกรูปที่เล็กกว่า');
            }
            return;
          }
          
          // Check if file size is too small (likely corrupted)
          if (fileSize < 1000) {
            if (!_isDisposed && mounted) {
              _showError('รูปภาพเสียหายหรือไม่สมบูรณ์');
            }
            return;
          }
          
          // ✅ FIX 4: Cleanup image cache before setting new image
          imageCache.clear();
          imageCache.clearLiveImages();
          
          // ✅ FIX 5: Final disposed check before setState
          if (!mounted || _isDisposed) {
            print('❌ [DeliveryScreen] Widget no longer mounted');
            return;
          }
          
          setState(() {
            _deliveryPhotos.add(imageFile);
            print('✅ [DeliveryScreen] Photo set successfully - Size: ${(fileSize / 1024).toStringAsFixed(1)} KB');
          });
          
        } catch (e) {
          print('❌ [DeliveryScreen] Error processing image file: $e');
          if (!_isDisposed && mounted) {
            _showError('ไม่สามารถประมวลผลรูปภาพได้: ${e.toString().substring(0, 100)}');
          }
        }
      } else if (!_isDisposed) {
        print('⚠️ [DeliveryScreen] Image pick cancelled or timed out');
      }
    } catch (e) {
      print('❌ [DeliveryScreen] Unexpected error in _pickDeliveryPhoto: $e');
      if (!_isDisposed && mounted) {
        _showError('เกิดข้อผิดพลาดที่ไม่คาดคิด: ${e.toString().substring(0, 100)}');
      }
    } finally {
      // ✅ FIX: ปลดล็อค flag ไม่ว่าจะสำเร็จหรือไม่
      if (!_isDisposed && mounted) {
        setState(() => _isPickingImage = false);
        print('✅ [DeliveryScreen] Image picking completed, flag reset');
      }
    }
  }

  Future<void> _shareDeliveryPhoto() async {
    if (_deliveryPhoto == null) return;
    try {
      await Share.shareXFiles([XFile(_deliveryPhoto!.path)], text: 'รูปการส่งสินค้า - ${widget.booking.name}');
    } catch (e) {
      _showError('ไม่สามารถแชร์รูปได้');
    }
  }

  Future<void> _completeDelivery() async {
    if (_isDisposed) {
      print('❌ [CompleteDelivery] Widget disposed');
      return;
    }

    if (_deliveryPhoto == null) { 
      _showError('กรุณาถ่ายรูปสินค้า'); 
      return; 
    }
    if (_signatureController.isEmpty) { 
      _showError('กรุณาให้ลูกค้าเซ็นชื่อ'); 
      return; 
    }
    if (_receiverNameController.text.trim().isEmpty) { 
      _showError('กรุณากรอกชื่อ$_receiverLabel'); 
      return; 
    }
    if (_receiverPositionController.text.trim().isEmpty) {
      _showError(_isHelpBranch
          ? 'กรุณากรอกตำแหน่งผู้รับรอง เช่น หัวหน้าสาขา พนักงานคลัง'
          : 'กรุณากรอกตำแหน่งผู้รับ เช่น เจ้าของบ้าน ยาม หัวหน้าช่าง');
      return;
    }

    if (mounted) setState(() => _isSubmitting = true);

    try {
      print('📸 [CompleteDelivery] Starting delivery completion...');
      
      if (!_isDisposed && !mounted) {
        print('❌ [CompleteDelivery] Widget disposed during operation');
        return;
      }

      // ✅ เช็ค session validity ก่อน
      // if (!await _odooService.isSessionValid()) {
      //   print('❌ [CompleteDelivery] Session expired!');
      //   if (!_isDisposed && mounted) {
      //     _showError('เซสชั่นหมดอายุ กรุณา login ใหม่');
      //   }
      //   if (mounted) {
      //     Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      //   }
      //   return;
      // }

      _watermarkedPhoto = _deliveryPhoto;
      print('✅ Using original photo without watermark');

      if (!_isDisposed && !mounted) {
        print('❌ [CompleteDelivery] Widget disposed before signature processing');
        return;
      }

      print('📝 [CompleteDelivery] Getting signature bytes...');
      final Uint8List? signatureBytes = await _signatureController.toPngBytes();
      
      if (signatureBytes == null) { 
        print('❌ [CompleteDelivery] Signature bytes is null');
        if (!_isDisposed && mounted) _showError('ไม่สามารถบันทึกลายเซ็นได้'); 
        return; 
      }
      print('✅ [CompleteDelivery] Signature bytes: ${signatureBytes.length} bytes');

      if (!_isDisposed && !mounted) return;

      print('📁 [CompleteDelivery] Getting temp directory...');
      final tempDir = await getTemporaryDirectory();
      final signatureFilePath = '${tempDir.path}/sig_${DateTime.now().millisecondsSinceEpoch}.png';
      
      print('📝 [CompleteDelivery] Writing signature...');
      final signatureFile = File(signatureFilePath);
      
      try {
        await signatureFile.writeAsBytes(signatureBytes);
        print('✅ [CompleteDelivery] Signature written successfully');
      } catch (e) {
        print('❌ [CompleteDelivery] Failed to write signature: $e');
        if (!_isDisposed && mounted) {
          _showError('ไม่สามารถบันทึกลายเซ็นได้ (Disk error)');
        }
        return;
      }

      if (!_isDisposed && !mounted) return;

      print('🌐 [CompleteDelivery] Sending to server...');
      final success = await _odooService.completeDelivery(
        bookingId: widget.booking.id,
        deliveryPhotoPath: _watermarkedPhoto!.path,
        extraDeliveryPhotoPaths:
            _deliveryPhotos.skip(1).map((f) => f.path).toList(),
        signaturePath: signatureFile.path,
        receiverName: _receiverNameController.text.trim(),
        receiverPosition: _receiverPositionController.text.trim(),
        signedBySelf: _signedBySelf,
        deliveryTimestamp: _currentPosition != null ? DateTime.now() : null,
        deliveryLatitude: _currentPosition?.latitude,
        deliveryLongitude: _currentPosition?.longitude,
      );
      print('📥 [CompleteDelivery] Response: success=$success');

      if (!_isDisposed && mounted) {
        if (success) {
          print('✅ Delivery completed successfully');
          _trackingService.stopTracking();
          _cleanupImageCache();
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('บันทึกการส่งสินค้าแล้ว'),
              backgroundColor: Colors.green,
            ),
          );
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) Navigator.of(context).pop(true);
          });
        } else {
          _showError('ไม่สามารถบันทึกข้อมูลได้');
        }
      }
    } catch (e) {
      print('❌ [CompleteDelivery] Error: $e\n${StackTrace.current}');
      if (!_isDisposed && mounted) {
        _showError('เกิดข้อผิดพลาด: ${e.toString().substring(0, 100)}');
      }
    } finally {
      if (!_isDisposed && mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String message) {
    if (_isDisposed || !mounted) {
      print('⚠️ [Error] Widget disposed, skipping dialog: $message');
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
}