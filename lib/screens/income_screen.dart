import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/driver.dart';
import '../models/income_data.dart';
import '../services/odoo_service.dart';
import 'home_screen.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.orange,
        title: Row(
          children: [
            const Icon(Icons.attach_money, color: Colors.white, size: 24),
            const SizedBox(width: 8),
            const Text('รายได้'),
          ],
        ),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error, color: Colors.red, size: 48),
                      const SizedBox(height: 16),
                      Text(_errorMessage!),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _loadIncomeData,
                        child: const Text('ลองใหม่'),
                      ),
                    ],
                  ),
                )
              : _incomeData.isEmpty
                  ? const Center(
                      child: Text('ไม่มีข้อมูลรายได้'),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadIncomeData,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _incomeData.length,
                        itemBuilder: (context, index) {
                          final income = _incomeData[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: 2,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Header: เดือน ปี และจำนวนครั้ง
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        income.displayText,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade100,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          '${income.totalDeliveries} ครั้ง',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.blue.shade700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  
                                  // รายละเอียดค่าใช้จ่าย
                                  _buildIncomeRow(
                                    icon: Icons.directions_car,
                                    label: 'ค่าเที่ยว',
                                    amount: income.totalTravelExpenses,
                                    color: Colors.blue,
                                  ),
                                  const SizedBox(height: 8),
                                  _buildIncomeRow(
                                    icon: Icons.restaurant,
                                    label: 'ค่าเบี้ยเลี้ยง',
                                    amount: income.totalDailyAllowance,
                                    color: Colors.orange,
                                  ),
                                  const SizedBox(height: 12),
                                  
                                  // Divider
                                  Container(
                                    height: 1,
                                    color: Colors.grey.shade300,
                                  ),
                                  const SizedBox(height: 12),
                                  
                                  // รวมรายได้
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'รวมรายได้',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        '${income.totalIncome.toStringAsFixed(2)} บาท',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF4CAF50),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: 3,
        driver: widget.driver,
      ),
    );
  }

  Widget _buildIncomeRow({
    required IconData icon,
    required String label,
    required double amount,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        Text(
          '${amount.toStringAsFixed(2)} บาท',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}