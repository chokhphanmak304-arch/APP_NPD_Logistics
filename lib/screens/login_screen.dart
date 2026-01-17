import 'package:flutter/material.dart';
import '../services/odoo_service.dart';
import '../services/connection_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  final OdooService? odooService;

  const LoginScreen({
    super.key,
    this.odooService,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String _pin = '';
  late OdooService _odooService;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _odooService = widget.odooService ?? OdooService();
  }

  void _onNumberPressed(String number) {
    if (_pin.length < 6) {
      setState(() {
        _pin += number;
      });
      
      if (_pin.length == 6) {
        _handleLogin();
      }
    }
  }

  void _onDeletePressed() {
    if (_pin.isNotEmpty) {
      setState(() {
        _pin = _pin.substring(0, _pin.length - 1);
      });
    }
  }

  Future<void> _handleLogin() async {
    if (_pin.length != 6) return;

    setState(() => _isLoading = true);

    try {
      // ✅ ตรวจสอบว่า OdooService ถูก initialize แล้วหรือไม่
      final driver = await _odooService.loginWithPin(_pin);

      if (!mounted) return;

      if (driver != null) {
        if (!driver.active) {
          _showErrorDialog('⚠️ บัญชีนี้ถูกระงับการใช้งาน');
          _clearPin();
          return;
        }

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => HomeScreen(driver: driver),
          ),
        );
      } else {
        _showErrorDialog('❌ PIN ไม่ถูกต้อง\nกรุณาลองใหม่อีกครั้ง');
        _clearPin();
      }
    } catch (e) {
      if (!mounted) return;
      _showErrorDialog('⚠️ เกิดข้อผิดพลาด\n$e');
      _clearPin();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _clearPin() {
    setState(() {
      _pin = '';
    });
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('แจ้งเตือน'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 40),
                
                // NPD Logo
                Image.asset(
                  'assets/images/192x192.png',
                  width: 120,
                  height: 120,
                ),
                
                const SizedBox(height: 60),
                
                // PIN Label
                Text(
                  'กรอก PIN 6 หลัก',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // PIN Dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    6,
                    (index) => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: index < _pin.length
                            ? const Color(0xFF2196F3)
                            : Colors.transparent,
                        border: Border.all(
                          color: index < _pin.length
                              ? const Color(0xFF2196F3)
                              : Colors.grey.shade400,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 60),
                
                // Loading or Keypad
                if (_isLoading)
                  const CircularProgressIndicator(
                    color: Color(0xFF2196F3),
                  )
                else
                  Column(
                    children: [
                      _buildKeypadRow(['1', '2', '3']),
                      const SizedBox(height: 16),
                      _buildKeypadRow(['4', '5', '6']),
                      const SizedBox(height: 16),
                      _buildKeypadRow(['7', '8', '9']),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(width: 80), // Empty space
                          const SizedBox(width: 16),
                          _buildKeypadButton('0'),
                          const SizedBox(width: 16),
                          _buildDeleteButton(),
                        ],
                      ),
                    ],
                  ),
                
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKeypadRow(List<String> numbers) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: numbers.map((number) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: _buildKeypadButton(number),
        );
      }).toList(),
    );
  }

  Widget _buildKeypadButton(String number) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade300,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onNumberPressed(number),
          customBorder: const CircleBorder(),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeleteButton() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade300,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _onDeletePressed,
          customBorder: const CircleBorder(),
          child: const Center(
            child: Icon(
              Icons.backspace_outlined,
              size: 28,
              color: Colors.black54,
            ),
          ),
        ),
      ),
    );
  }
}
