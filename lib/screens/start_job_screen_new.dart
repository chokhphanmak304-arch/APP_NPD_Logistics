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
  
  File? _pickedImage;
  bool _isUploading = false;
  
  // ✅ เพิ่มตรงนี้
  bool _isDisposed = false;
  bool _isPickingImage = false;  // ✅ ป้องกันการถ่ายภาพซ้ำ

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);  // ✅ เพิ่ม
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📸 ถ่ายรูปสินค้า'),
        backgroundColor: Colors.blue[700],
      ),
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
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '📋 ${widget.booking.name}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(),
            Text('📍 รับที่: ${widget.booking.pickupLocation ?? "-"}'),
            const SizedBox(height: 4),
            Text('🎯 ส่งที่: ${widget.booking.destination ?? "-"}'),
            const SizedBox(height: 4),
            Text('👤 ลูกค้า: ${widget.booking.partnerName ?? "-"}'),
            const SizedBox(height: 4),
            // ✅ วางแผนการออกเดินทาง
            if (widget.booking.plannedStartDate != null)
              Text('⏰ วางแผนออกเดินทาง: ${_formatDateTime(widget.booking.plannedStartDate!)}'),
            const SizedBox(height: 4),
            // ✅ เวลาออกเดินทางจริง (บันทึกจากแอป)
            if (widget.booking.plannedStartDateT != null)
              Text('⏱️ เวลาออกจริง: ${_formatDateTime(widget.booking.plannedStartDateT!)}', 
                style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            // 💰 ค่าใช้จ่าย
            if ((widget.booking.shippingCost != null && widget.booking.shippingCost! > 0) ||
                (widget.booking.travelExpenses != null && widget.booking.travelExpenses! > 0) ||
                (widget.booking.dailyAllowance != null && widget.booking.dailyAllowance! > 0))
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('💰 ค่าใช้จ่าย:', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[700])),
                  const SizedBox(height: 4),
                  if (widget.booking.shippingCost != null && widget.booking.shippingCost! > 0)
                    Text('  🚛 ค่าขนส่ง: ${widget.booking.shippingCost!.toStringAsFixed(2)} บาท'),
                  if (widget.booking.travelExpenses != null && widget.booking.travelExpenses! > 0)
                    Text('  🚗 ค่าเที่ยว: ${widget.booking.travelExpenses!.toStringAsFixed(2)} บาท'),
                  if (widget.booking.dailyAllowance != null && widget.booking.dailyAllowance! > 0)
                    Text('  🍽️ ค่าเบี้ยเลี้ยง: ${widget.booking.dailyAllowance!.toStringAsFixed(2)} บาท'),
                ],
              ),
            // ✅ เวลาโดยประมาณ
            if (widget.booking.estimatedTime != null && widget.booking.estimatedTime!.isNotEmpty)
              Text('⏳ เวลาโดยประมาณ: ${widget.booking.estimatedTime}',
                style: TextStyle(color: Colors.amber[700], fontWeight: FontWeight.w600)),
          ],
        ),
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
                Icon(Icons.info_outline, color: Colors.blue[700]),
                const SizedBox(width: 8),
                Text(
                  'ℹ️ คำแนะนำ',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('• ถ่ายรูปสินค้าก่อนเริ่มงาน'),
            const SizedBox(height: 4),
            const Text('• ให้เห็นสภาพสินค้าชัดเจน'),
            const SizedBox(height: 4),
            const Text('• บันทึกเวลาเริ่มงาน'),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    return Card(
      elevation: 2,
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              _pickedImage!,
              width: double.infinity,
              height: 300,
              fit: BoxFit.cover,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton.icon(
                  onPressed: () {
                    if (!_isDisposed && mounted) {
                      setState(() {
                        _pickedImage = null;
                      });
                    }
                  },
                  icon: const Icon(Icons.delete, color: Colors.red),
                  label: const Text('ถ่ายใหม่'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraButtons() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: () => _pickImage(ImageSource.camera),
        icon: const Icon(Icons.camera_alt, size: 28),
        label: const Text(
          'เปิดกล้องถ่ายรูป',
          style: TextStyle(fontSize: 18),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue[700],
          foregroundColor: Colors.white,
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
              _isUploading ? 'กำลังเริ่มงาน...' : '🚚 เริ่มงานขนส่ง',
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
      
      // ✅ FIX CRITICAL: ลบรูปเก่าก่อนถ่ายใหม่ (ป้องกัน memory leak)
      if (_pickedImage != null) {
        try {
          print('🗑️ [StartJob] Deleting old photo to free memory...');
          final oldFile = _pickedImage!;
          _pickedImage = null; // Clear reference first
          
          if (await oldFile.exists()) {
            await oldFile.delete();
            print('✅ [StartJob] Old photo deleted successfully');
          }
        } catch (e) {
          print('⚠️ [StartJob] Could not delete old photo: $e');
        }
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
            _pickedImage = imageFile;
            print('✅ [StartJob] Photo set - Size: ${(fileSize / 1024).toStringAsFixed(1)} KB');
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
        text: 'รูปสินค้า - ${widget.booking.name}',
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
      _showError('กรุณาถ่ายรูปสินค้าก่อน');
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
      final success = await _odooService.startJobWithPhoto(
        bookingId: widget.booking.id,
        photoPath: _pickedImage!.path,
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
                content: Text('✅ เริ่มงานและติดตามตำแหน่งสำเร็จ!'),
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
                    const Text('⚠️ แจ้งเตือน'),
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
            Text('❌ ข้อผิดพลาด'),
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
