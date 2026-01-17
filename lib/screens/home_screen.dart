import 'dart:async';
import 'package:flutter/material.dart';
import '../models/driver.dart';
import '../services/odoo_service.dart';
import '../widgets/bottom_nav_bar.dart';
import 'login_screen.dart';
import 'my_jobs_screen.dart';
import 'delivery_history_screen.dart';
import 'income_screen.dart';
import 'vehicle_inspection_screen.dart';
// import 'settings_screen.dart'; // ❌ ไม่ใช้แล้ว ใช้การตั้งค่าจาก Odoo18

class HomeScreen extends StatefulWidget {
  final Driver driver;

  const HomeScreen({super.key, required this.driver});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _odooService = OdooService();
  int _pendingJobsCount = 0;
  double _currentMonthIncome = 0.0;
  bool _isLoading = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadPendingJobsCount();
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
        _loadPendingJobsCount();
      }
    });
  }

  Future<void> _loadPendingJobsCount() async {
    if (_isLoading) return;
    
    setState(() => _isLoading = true);
    
    try {
      print('🔄 Loading bookings for driver: ${widget.driver.id}');
      final bookings = await _odooService.getDriverBookings(widget.driver.id);
      print('✅ Found ${bookings.length} bookings');
      
      // 💰 ดึงรายได้เดือนนี้
      final income = await _odooService.getCurrentMonthIncome(widget.driver.id);
      
      if (mounted) {
        setState(() {
          _pendingJobsCount = bookings.length;
          _currentMonthIncome = income;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error loading jobs count: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/192x192.png',
              height: 32,
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'หน้าหลัก',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                Text(
                  widget.driver.name,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2196F3),
        elevation: 1,
        shadowColor: Colors.black.withOpacity(0.1),
        actions: [
          // ปุ่ม Refresh
          IconButton(
            icon: _isLoading 
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadPendingJobsCount,
          ),
          // ปุ่ม Settings - ❌ ไม่ใช้แล้ว ใช้การตั้งค่าจาก Odoo18
          // IconButton(
          //   icon: const Icon(Icons.settings),
          //   onPressed: () {
          //     Navigator.push(
          //       context,
          //       MaterialPageRoute(
          //         builder: (context) => const SettingsScreen(),
          //       ),
          //     );
          //   },
          // ),
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () => _showDriverInfo(context),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _showLogoutDialog(context),
          ),
        ],
      ),
      body: Container(
        color: Colors.white,
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ✅ เช็ค Active Status
                  if (!widget.driver.active)
                    _buildInactiveWarning()
                  else
                    Column(
                      children: [
                        _buildJobsCard(),
                        const SizedBox(height: 12),
                        _buildIncomeCard(),
                      ],
                    ),
                  
                  const SizedBox(height: 12),
                  
                  // 🚗 ปุ่มรายการตรวจสอบสภาพรถ
                  if (widget.driver.active)
                    _buildVehicleInspectionButton(),
                  
                  const SizedBox(height: 12),
                  
                  // 📜 ปุ่มประวัติการจัดส่ง
                  if (widget.driver.active)
                    _buildHistoryButton(),
                  
                  const SizedBox(height: 16),
                  
                  // แสดงข้อมูลคนขับ
                  _buildDriverInfoCard(),
                ],
              ),
            ),
          ),
        ),
      ),
      // ✅ Bottom Navigation Bar
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: 0,
        driver: widget.driver,
      ),
    );
  }

  // ⚠️ แสดงเมื่อ Driver ไม่ Active
  Widget _buildInactiveWarning() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 64,
              color: Colors.red.shade700,
            ),
            const SizedBox(height: 16),
            Text(
              'บัญชีของคุณถูกระงับ',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'กรุณาติดต่อผู้ดูแลระบบ',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.red.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 📋 Card งานของฉัน
  Widget _buildJobsCard() {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: InkWell(
        onTap: widget.driver.active ? () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MyJobsScreen(driver: widget.driver),
            ),
          );
          _loadPendingJobsCount();
        } : () {
          _showInactiveDialog();
        },
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFFFF9800).withOpacity(0.8),
                    const Color(0xFFFF9800),
                  ],
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.assignment,
                    size: 48,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'งานของฉัน',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _pendingJobsCount > 0 
                              ? '$_pendingJobsCount คิวที่ต้องส่ง'
                              : 'ไม่มีงานรอดำเนินการ',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // 🔴 Badge แจ้งเตือน
            if (_pendingJobsCount > 0)
              Positioned(
                top: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    _pendingJobsCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // 🚗 ปุ่มรายการตรวจสอบสภาพรถ
  Widget _buildVehicleInspectionButton() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VehicleInspectionScreen(driver: widget.driver),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.teal.shade400,
                Colors.teal.shade600,
              ],
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.car_repair,
                size: 32,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              const Text(
                'รายการตรวจสอบสภาพรถ',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 📜 ปุ่มประวัติการจัดส่ง
  Widget _buildHistoryButton() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DeliveryHistoryScreen(driver: widget.driver),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.blue.shade400,
                Colors.blue.shade600,
              ],
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.history,
                size: 32,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              const Text(
                'ประวัติการจัดส่ง',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 👤 Card ข้อมูลคนขับ
  Widget _buildDriverInfoCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.blue.shade100,
                  child: const Icon(
                    Icons.person,
                    size: 35,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.driver.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            widget.driver.active 
                                ? Icons.check_circle 
                                : Icons.cancel,
                            size: 16,
                            color: widget.driver.active 
                                ? Colors.green 
                                : Colors.red,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            widget.driver.active ? 'พร้อมใช้งาน' : 'ระงับการใช้',
                            style: TextStyle(
                              fontSize: 14,
                              color: widget.driver.active 
                                  ? Colors.green.shade700 
                                  : Colors.red.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow(Icons.phone, widget.driver.phone),
            if (widget.driver.email != null)
              _buildInfoRow(Icons.email, widget.driver.email!),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: Colors.grey.shade800,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDriverInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(
          widget.driver.name,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
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

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getEmploymentStatusText(String status) {
    switch (status) {
      case 'employed':
        return 'พนักงานประจำ';
      case 'partner':
        return 'คนขับรถร่วม';
      case 'inactive':
        return 'ไม่ทำงาน';
      default:
        return status;
    }
  }

  String _getLicenseTypeText(String type) {
    switch (type) {
      case 'car':
        return 'รถยนต์';
      case 'truck':
        return 'รถบรรทุก';
      case 'trailer':
        return 'รถพ่วง';
      default:
        return type;
    }
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('ออกจากระบบ'),
        content: const Text('คุณต้องการออกจากระบบหรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (context) => const LoginScreen(),
                ),
                (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('ออกจากระบบ'),
          ),
        ],
      ),
    );
  }

  void _showInactiveDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        icon: Icon(
          Icons.block,
          size: 64,
          color: Colors.red.shade700,
        ),
        title: Text(
          'ไม่สามารถเข้าใช้งานได้',
          style: TextStyle(
            color: Colors.red.shade900,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'บัญชีของคุณถูกระงับการใช้งาน',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.red.shade700,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(
                'กรุณาติดต่อผู้ดูแลระบบเพื่อเปิดใช้งานบัญชี',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.red.shade900,
                  fontWeight: FontWeight.w500,
                ),
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

  // 💰 Card รายได้เดือนนี้
  Widget _buildIncomeCard() {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: InkWell(
        onTap: widget.driver.active ? () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => IncomeScreen(driver: widget.driver),
            ),
          );
        } : () {
          _showInactiveDialog();
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF4CAF50).withOpacity(0.8),
                const Color(0xFF4CAF50),
              ],
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Icon(
                Icons.attach_money,
                size: 32,
                color: Colors.white,
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'รายได้เดือนนี้',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_currentMonthIncome.toStringAsFixed(2)} บาท',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
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
}
