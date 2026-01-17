import 'dart:async';
import 'package:flutter/material.dart';
import '../models/driver.dart';
import '../models/booking.dart';
import '../services/odoo_service.dart';
import '../services/tracking_service.dart';
import '../services/background_location_service.dart';
import '../widgets/bottom_nav_bar.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'start_job_screen_new.dart';
import 'delivery_completion_screen.dart';
import 'navigation_map_screen.dart';

class MyJobsScreen extends StatefulWidget {
  final Driver driver;

  const MyJobsScreen({super.key, required this.driver});

  @override
  State<MyJobsScreen> createState() => _MyJobsScreenState();
}

class _MyJobsScreenState extends State<MyJobsScreen> {
  final _odooService = OdooService();
  final _trackingService = TrackingService();
  List<Booking> _bookings = [];
  Booking? _activeJob; // งานที่กำลังทำอยู่
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _refreshTimer;
  final Map<int, DateTime> _bookingStartTimes = {}; // ✅ เก็บเวลาออกเดินทางจริง

  @override
  void initState() {
    super.initState();
    _loadBookings();
    _checkActiveJob();
    // ✅ Auto-refresh ทุก 30 วินาที
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _loadBookings(showLoading: false);
      }
    });
  }

  // ✅ ดึงเวลาออกเดินทางจริง จาก Map
  DateTime? _getStoredStartTime(int bookingId) {
    return _bookingStartTimes[bookingId];
  }

  Future<void> _loadBookings({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    
    try {
      print('🔄 [MyJobs] Loading bookings for driver: ${widget.driver.id}');
      print('📋 [MyJobs] Driver name: ${widget.driver.name}');
      print('✅ [MyJobs] Driver active: ${widget.driver.active}');
      
      final bookings = await _odooService.getDriverBookings(widget.driver.id);
      
      print('✅ [MyJobs] Received ${bookings.length} bookings from API');
      for (var i = 0; i < bookings.length; i++) {
        print('   $i: ${bookings[i].name} - ${bookings[i].state}');
        print('      📍 Destination: ${bookings[i].destination}');
        print('      🗺️  Coordinates: lat=${bookings[i].destinationLatitude}, lng=${bookings[i].destinationLongitude}');
      }
      
      // ✅ เช็คว่ามีงานที่กำลังทำอยู่หรือไม่
      await _checkActiveJob();
      
      setState(() {
        _bookings = bookings;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e, stackTrace) {
      print('❌ [MyJobs] Error loading bookings: $e');
      print('📚 [MyJobs] Stack trace: $stackTrace');
      
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ✅ ฟังก์ชันเช็คว่าเป็นวันเดียวกันหรือไม่
  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
           date1.month == date2.month &&
           date1.day == date2.day;
  }

  // ✅ ฟังก์ชันเปิด Google Maps Navigation
  // นำทางตรงจากตำแหน่งปัจจุบัน → ปลายทาง (destination)
  // ใช้พิกัด lat/lng สำหรับความแม่นยำ
  Future<void> _openGoogleMaps({
    double? lat,
    double? lng,
    String? address,
  }) async {
    print('🗺️ _openGoogleMaps called with:');
    print('   lat: $lat');
    print('   lng: $lng');
    print('   address: $address');
    
    String destination;
    
    // ตรวจสอบว่ามีข้อมูลหรือไม่
    if (lat == null || lng == null || lat == 0.0 || lng == 0.0) {
      print('⚠️  Invalid or missing coordinates, will try to use address');
      if (address == null || address.isEmpty) {
        print('❌ No valid location data available');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ ไม่พบข้อมูลตำแหน่งปลายทาง'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      // ใช้ address แทน
      destination = Uri.encodeComponent(address);
      print('📍 Using address: $address');
    } else {
      destination = '$lat,$lng';
      print('📍 Using coordinates: $lat, $lng');
    }
    
    // 🎯 ลำดับความสำคัญ: ลอง URL schemes ต่างๆ จนกว่าจะสำเร็จ
    
    // 1️⃣ comgooglemaps:// - นำทางตรงไปปลายทาง
    try {
      final comGoogleUrl = 'comgooglemaps://?daddr=$destination&directionsmode=driving';
      final uri = Uri.parse(comGoogleUrl);
      
      print('🔍 Trying: comgooglemaps://');
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      print('✅ SUCCESS: comgooglemaps://');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🗺️ เปิด Google Maps\n📍 นำทางไปปลายทาง'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    } catch (e) {
      print('❌ FAILED: comgooglemaps:// - $e');
    }
    
    // 2️⃣ google.navigation: - นำทางไปปลายทางโดยตรง
    try {
      final navUrl = 'google.navigation:q=$destination&mode=d';
      final uri = Uri.parse(navUrl);
      
      print('🔍 Trying: google.navigation:');
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      print('✅ SUCCESS: google.navigation:');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🗺️ เปิด Google Maps นำทางไปปลายทาง'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    } catch (e) {
      print('❌ FAILED: google.navigation: - $e');
    }
    
    // 3️⃣ Web URL - นำทางตรงไปปลายทาง (Fallback)
    try {
      final webUrl = 'https://www.google.com/maps/dir/?api=1&destination=$destination&travelmode=driving';
      final uri = Uri.parse(webUrl);
      
      print('🔍 Trying: web URL');
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      print('✅ SUCCESS: web URL');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🌐 เปิด Google Maps ผ่าน Browser\nกดปุ่ม "Start" เพื่อเริ่มนำทาง'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    } catch (e) {
      print('❌ FAILED: web URL - $e');
    }
    
    // 4️⃣ ถ้าทุกวิธีล้มเหลว
    print('❌ ALL METHODS FAILED');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ ไม่สามารถเปิด Google Maps ได้\n'
              'กรุณาติดตั้ง Google Maps\n'
              'หรือนำทางเอง:\n'
              '• ปลายทาง: ${lat != null && lng != null ? "$lat, $lng" : address}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'งานของฉัน',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                if (_bookings.isEmpty && !_isLoading)
                  Text(
                    'ไม่มีงานที่รอดำเนินการ',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green.shade600,
                      fontWeight: FontWeight.normal,
                    ),
                  )
                else if (_bookings.isNotEmpty)
                  Text(
                    '${_bookings.length} คิวที่ต้องส่ง',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
              ],
            ),
            const Spacer(),
            // 🔴 Badge แจ้งเตือนจำนวนคิว
            if (_bookings.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  _bookings.length.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFFFF9800),
        elevation: 1,
        shadowColor: Colors.black.withOpacity(0.1),
        actions: [
          IconButton(
            icon: _isLoading 
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadBookings,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
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
                        onPressed: _loadBookings,
                        icon: const Icon(Icons.refresh),
                        label: const Text('ลองอีกครั้ง'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF9800),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                )
              : _bookings.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.assignment_turned_in,
                            size: 100,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'ไม่มีงานที่รอดำเนินการ',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.green.shade200,
                                width: 2,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  color: Colors.green.shade600,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'คุณไม่มีคิวงานในขณะนี้',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.green.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'ระบบจะแจ้งเตือนอัตโนมัติเมื่อมีงานใหม่',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.autorenew,
                                size: 16,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'กำลังอัพเดท...',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadBookings,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _bookings.length,
                        itemBuilder: (context, index) {
                          final booking = _bookings[index];
                          return _buildBookingCard(booking);
                        },
                      ),
                    ),
      // ✅ Bottom Navigation Bar
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: 1,
        driver: widget.driver,
      ),
    );
  }

  Widget _buildBookingCard(Booking booking) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final now = DateTime.now();
    
    // ✅ เช็คว่าวันเวลาที่วางแผน <= เวลาปัจจุบัน (แสดงงานที่ถึงเวลาหรือล่าช้า)
    final bool canStartNow = booking.plannedStartDate == null ||
        booking.plannedStartDate!.isBefore(now) ||
        booking.plannedStartDate!.isAtSameMomentAs(now);

    // ✅ ดึงเวลาออกเดินทางจริง จาก SharedPreferences (ถ้ามี)
    DateTime? actualStartTime;
    if (booking.state == 'in_progress') {
      actualStartTime = _getStoredStartTime(booking.id);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _showBookingDetail(booking),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      booking.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: booking.state == 'in_progress'
                          ? Colors.blue.shade50
                          : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: booking.state == 'in_progress'
                            ? Colors.blue.shade200
                            : Colors.green.shade200,
                      ),
                    ),
                    child: Text(
                      booking.getStateText(),
                      style: TextStyle(
                        color: booking.state == 'in_progress'
                            ? Colors.blue.shade700
                            : Colors.green.shade700,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (booking.partnerName != null)
                _buildInfoRow(
                  Icons.business,
                  'ลูกค้า',
                  booking.partnerName!,
                ),
              if (booking.pickupLocation != null)
                _buildInfoRow(
                  Icons.location_on,
                  'ต้นทาง',
                  booking.pickupLocation!,
                ),
              if (booking.destination != null)
                _buildInfoRow(
                  Icons.flag,
                  'ปลายทาง',
                  booking.destination!,
                ),
              if (booking.totalWeightOrder != null && booking.totalWeightOrder! > 0)
                _buildInfoRow(
                  Icons.scale,
                  'น้ำหนักรวม',
                  '${booking.totalWeightOrder!.toStringAsFixed(2)} กก.',
                  color: Colors.blue.shade700,
                ),
              if (booking.plannedStartDate != null)
                _buildInfoRow(
                  Icons.schedule,
                  'วางแผนออกเดินทาง',
                  dateFormat.format(booking.plannedStartDate!),
                  color: canStartNow ? Colors.green : Colors.orange,
                ),
              // ✅ แสดง เวลาออกเดินทางจริง (ดึงจาก plannedStartDateT)
              if (booking.plannedStartDateT != null)
                _buildInfoRow(
                  Icons.flight_takeoff,
                  'เวลาออกจริง',
                  dateFormat.format(booking.plannedStartDateT!),
                  color: Colors.green.shade700,
                ),
              // ✅ แสดง เวลาส่งถึงจริง (ดึงจาก plannedEndDateT)
              if (booking.plannedEndDateT != null)
                _buildInfoRow(
                  Icons.check_circle,
                  'เวลาส่งถึงจริง',
                  dateFormat.format(booking.plannedEndDateT!),
                  color: Colors.blue.shade700,
                ),
              // ส่วนที่ 3: แสดงค่าขนส่ง
              if (booking.shippingCost != null && booking.shippingCost! > 0)
                _buildInfoRow(
                  Icons.local_shipping,
                  'ค่าขนส่ง',
                  '${booking.shippingCost!.toStringAsFixed(2)} บาท',
                  color: Colors.purple.shade700,
                ),
              // ส่วนที่ 4: แสดงค่าเที่ยว
              if (booking.travelExpenses != null && booking.travelExpenses! > 0)
                _buildInfoRow(
                  Icons.local_atm,
                  'ค่าเที่ยว',
                  '${booking.travelExpenses!.toStringAsFixed(2)} บาท',
                  color: Colors.green.shade700,
                ),
              // ✅ เพิ่มค่าเบี้ยเลี้ยง
              if (booking.dailyAllowance != null && booking.dailyAllowance! > 0)
                _buildInfoRow(
                  Icons.restaurant,
                  'ค่าเบี้ยเลี้ยง',
                  '${booking.dailyAllowance!.toStringAsFixed(2)} บาท',
                  color: Colors.orange.shade700,
                ),
              // ✅ เพิ่ม: เวลาโดยประมาณ
              if (booking.estimatedTime != null && booking.estimatedTime!.isNotEmpty)
                _buildInfoRow(
                  Icons.hourglass_bottom,
                  'เวลาโดยประมาณ',
                  booking.estimatedTime!,
                  color: Colors.amber.shade700,
                ),
              const SizedBox(height: 12),
              
              // แสดงสถานะการติดตามตำแหน่ง (เฉพาะงานที่กำลังทำ)
              _buildTrackingStatus(booking),
              
              // ✅ แสดงปุ่มตามสถานะ
              // หมายเหตุ: ตอนนี้จะแสดงเฉพาะงาน 'in_progress' เท่านั้น (ไม่แสดง 'confirmed')
              if (booking.state == 'confirmed')
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ✅ แสดงข้อความเตือนถ้ามีงานอื่นกำลังทำอยู่
                    if (_activeJob != null && _activeJob!.id != booking.id) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.orange.shade300,
                            width: 2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.work_history,
                              color: Colors.orange.shade700,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '⚠️ มีงานกำลังทำอยู่',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Colors.orange.shade900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'กรุณาทำ "${_activeJob!.name}" ให้เสร็จก่อน',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.orange.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    // ปุ่มเริ่มงาน
                    ElevatedButton.icon(
                      onPressed: (_activeJob != null && _activeJob!.id != booking.id)
                          ? null  // Disable ถ้ามีงานอื่นกำลังทำ
                          : (canStartNow
                              ? () => _handleStartJob(booking)
                              : () => _showNotTodayDialog(booking)),
                      icon: Icon(
                        (_activeJob != null && _activeJob!.id != booking.id)
                            ? Icons.lock
                            : Icons.play_arrow,
                      ),
                      label: Text(
                        (_activeJob != null && _activeJob!.id != booking.id)
                            ? 'รอจบงานก่อนหน้า'
                            : (canStartNow ? 'เริ่มงาน' : 'ดูรายละเอียด'),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: (_activeJob != null && _activeJob!.id != booking.id)
                            ? Colors.grey.shade300
                            : (canStartNow 
                                ? const Color(0xFFFF9800) 
                                : Colors.grey),
                        foregroundColor: (_activeJob != null && _activeJob!.id != booking.id)
                            ? Colors.grey.shade600
                            : Colors.white,
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                )
              else if (booking.state == 'in_progress')
                // ✅ ปุ่มนำทางเมื่ออยู่ในสถานะ in_progress
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          // เปิด Google Maps นำทางโดยตรงไปปลายทาง
                          // ใช้พิกัดถ้ามี ไม่เช่นนั้นใช้ที่อยู่
                          _openGoogleMaps(
                            lat: booking.destinationLatitude,
                            lng: booking.destinationLongitude,
                            address: booking.destination,
                          );
                        },
                        icon: const Icon(Icons.navigation),
                        label: const Text('นำทาง'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _handleCompleteJob(booking),
                        icon: const Icon(Icons.check_circle),
                        label: const Text('เสร็จสิ้น'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value,
      {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color ?? Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontFamily: 'Kanit',  // ✅ เพิ่ม Kanit font
                  color: Colors.grey.shade800,
                  fontSize: 14,
                ),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(
                      fontFamily: 'Kanit',  // ✅ เพิ่ม Kanit font
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextSpan(
                    text: value,
                    style: TextStyle(
                      fontFamily: 'Kanit',  // ✅ เพิ่ม Kanit font
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

  // ✅ แสดง Dialog เมื่องานยังไม่ถึงวันที่กำหนด (อนาคต)
  void _showNotTodayDialog(Booking booking) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final now = DateTime.now();
    final today = DateFormat('dd/MM/yyyy').format(now);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        icon: Icon(
          Icons.schedule,
          size: 48,
          color: Colors.blue.shade700,
        ),
        title: const Text(
          'งานนี้ยังไม่ถึงกำหนด',
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'งานนี้วางแผนออกเดินทางในวันที่:',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Text(
                booking.plannedStartDate != null
                    ? dateFormat.format(booking.plannedStartDate!)
                    : 'ไม่ระบุ',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade900,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.today, size: 20, color: Colors.grey.shade700),
                  const SizedBox(width: 8),
                  Text(
                    'วันนี้: $today',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'งานนี้สามารถเริ่มได้เมื่อถึงวันที่กำหนด',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ตกลง'),
          ),
        ],
      ),
    );
  }

  void _showBookingDetail(Booking booking) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(booking.name),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('สถานะ', booking.getStateText()),
              if (booking.partnerName != null)
                _buildDetailRow('ลูกค้า', booking.partnerName!),
              if (booking.deliveryEmployeeName != null)
                _buildDetailRow(
                    'พนักงานส่งของ', booking.deliveryEmployeeName!),
              if (booking.vehicleName != null)
                _buildDetailRow('รถ', booking.vehicleName!),
              if (booking.pickupLocation != null)
                _buildDetailRow('ต้นทาง', booking.pickupLocation!),
              if (booking.destination != null)
                _buildDetailRow('ปลายทาง', booking.destination!),
              if (booking.totalWeightOrder != null && booking.totalWeightOrder! > 0)
                _buildDetailRow('น้ำหนักรวม', '${booking.totalWeightOrder!.toStringAsFixed(2)} กก.'),
              if (booking.distanceKm != null)
                _buildDetailRow(
                    'ระยะทาง', '${booking.distanceKm!.toStringAsFixed(2)} กม.'),
              if (booking.shippingCost != null)
                _buildDetailRow('ค่าขนส่ง',
                    '${booking.shippingCost!.toStringAsFixed(2)} บาท'),
              if (booking.travelExpenses != null && booking.travelExpenses! > 0)
                _buildDetailRow('ค่าเที่ยว',
                    '${booking.travelExpenses!.toStringAsFixed(2)} บาท'),
              // ✅ เพิ่มค่าเบี้ยเลี้ยง
              if (booking.dailyAllowance != null && booking.dailyAllowance! > 0)
                _buildDetailRow('ค่าเบี้ยเลี้ยง',
                    '${booking.dailyAllowance!.toStringAsFixed(2)} บาท'),
              // ✅ เพิ่ม: เวลาโดยประมาณ
              if (booking.estimatedTime != null && booking.estimatedTime!.isNotEmpty)
                _buildDetailRow('เวลาโดยประมาณ', booking.estimatedTime!),
              if (booking.plannedStartDate != null)
                _buildDetailRow('วางแผนออกเดินทาง',
                    dateFormat.format(booking.plannedStartDate!)),
              // ✅ แสดงเวลาออกเดินทางจริง (เฉพาะเมื่อ state = 'in_progress' ให้แสดงเวลาปัจจุบัน)
              if (booking.state == 'in_progress')
                _buildDetailRow('ออกเดินทางจริง',
                    dateFormat.format(DateTime.now().add(const Duration(hours: 7)))),
              if (booking.plannedEndDate != null)
                _buildDetailRow('วางแผนถึงปลายทาง',
                    dateFormat.format(booking.plannedEndDate!)),
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

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }

  void _startJob(Booking booking) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('ยืนยันเริ่มงาน'),
        content: Text('คุณต้องการเริ่มงาน ${booking.name} หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF9800),
              foregroundColor: Colors.white,
            ),
            child: const Text('เริ่มงาน'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // แสดง loading
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );
      }

      final success = await _odooService.startBooking(booking.id);
      
      // ปิด loading
      if (mounted) {
        Navigator.pop(context);
      }

      if (mounted) {
        if (success) {
          // ✅ บันทึกเวลาออกเดินทางจริง (UTC+7)
          final startTime = DateTime.now().add(const Duration(hours: 7));
          _bookingStartTimes[booking.id] = startTime;
          print('✅ [MyJobs] Recorded start time for booking ${booking.id}: $startTime');
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ เริ่มงานสำเร็จ'),
              backgroundColor: Colors.green,
            ),
          );
          _loadBookings();
          
          // ✅ เปิด Google Maps ทันทีหลังเริ่มงาน
          await Future.delayed(const Duration(seconds: 1));
          _openGoogleMaps(
            lat: booking.destinationLatitude,
            lng: booking.destinationLongitude,
            address: booking.destination,
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ เริ่มงานไม่สำเร็จ'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // ✅ ฟังก์ชันเสร็จสิ้นงาน
  void _completeJob(Booking booking) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('ยืนยันเสร็จสิ้นงาน'),
        content: Text('คุณต้องการยืนยันว่างาน ${booking.name} เสร็จสิ้นหรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('เสร็จสิ้น'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // แสดง loading
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );
      }

      final success = await _odooService.completeBooking(booking.id);
      
      // ปิด loading
      if (mounted) {
        Navigator.pop(context);
      }

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ เสร็จสิ้นงานสำเร็จ'),
              backgroundColor: Colors.green,
            ),
          );
          _loadBookings();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ เสร็จสิ้นงานไม่สำเร็จ'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // เช็คว่ามีงานที่กำลังทำอยู่หรือไม่
  Future<void> _checkActiveJob() async {
    try {
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('🔍 [MyJobs] Checking for active job...');
      
      final activeJob = await _odooService.getActiveJob(widget.driver.id);
      
      setState(() {
        _activeJob = activeJob;
      });
      
      if (activeJob != null) {
        print('✅ [MyJobs] Active job found: ${activeJob.name} (ID: ${activeJob.id})');
        print('   📊 State: ${activeJob.state}');
        print('   📍 Destination: ${activeJob.destination}');
        
        // ✅ ถ้ามี active job และยังไม่ได้ tracking ให้เริ่ม tracking อัตโนมัติ
        if (!_trackingService.isTracking) {
          print('🚀 [MyJobs] Auto-starting tracking for active job...');
          
          // ตรวจสอบ permission ก่อน
          final hasPermission = await _requestLocationPermission();
          
          if (hasPermission) {
            // ✅ เซต Booking ID ให้ Background Service ก่อน
            await BackgroundLocationService.setActiveBookingId(activeJob.id);
            print('✅ [MyJobs] Booking ID set: ${activeJob.id}');
            
            // เริ่ม tracking แบบ force start
            final success = await _trackingService.startTracking(
              activeJob,
              forceStart: true, // ✅ บังคับเปิดเสมอ
            );
            
            if (success) {
              print('✅ [MyJobs] Tracking auto-started successfully!');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ เริ่มติดตามตำแหน่งอัตโนมัติสำเร็จ'),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            } else {
              print('⚠️ [MyJobs] Failed to auto-start tracking');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('⚠️ ไม่สามารถเริ่มติดตามตำแหน่งได้'),
                    backgroundColor: Colors.orange,
                    duration: Duration(seconds: 3),
                  ),
                );
              }
            }
          } else {
            print('❌ [MyJobs] Location permission not granted');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('⚠️ ต้องการสิทธิ์ GPS เพื่อติดตามตำแหน่ง'),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 3),
                  action: SnackBarAction(
                    label: 'ตั้งค่า',
                    textColor: Colors.white,
                    onPressed: () {
                      Geolocator.openAppSettings();
                    },
                  ),
                ),
              );
            }
          }
        } else {
          print('✅ [MyJobs] Tracking already running');
        }
      } else {
        print('ℹ️  [MyJobs] No active job found');
        
        // ถ้าไม่มี active job แล้ว tracking ยังเปิดอยู่ ให้ปิด
        if (_trackingService.isTracking) {
          print('🛑 [MyJobs] Stopping tracking (no active job)');
          _trackingService.stopTracking();
        }
      }
      
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    } catch (e, stackTrace) {
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('❌ [MyJobs] Error checking active job: $e');
      print('📚 Stack trace: $stackTrace');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    }
  }

  // ขออนุญาต Location Permission
  Future<bool> _requestLocationPermission() async {
    try {
      print('🔐 [MyJobs] Checking location permission...');
      
      // ตรวจสอบว่า Location Service เปิดอยู่หรือไม่
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('❌ [MyJobs] Location services are disabled');
        return false;
      }

      // ตรวจสอบสิทธิ์
      LocationPermission permission = await Geolocator.checkPermission();
      
      if (permission == LocationPermission.denied) {
        print('📍 [MyJobs] Permission denied, requesting...');
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('❌ [MyJobs] Location permissions are denied');
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('❌ [MyJobs] Location permissions are permanently denied');
        return false;
      }

      print('✅ [MyJobs] Location permission granted: $permission');
      return true;
    } catch (e) {
      print('❌ [MyJobs] Error checking permission: $e');
      return false;
    }
  }

  // เริ่มงาน
  Future<void> _handleStartJob(Booking booking) async {
    // เช็คว่ามีงานกำลังทำอยู่หรือไม่
    if (_activeJob != null && _activeJob!.id != booking.id) {
      _showErrorDialog(
        'ไม่สามารถเริ่มงานได้',
        'คุณมีงาน "${_activeJob!.name}" ที่กำลังทำอยู่\nกรุณาจบงานนั้นก่อน',
      );
      return;
    }

    // ✅ ไม่ต้องเช็ควันที่อีก เพราะ UI กรองไว้แล้ว (canStartToday)
    // งานที่แสดงปุ่มได้คือ: planned_start_date <= today หรือ null
    
    // ไปหน้าถ่ายรูปก่อนเริ่มงาน
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StartJobScreen(
          booking: booking,
          driver: widget.driver,
        ),
      ),
    );

    if (result == true) {
      // รีเฟรชข้อมูล
      _loadBookings();
      _checkActiveJob();
    }
  }

  // จบงาน
  Future<void> _handleCompleteJob(Booking booking) async {
    // ไปหน้าเซ็นรับของ
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DeliveryCompletionScreen(booking: booking, driver: widget.driver),
      ),
    );

    if (result == true) {
      // รีเฟรชข้อมูล
      _loadBookings();
      _checkActiveJob();
    }
  }

  // ติดตามรถ
  void _handleTrackVehicle(Booking booking) {
    // ต้องสร้าง ActiveBooking object สำหรับ tracking screen
    // (ใช้งานเดิม ไม่ต้องแก้)
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning, color: Colors.orange),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ตกลง'),
          ),
        ],
      ),
    );
  }

  // แสดงสถานะการติดตามตำแหน่ง
  Widget _buildTrackingStatus(Booking booking) {
    final isActiveJob = _activeJob != null && _activeJob!.id == booking.id;
    final isTracking = _trackingService.isTracking;
    
    if (!isActiveJob || booking.state != 'in_progress') {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isTracking ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isTracking ? Colors.green.shade200 : Colors.orange.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isTracking ? Icons.gps_fixed : Icons.gps_off,
            color: isTracking ? Colors.green.shade700 : Colors.orange.shade700,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isTracking ? '📍 กำลังติดตามตำแหน่ง' : '⚠️ ไม่ได้ติดตามตำแหน่ง',
                  style: TextStyle(
                    fontFamily: 'Kanit',  // ✅ เพิ่ม Kanit font
                    fontWeight: FontWeight.bold,
                    color: isTracking ? Colors.green.shade700 : Colors.orange.shade700,
                    fontSize: 13,
                  ),
                ),
                if (isTracking) ...[
                  const SizedBox(height: 4),
                  Text(
                    _trackingService.getTrackingStatus(),
                    style: TextStyle(
                      fontFamily: 'Kanit',  // ✅ เพิ่ม Kanit font
                      color: Colors.grey.shade600,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!isTracking && _trackingService.settings != null)
            TextButton(
              onPressed: () async {
                // แสดง loading
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('🔄 กำลังเริ่มติดตามตำแหน่ง...'),
                    duration: Duration(seconds: 1),
                  ),
                );
                
                // เริ่ม tracking แบบ force
                final started = await _trackingService.startTracking(
                  booking,
                  forceStart: true,  // ✅ บังคับเปิด
                );
                
                if (started && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ เริ่มติดตามตำแหน่งแล้ว'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  setState(() {});
                } else if (mounted) {
                  // แสดง dialog แนะนำ
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red[700]),
                          const SizedBox(width: 8),
                          const Text('ไม่สามารถเริ่ม Tracking ได้'),
                        ],
                      ),
                      content: const Text(
                        'กรุณาตรวจสอบ:\n\n'
                        '✓ เปิด GPS/Location Service\n'
                        '✓ อนุญาตสิทธิ์ Location ให้แอป\n'
                        '✓ ตรวจสอบสัญญาณ GPS\n'
                        '✓ ลองรีสตาร์ทแอป',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('ปิด'),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            Geolocator.openLocationSettings();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                          ),
                          child: const Text('เปิดการตั้งค่า GPS'),
                        ),
                      ],
                    ),
                  );
                }
              },
              child: const Text('เริ่ม', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
