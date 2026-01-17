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
  
  File? _deliveryPhoto;
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
    
    _receiverNameController.addListener(() {
      if (mounted && !_isDisposed) {
        setState(() {
          print('🔍 [ReceiverName] Changed');
        });
      }
    });
    
    _fetchCurrentLocation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);  // ✅ Remove observer
    _isDisposed = true;
    _cleanupMemory();
    _signatureController.dispose();
    _receiverNameController.dispose();
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
        title: const Text('✅ ส่งของถึงแล้ว'),
        backgroundColor: Colors.green[700],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildJobInfoCard(),
            const SizedBox(height: 24),
            _buildPhotoSection(),
            const SizedBox(height: 24),
            _buildReceiverNameField(),
            const SizedBox(height: 24),
            _buildSignatureSection(),
            const SizedBox(height: 24),
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

  Widget _buildJobInfoCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📋 ${widget.booking.name}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(),
            Text('🎯 ปลายทาง: ${widget.booking.destination ?? "-"}'),
            const SizedBox(height: 4),
            Text('👤 ลูกค้า: ${widget.booking.partnerName ?? "-"}'),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.camera_alt, color: Colors.green[700]),
                const SizedBox(width: 8),
                const Text('📸 ถ่ายรูปสินค้าหลังส่ง', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            if (_deliveryPhoto != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(_deliveryPhoto!, width: double.infinity, height: 200, fit: BoxFit.cover),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(
                    onPressed: () => setState(() => _deliveryPhoto = null),
                    icon: const Icon(Icons.delete, color: Colors.red),
                    label: const Text('ลบรูป'),
                  ),
                  TextButton.icon(
                    onPressed: _shareDeliveryPhoto,
                    icon: const Icon(Icons.share),
                    label: const Text('แชร์รูป'),
                  ),
                ],
              ),
            ] else ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _pickDeliveryPhoto(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('ถ่ายรูป'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReceiverNameField() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.person, color: Colors.green[700]),
                const SizedBox(width: 8),
                const Text('👤 ชื่อผู้รับ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _receiverNameController,
              decoration: InputDecoration(
                hintText: _signedBySelf 
                    ? 'กรอกชื่อผู้เซ็นรับแทน (บังคับ)' 
                    : 'กรอกชื่อผู้รับ',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.edit),
                // ✅ เพิ่มการเน้นว่าบังคับกรอก เมื่อเปิด toggle
                filled: _signedBySelf,
                fillColor: _signedBySelf ? Colors.orange[50] : null,
                enabledBorder: _signedBySelf 
                    ? OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.orange[300]!, width: 2),
                      )
                    : OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            // ✅ แสดงข้อความเตือนเมื่อเปิด toggle
            if (_signedBySelf && _receiverNameController.text.trim().isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'กรุณาระบุชื่อผู้เซ็นรับแทน (เช่น เจ้าของบ้าน, ยาม, เพื่อนบ้าน)',
                        style: TextStyle(color: Colors.orange[700], fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignatureSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.edit, color: Colors.green[700]),
                    const SizedBox(width: 8),
                    const Text('✍️ ลายเซ็นผู้รับ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                if (_signatureController.isNotEmpty)
                  TextButton.icon(
                    onPressed: _signatureController.clear,
                    icon: const Icon(Icons.refresh, size: 20),
                    label: const Text('ล้าง'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('🚫 ไม่เจอลูกค้า - เซ็นรับแทน'),
              value: _signedBySelf,
              onChanged: (value) {
                setState(() {
                  _signedBySelf = value;
                  // ✅ ไม่ใส่ค่า default - ให้ผู้ใช้กรอกเอง
                  _receiverNameController.clear();
                });
              },
            ),
            const SizedBox(height: 12),
            Container(
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[400]!),
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey[100],
              ),
              child: Signature(controller: _signatureController, backgroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    final hasPhoto = _deliveryPhoto != null;
    final hasSignature = _signatureController.isNotEmpty;
    final hasReceiverName = _receiverNameController.text.trim().isNotEmpty;
    final isReadyToSubmit = hasPhoto && hasSignature && hasReceiverName;
    
    return Column(
      children: [
        if (isReadyToSubmit) ...[
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _completeDelivery,
              icon: _isSubmitting
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.check_circle, size: 28),
              label: Text(_isSubmitting ? 'กำลังบันทึก...' : '✅ ยืนยันส่งของเสร็จสิ้น', style: const TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[600],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange[300]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange[700]),
                    const SizedBox(width: 12),
                    const Expanded(child: Text('กรุณาตรวจสอบให้ครบ:', style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                ),
                const SizedBox(height: 8),
                _buildChecklistItem('📸 ถ่ายรูปการส่งของ', hasPhoto),
                _buildChecklistItem('✍️ ลายเซ็น', hasSignature),
                _buildChecklistItem('👤 ชื่อผู้รับ', hasReceiverName),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildChecklistItem(String label, bool isComplete) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(isComplete ? Icons.check_circle : Icons.radio_button_unchecked, 
            color: isComplete ? Colors.green : Colors.grey[400], size: 20),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(
            color: isComplete ? Colors.black : Colors.grey[600],
            decoration: isComplete ? TextDecoration.lineThrough : null,
          )),
        ],
      ),
    );
  }

  Future<void> _pickDeliveryPhoto(ImageSource source) async {
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
      
      // ✅ FIX CRITICAL: ลบรูปเก่าก่อนถ่ายใหม่ (ป้องกัน memory leak)
      if (_deliveryPhoto != null) {
        try {
          print('🗑️ [DeliveryScreen] Deleting old photo to free memory...');
          final oldFile = _deliveryPhoto!;
          _deliveryPhoto = null; // Clear reference first
          
          if (await oldFile.exists()) {
            await oldFile.delete();
            print('✅ [DeliveryScreen] Old photo deleted successfully');
          }
        } catch (e) {
          print('⚠️ [DeliveryScreen] Could not delete old photo: $e');
        }
      }
      
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
            _deliveryPhoto = imageFile;
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
      _showError('กรุณากรอกชื่อผู้รับ'); 
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
        signaturePath: signatureFile.path,
        receiverName: _receiverNameController.text.trim(),
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
              content: Text('✅ บันทึกการส่งสินค้าสำเร็จ!'),
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
}