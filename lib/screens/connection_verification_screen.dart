import 'package:flutter/material.dart';
import '../services/connection_service.dart';
import '../services/odoo_service.dart';
import '../services/odoo_config_holder.dart';
import 'login_screen.dart';

class ConnectionVerificationScreen extends StatefulWidget {
  const ConnectionVerificationScreen({super.key});

  @override
  State<ConnectionVerificationScreen> createState() =>
      _ConnectionVerificationScreenState();
}

class _ConnectionVerificationScreenState
    extends State<ConnectionVerificationScreen> {
  late Future<bool> _connectionFuture;
  bool _hasInitialized = false;  // ✅ Flag to prevent multiple initializations

  @override
  void initState() {
    super.initState();
    print('🔧 [ConnectionVerificationScreen] initState called');
    _connectionFuture = _verifyConnection();
  }

  Future<bool> _verifyConnection() async {
    try {
      print('🔄 [ConnectionVerificationScreen] Starting connection verification...');
      
      // ดึงการตั้งค่าการเชื่อมต่อจาก API
      final config = await ConnectionService.fetchConnectionConfig(forceRefresh: true);
      
      if (config == null) {
        print('❌ [ConnectionVerificationScreen] Failed to fetch connection config');
        return false;
      }

      // ✅ บรรจุ config ลงใน Singleton เพื่อให้ OdooService สามารถเข้าถึงได้
      OdooConfigHolder.getInstance().setConfig(config);
      print('✅ [ConnectionVerificationScreen] Config stored in singleton');

      // ทดสอบการเชื่อมต่อกับ Odoo
      final isConnected = await ConnectionService.testConnection(config);
      
      if (isConnected) {
        print('✅ [ConnectionVerificationScreen] Connection verified successfully');
        // รอ 1 วินาทีเพื่อให้ผู้ใช้เห็น success state
        await Future.delayed(const Duration(seconds: 1));
        return true;
      } else {
        print('❌ [ConnectionVerificationScreen] Connection test failed');
        return false;
      }
    } catch (e) {
      print('❌ [ConnectionVerificationScreen] Verification error: $e');
      return false;
    }
  }

  void _retryConnection() {
    setState(() {
      _connectionFuture = _verifyConnection();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: FutureBuilder<bool>(
            future: _connectionFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _buildLoadingState();
              } else if (snapshot.hasError) {
                return _buildErrorState('เกิดข้อผิดพลาด: ${snapshot.error}');
              } else if (snapshot.data == true) {
                // ✅ เชื่อมต่อสำเร็จ - navigate ทันที
                Future.microtask(() {
                  if (mounted) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LoginScreen(odooService: OdooService()),
                      ),
                    );
                  }
                });
                return _buildLoadingState();
              } else {
                return _buildErrorState('ไม่สามารถเชื่อมต่อกับระบบได้');
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 60),
          
          // NPD Logo
          Image.asset(
            'assets/images/192x192.png',
            width: 120,
            height: 120,
          ),
          
          const SizedBox(height: 60),
          
          // Animated Loading
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2196F3)),
            strokeWidth: 3,
          ),
          
          const SizedBox(height: 40),
          
          // Status Text
          const Text(
            'กำลังตรวจสอบการเชื่อมต่อ',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
          
          const SizedBox(height: 8),
          
          const Text(
            'กรุณารอสักครู่...',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
          
          const SizedBox(height: 60),
        ],
      ),
    );
  }

  Widget _buildErrorState(String errorMessage) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 60),
          
          // NPD Logo
          Image.asset(
            'assets/images/192x192.png',
            width: 120,
            height: 120,
          ),
          
          const SizedBox(height: 60),
          
          // Error Icon
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.red.shade100,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(
                Icons.error_outline,
                size: 50,
                color: Colors.red.shade700,
              ),
            ),
          ),
          
          const SizedBox(height: 32),
          
          // Error Title
          const Text(
            'ไม่สามารถเชื่อมต่อ',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Error Message
          Text(
            errorMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
              height: 1.5,
            ),
          ),
          
          const SizedBox(height: 40),
          
          // Retry Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _retryConnection,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2196F3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.refresh, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'ลองใหม่อีกครั้ง',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 60),
        ],
      ),
    );
  }
}
