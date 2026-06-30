import 'dart:async';
import 'package:flutter/material.dart';
import '../models/driver.dart';
import '../services/odoo_service.dart';
import '../services/update_service.dart';
import '../services/notification_service.dart';
import '../widgets/bottom_nav_bar.dart';
import 'login_screen.dart';
import 'my_jobs_screen.dart';
import 'delivery_history_screen.dart';
import 'income_screen.dart';
import 'vehicle_inspection_screen.dart';

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
  // ใช้เทียบจำนวนงานรอบก่อน เพื่อตรวจจับ "งานใหม่" (-1 = ยังไม่มี baseline)
  int _previousJobsCount = -1;

  // 🎨 พาเลตสีหลัก
  static const Color _primary = Color(0xFF2D6CDF);
  static const Color _primaryDark = Color(0xFF1E47B8);

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _loadPendingJobsCount();
    _startAutoRefresh();
    // 🔔 เช็คอัปเดตเวอร์ชันจาก Google Play หลังเฟรมแรกพร้อม
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UpdateService.checkForUpdate(context);
    });
  }

  Future<void> _initNotifications() async {
    await NotificationService.init();
    await NotificationService.requestPermission();
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
      final bookings = await _odooService.getDriverBookings(widget.driver.id);
      final income = await _odooService.getCurrentMonthIncome(widget.driver.id);
      final newCount = bookings.length;

      // 🔔 แจ้งเตือนงานใหม่: ยิงเมื่อจำนวนงานเพิ่มขึ้นจากรอบก่อน
      //    (ข้ามรอบแรกที่ยังไม่มี baseline และเฉพาะพนักงานที่ active)
      if (widget.driver.active &&
          _previousJobsCount >= 0 &&
          newCount > _previousJobsCount) {
        NotificationService.showNewJob(
          newCount - _previousJobsCount,
          newCount,
        );
      }
      _previousJobsCount = newCount;

      if (mounted) {
        setState(() {
          _pendingJobsCount = newCount;
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

  // 📅 ข้อความช่วงรอบจ่ายเงินปัจจุบัน เช่น "25 พ.ค. – 24 มิ.ย."
  String _currentCycleLabel() {
    final now = DateTime.now();
    DateTime start, end;
    if (now.day >= 25) {
      start = DateTime(now.year, now.month, 25);
      end = DateTime(now.year, now.month + 1, 24);
    } else {
      start = DateTime(now.year, now.month - 1, 25);
      end = DateTime(now.year, now.month, 24);
    }
    const m = [
      'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
      'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'
    ];
    return '${start.day} ${m[start.month - 1]} – ${end.day} ${m[end.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: RefreshIndicator(
        color: _primary,
        onRefresh: _loadPendingJobsCount,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              // ===== Header =====
              _buildHeader(),

              // ===== การ์ดรายได้ลอยทับ header (ใช้ Transform.translate
              //        เพื่อให้กดได้ทั้งใบ ไม่ติดปัญหา hit-test ของ Stack) =====
              Transform.translate(
                offset: const Offset(0, -54),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildIncomeHeroCard(),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          if (!widget.driver.active) ...[
                            _buildInactiveWarning(),
                            const SizedBox(height: 16),
                          ],

                          // ===== เมนูลัด =====
                          _buildSectionTitle('เมนูหลัก'),
                          const SizedBox(height: 12),
                          _buildQuickActionsGrid(),
                          const SizedBox(height: 24),
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
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: 0,
        driver: widget.driver,
      ),
    );
  }

  // ===================== Header =====================
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 70),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_primary, _primaryDark],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // แถวบน: โลโก้ + แอ็คชัน
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Image.asset('assets/images/192x192.png', height: 26),
                ),
                const SizedBox(width: 10),
                const Text(
                  'NPD Logistics',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                _headerIconButton(
                  icon: _isLoading ? null : Icons.refresh_rounded,
                  loading: _isLoading,
                  onTap: _isLoading ? null : _loadPendingJobsCount,
                ),
                _headerIconButton(
                  icon: Icons.person_outline_rounded,
                  onTap: () => _showDriverInfo(context),
                ),
                _headerIconButton(
                  icon: Icons.logout_rounded,
                  onTap: () => _showLogoutDialog(context),
                ),
              ],
            ),
            const SizedBox(height: 18),
            // แถวทักทาย
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: Colors.white.withOpacity(0.22),
                  child: const Icon(Icons.person, color: Colors.white, size: 30),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'สวัสดี 👋',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.driver.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusChip(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerIconButton({
    IconData? icon,
    bool loading = false,
    VoidCallback? onTap,
  }) {
    return IconButton(
      onPressed: onTap,
      icon: loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(Colors.white),
              ),
            )
          : Icon(icon, color: Colors.white),
    );
  }

  Widget _buildStatusChip() {
    final active = widget.driver.active;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? Icons.check_circle : Icons.cancel,
            color: active ? const Color(0xFF9CFF9C) : const Color(0xFFFFB3B3),
            size: 15,
          ),
          const SizedBox(width: 5),
          Text(
            active ? 'พร้อมใช้งาน' : 'ระงับ',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ===================== การ์ดรายได้ (Hero) =====================
  Widget _buildIncomeHeroCard() {
    return Material(
      elevation: 6,
      shadowColor: Colors.black.withOpacity(0.25),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: widget.driver.active
            ? _showCurrentCycleSheet
            : _showInactiveDialog,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2BB673), Color(0xFF179E5B)],
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.account_balance_wallet_rounded,
                    color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'รายได้รอบนี้',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_currentMonthIncome.toStringAsFixed(2)} บาท',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'รอบ ${_currentCycleLabel()}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: Colors.white.withOpacity(0.9)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1F2937),
        ),
      ),
    );
  }

  // 📅 แปลงวันที่ "YYYY-MM-DD" เป็นแบบไทยสั้น เช่น "24 มิ.ย."
  String _thaiShortDate(String ymd) {
    try {
      final d = DateTime.parse(ymd);
      const m = [
        'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
        'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'
      ];
      return '${d.day} ${m[d.month - 1]}';
    } catch (_) {
      return ymd;
    }
  }

  // 💸 Popup รายการงานในรอบจ่ายเงินปัจจุบัน
  void _showCurrentCycleSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // ตัวจับลาก
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  // หัวเรื่อง
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2BB673).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.account_balance_wallet_rounded,
                            color: Color(0xFF179E5B),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'รายได้รอบนี้',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'รอบ ${_currentCycleLabel()}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // เนื้อหา: โหลดรายการ
                  Expanded(
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      future: _odooService
                          .getCurrentCycleDeliveries(widget.driver.id),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final items = snapshot.data ?? [];
                        if (items.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.inbox_rounded,
                                    size: 56, color: Colors.grey.shade300),
                                const SizedBox(height: 12),
                                Text(
                                  'ยังไม่มีงานในรอบนี้',
                                  style:
                                      TextStyle(color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          );
                        }

                        double totalTravel = 0, totalAllowance = 0;
                        for (final it in items) {
                          totalTravel += it['travel_expenses'] as double;
                          totalAllowance += it['daily_allowance'] as double;
                        }
                        final total = totalTravel + totalAllowance;

                        return Column(
                          children: [
                            // แถบสรุปยอดรวม
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF2BB673),
                                    Color(0xFF179E5B)
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'รวม ${items.length} งาน',
                                        style: TextStyle(
                                          color:
                                              Colors.white.withOpacity(0.9),
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${total.toStringAsFixed(2)} บาท',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      _miniTotal('ค่าเที่ยว', totalTravel),
                                      const SizedBox(height: 4),
                                      _miniTotal(
                                          'ค่าเบี้ยเลี้ยง', totalAllowance),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // รายการงาน
                            Expanded(
                              child: ListView.separated(
                                controller: scrollController,
                                padding: const EdgeInsets.fromLTRB(
                                    16, 8, 16, 16),
                                itemCount: items.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) =>
                                    _buildCycleItem(items[index]),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  // ปุ่มดูทั้งหมด
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    IncomeScreen(driver: widget.driver),
                              ),
                            );
                          },
                          icon: const Icon(Icons.bar_chart_rounded),
                          label: const Text('ดูรายได้ทุกเดือน'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _primary,
                            side: const BorderSide(color: _primary),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _miniTotal(String label, double amount) {
    return Text(
      '$label ${amount.toStringAsFixed(0)}',
      style: TextStyle(color: Colors.white.withOpacity(0.95), fontSize: 12),
    );
  }

  Widget _buildCycleItem(Map<String, dynamic> item) {
    final travel = item['travel_expenses'] as double;
    final allowance = item['daily_allowance'] as double;
    final sum = travel + allowance;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: _primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _thaiShortDate(item['delivery_date'] as String),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: _primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name'] as String,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'เที่ยว ${travel.toStringAsFixed(0)} · เบี้ยเลี้ยง ${allowance.toStringAsFixed(0)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${sum.toStringAsFixed(0)} ฿',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF179E5B),
            ),
          ),
        ],
      ),
    );
  }

  // ===================== เมนูลัดแบบ Grid =====================
  Widget _buildQuickActionsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.05,
      children: [
        _buildActionCard(
          icon: Icons.assignment_rounded,
          color: const Color(0xFFFF9800),
          title: 'งานของฉัน',
          subtitle: _pendingJobsCount > 0
              ? '$_pendingJobsCount คิวที่ต้องส่ง'
              : 'ไม่มีงานรอดำเนินการ',
          badge: _pendingJobsCount > 0 ? '$_pendingJobsCount' : null,
          onTap: widget.driver.active
              ? () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MyJobsScreen(driver: widget.driver),
                    ),
                  );
                  _loadPendingJobsCount();
                }
              : _showInactiveDialog,
        ),
        _buildActionCard(
          icon: Icons.account_balance_wallet_rounded,
          color: const Color(0xFF2BB673),
          title: 'รายได้',
          subtitle: 'ดูรายได้ตามรอบ',
          onTap: widget.driver.active
              ? () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => IncomeScreen(driver: widget.driver),
                    ),
                  )
              : _showInactiveDialog,
        ),
        _buildActionCard(
          icon: Icons.car_repair_rounded,
          color: const Color(0xFF14B8A6),
          title: 'ตรวจสอบสภาพรถ',
          subtitle: 'บันทึกการตรวจเช็ค',
          onTap: widget.driver.active
              ? () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          VehicleInspectionScreen(driver: widget.driver),
                    ),
                  )
              : _showInactiveDialog,
        ),
        _buildActionCard(
          icon: Icons.history_rounded,
          color: const Color(0xFF3B82F6),
          title: 'ประวัติการจัดส่ง',
          subtitle: 'งานที่เสร็จแล้ว',
          onTap: widget.driver.active
              ? () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          DeliveryHistoryScreen(driver: widget.driver),
                    ),
                  )
              : _showInactiveDialog,
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    String? badge,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      elevation: 1.5,
      shadowColor: Colors.black.withOpacity(0.08),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: color, size: 26),
                  ),
                  const Spacer(),
                  if (badge != null)
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        badge,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ⚠️ การ์ดเตือนเมื่อบัญชีถูกระงับ
  Widget _buildInactiveWarning() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 52, color: Colors.red.shade700),
          const SizedBox(height: 12),
          Text(
            'บัญชีของคุณถูกระงับ',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.red.shade900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'กรุณาติดต่อผู้ดูแลระบบ',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.red.shade700),
          ),
        ],
      ),
    );
  }

  // ===================== Dialogs =====================
  void _showDriverInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Text(
          widget.driver.name,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
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

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                MaterialPageRoute(builder: (context) => const LoginScreen()),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: Icon(Icons.block, size: 64, color: Colors.red.shade700),
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
              style: TextStyle(fontSize: 16, color: Colors.red.shade700),
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
}
