import 'package:flutter/material.dart';
import '../models/driver.dart';
import '../models/income_data.dart';
import '../services/odoo_service.dart';
import '../widgets/bottom_nav_bar.dart';

class IncomeScreen extends StatefulWidget {
  final Driver driver;

  const IncomeScreen({
    Key? key,
    required this.driver,
  }) : super(key: key);

  @override
  State<IncomeScreen> createState() => _IncomeScreenState();
}

class _IncomeScreenState extends State<IncomeScreen> {
  late OdooService _odooService;
  List<IncomeData> _incomeData = [];
  bool _isLoading = true;
  String? _errorMessage;

  static const Color _accent = Color(0xFF179E5B);
  static const Color _accentLight = Color(0xFF2BB673);

  @override
  void initState() {
    super.initState();
    _odooService = OdooService();
    _loadIncomeData();
  }

  Future<void> _loadIncomeData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final income = await _odooService.getMonthlyIncome(widget.driver.id);
      setState(() {
        _incomeData = income;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  double get _grandTotal =>
      _incomeData.fold(0.0, (sum, e) => sum + e.totalIncome);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? _buildErrorView()
                    : _incomeData.isEmpty
                        ? _buildEmptyView()
                        : RefreshIndicator(
                            color: _accent,
                            onRefresh: _loadIncomeData,
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                              itemCount: _incomeData.length,
                              itemBuilder: (context, index) =>
                                  _buildIncomeCard(_incomeData[index]),
                            ),
                          ),
          ),
        ],
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: 3,
        driver: widget.driver,
      ),
    );
  }

  // ===================== Header =====================
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 0, 12, 24),
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
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                const Expanded(
                  child: Text(
                    'รายได้',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
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
                  onPressed: _isLoading ? null : _loadIncomeData,
                ),
              ],
            ),
            const SizedBox(height: 8),
            // สรุปยอดรวมทุกรอบ
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.savings_rounded,
                        color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'รายได้รวมทั้งหมด',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_grandTotal.toStringAsFixed(2)} บาท',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${_incomeData.length} รอบ',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 12,
                          ),
                        ),
                      ],
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

  // ===================== การ์ดรายได้แต่ละรอบ =====================
  Widget _buildIncomeCard(IncomeData income) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // หัว: เดือน + ช่วงรอบ + จำนวนครั้ง
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        income.displayText,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        income.periodText,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _accent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${income.totalDeliveries} ครั้ง',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _accent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            _buildExpenseRow(
              icon: Icons.directions_car_rounded,
              label: 'ค่าเที่ยว',
              amount: income.totalTravelExpenses,
              color: const Color(0xFF3B82F6),
            ),
            const SizedBox(height: 10),
            _buildExpenseRow(
              icon: Icons.restaurant_rounded,
              label: 'ค่าเบี้ยเลี้ยง',
              amount: income.totalDailyAllowance,
              color: const Color(0xFFFF9800),
            ),

            const SizedBox(height: 14),
            Container(height: 1, color: Colors.grey.shade200),
            const SizedBox(height: 14),

            // รวมรายได้
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'รวมรายได้',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
                Text(
                  '${income.totalIncome.toStringAsFixed(2)} บาท',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _accent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpenseRow({
    required IconData icon,
    required String label,
    required double amount,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, color: Color(0xFF374151)),
          ),
        ),
        Text(
          '${amount.toStringAsFixed(2)} บาท',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyView() {
    return ListView(
      // ListView เพื่อให้ pull-to-refresh ทำงานได้แม้ไม่มีข้อมูล
      children: [
        const SizedBox(height: 120),
        Icon(Icons.account_balance_wallet_outlined,
            size: 90, color: Colors.grey.shade300),
        const SizedBox(height: 20),
        Center(
          child: Text(
            'ยังไม่มีข้อมูลรายได้',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'รายได้จะแสดงหลังจากมีงานที่เสร็จสิ้น',
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
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadIncomeData,
            icon: const Icon(Icons.refresh),
            label: const Text('ลองใหม่'),
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
