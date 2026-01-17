import 'package:flutter/material.dart';
import '../models/driver.dart';
import '../screens/home_screen.dart';
import '../screens/my_jobs_screen.dart';
import '../screens/delivery_history_screen.dart';
import '../screens/income_screen.dart';

class CustomBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final Driver driver;

  const CustomBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.driver,
  });

  void _onNavItemTapped(BuildContext context, int index) {
    if (index == currentIndex) return; // ไม่ทำอะไรถ้าเลือกเมนูเดิม

    Widget nextScreen;

    if (index == 0) {
      nextScreen = HomeScreen(driver: driver);
    } else if (index == 1) {
      nextScreen = MyJobsScreen(driver: driver);
    } else if (index == 2) {
      nextScreen = DeliveryHistoryScreen(driver: driver);
    } else {
      nextScreen = IncomeScreen(driver: driver);
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => nextScreen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (index) => _onNavItemTapped(context, index),
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFF2196F3),
        unselectedItemColor: Colors.grey.shade600,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        iconSize: 24,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'หน้าหลัก',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment_turned_in),
            label: 'งานของฉัน',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'ประวัติจัดส่ง',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.attach_money),
            label: 'รายได้',
          ),
        ],
      ),
    );
  }
}
