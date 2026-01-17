import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/booking.dart';
import '../models/driver.dart';
import '../services/odoo_service.dart';
import '../services/background_location_service.dart';
import '../widgets/bottom_nav_bar.dart';

class NavigationMapScreen extends StatefulWidget {
  final Booking booking;
  final Driver? driver;

  const NavigationMapScreen({
    super.key,
    required this.booking,
    this.driver,
  });

  @override
  State<NavigationMapScreen> createState() => _NavigationMapScreenState();
}

class _NavigationMapScreenState extends State<NavigationMapScreen> {
  GoogleMapController? _mapController;
  Position? _currentPosition;
  bool _isLoadingLocation = true;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  
  // พิกัดปลายทาง
  LatLng? _destinationLatLng;
  
  // ✅ สำหรับ Real-time Update
  final OdooService _odooService = OdooService();
  Timer? _updateTimer;
  Booking? _latestBooking;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _latestBooking = widget.booking;
    _initMap();
    _startRealtimeUpdates();
  }

  // ✅ เริ่ม Real-time Updates
  void _startRealtimeUpdates() {
    print('🔄 Starting real-time destination updates');
    
    // อัพเดททุก 15 วินาที
    _updateTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      await _checkForUpdates();
    });
  }

  // ✅ เช็คการเปลี่ยนแปลงจาก Odoo
  Future<void> _checkForUpdates() async {
    if (_isUpdating) return;
    
    try {
      setState(() {
        _isUpdating = true;
      });

      print('🔍 Checking for destination updates...');
      
      // ดึงข้อมูล booking ล่าสุดจาก Odoo
      final updatedBooking = await _odooService.getBookingById(widget.booking.id);
      
      if (updatedBooking == null) {
        print('⚠️  Cannot fetch booking updates');
        return;
      }

      // เช็คว่าพิกัดปลายทางเปลี่ยนหรือไม่
      final oldDestLat = _latestBooking?.destinationLatitude;
      final oldDestLng = _latestBooking?.destinationLongitude;
      final newDestLat = updatedBooking.destinationLatitude;
      final newDestLng = updatedBooking.destinationLongitude;

      if (oldDestLat != newDestLat || oldDestLng != newDestLng) {
        print('🎯 Destination changed!');
        print('   Old: ($oldDestLat, $oldDestLng)');
        print('   New: ($newDestLat, $newDestLng)');
        
        // อัพเดทข้อมูล
        setState(() {
          _latestBooking = updatedBooking;
          _destinationLatLng = (newDestLat != null && newDestLng != null)
              ? LatLng(newDestLat, newDestLng)
              : null;
        });
        
        // อัพเดท markers
        _setupMarkers();
        
        // แสดงการแจ้งเตือน
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('📍 ปลายทางได้รับการอัพเดทแล้ว'),
              backgroundColor: Colors.blue.shade700,
              duration: const Duration(seconds: 3),
              action: SnackBarAction(
                label: 'ดูแผนที่',
                textColor: Colors.white,
                onPressed: _fitMapToMarkers,
              ),
            ),
          );
        }
      } else {
        print('✅ No destination changes');
      }
    } catch (e) {
      print('❌ Error checking for updates: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  Future<void> _initMap() async {
    await _getCurrentLocation();
    _setupMarkers();
  }

  Future<void> _getCurrentLocation() async {
    try {
      // 1. ตรวจสอบว่า Location Service เปิดอยู่หรือไม่
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('❌ Location services are disabled');
        setState(() {
          _isLoadingLocation = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ กรุณาเปิด GPS ในการตั้งค่า'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // 2. ตรวจสอบและขอ Permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        print('📍 Requesting location permission...');
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('❌ Location permission denied');
          setState(() {
            _isLoadingLocation = false;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('❌ กรุณาอนุญาตให้แอปเข้าถึงตำแหน่ง'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 3),
              ),
            );
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('❌ Location permission denied forever');
        setState(() {
          _isLoadingLocation = false;
        });
        if (mounted) {
          _showOpenSettingsDialog();
        }
        return;
      }

      // 3. ดึงตำแหน่งปัจจุบัน
      print('📍 Getting current position...');
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      setState(() {
        _currentPosition = position;
        _isLoadingLocation = false;
      });

      print('✅ Current location: ${position.latitude}, ${position.longitude}');
    } catch (e) {
      print('❌ Error getting location: $e');
      setState(() {
        _isLoadingLocation = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ไม่สามารถเข้าถึงตำแหน่งได้: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _showOpenSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ ต้องการสิทธิ์เข้าถึงตำแหน่ง'),
        content: const Text(
          'แอปต้องการสิทธิ์เข้าถึงตำแหน่งเพื่อแสดงแผนที่นำทาง\n\n'
          'กรุณาไปที่การตั้งค่า → แอป → สิทธิ์ → เปิดใช้งาน "ตำแหน่ง"',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await Geolocator.openLocationSettings();
            },
            child: const Text('เปิดการตั้งค่า'),
          ),
        ],
      ),
    );
  }

  void _setupMarkers() {
    final markers = <Marker>{};

    // Marker: ตำแหน่งปัจจุบัน (ต้นทาง)
    if (_currentPosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('current'),
          position: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(
            title: '🏁 ต้นทาง (ตำแหน่งปัจจุบัน)',
            snippet: 'คุณอยู่ที่นี่',
          ),
        ),
      );
    }

    // ✅ Marker: ปลายทาง (ใช้ข้อมูลล่าสุด)
    // เช็คว่ามีพิกัดจริง และไม่ใช่ 0.0 (ค่า default ของ Odoo)
    if (_latestBooking?.destinationLatitude != null && 
        _latestBooking?.destinationLongitude != null &&
        _latestBooking!.destinationLatitude! != 0.0 &&
        _latestBooking!.destinationLongitude! != 0.0) {
      _destinationLatLng = LatLng(
        _latestBooking!.destinationLatitude!,
        _latestBooking!.destinationLongitude!,
      );
      
      markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: _destinationLatLng!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: '🎯 ปลายทาง',
            snippet: _latestBooking!.destination ?? '',
          ),
        ),
      );
    }

    setState(() {
      _markers = markers;
    });

    // ปรับ camera ให้เห็นทุก marker
    _fitMapToMarkers();
  }

  void _fitMapToMarkers() async {
    if (_mapController == null || _markers.isEmpty) return;

    // หา bounds ของทุก marker
    double? minLat, maxLat, minLng, maxLng;

    for (var marker in _markers) {
      final lat = marker.position.latitude;
      final lng = marker.position.longitude;

      minLat = minLat == null ? lat : (lat < minLat ? lat : minLat);
      maxLat = maxLat == null ? lat : (lat > maxLat ? lat : maxLat);
      minLng = minLng == null ? lng : (lng < minLng ? lng : minLng);
      maxLng = maxLng == null ? lng : (lng > maxLng ? lng : maxLng);
    }

    if (minLat != null && maxLat != null && minLng != null && maxLng != null) {
      final bounds = LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      );

      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 100), // 100 = padding
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text(
              '🗺️ แผนที่นำทาง',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            if (_isUpdating) ...[
              const SizedBox(width: 8),
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ],
          ],
        ),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      body: Stack(
        children: [
          // แผนที่
          _isLoadingLocation
              ? const Center(child: CircularProgressIndicator())
              : _currentPosition == null
                  ? _buildLocationError()
                  : GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: LatLng(
                          _currentPosition!.latitude,
                          _currentPosition!.longitude,
                        ),
                        zoom: 14,
                      ),
                      markers: _markers,
                      polylines: _polylines,
                      myLocationEnabled: true,
                      myLocationButtonEnabled: true,
                      zoomControlsEnabled: true,
                      mapToolbarEnabled: false,
                      onMapCreated: (controller) {
                        _mapController = controller;
                        _fitMapToMarkers();
                      },
                    ),

          // ข้อมูลงาน (ด้านบน)
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: _buildJobInfoCard(),
          ),

          // ปุ่ม action (ด้านล่าง)
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: _buildActionButtons(),
          ),
        ],
      ),
      // ✅ Bottom Navigation Bar
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
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _latestBooking?.name ?? widget.booking.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_isUpdating)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.navigation, size: 16, color: Colors.blue),
                const SizedBox(width: 4),
                const Expanded(
                  child: Text(
                    'กำลังนำทางจากตำแหน่งปัจจุบัน',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.blue,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_latestBooking?.destination != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.flag, size: 16, color: Colors.red),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'ปลายทาง: ${_latestBooking!.destination}',
                      style: const TextStyle(fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            if (_latestBooking?.destinationLatitude != null && 
                _latestBooking?.destinationLongitude != null &&
                _latestBooking!.destinationLatitude! != 0.0 &&
                _latestBooking!.destinationLongitude! != 0.0) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 16, color: Colors.green),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'พิกัด: ${_latestBooking!.destinationLatitude!.toStringAsFixed(5)}, ${_latestBooking!.destinationLongitude!.toStringAsFixed(5)}',
                      style: const TextStyle(fontSize: 12, color: Colors.green),
                    ),
                  ),
                ],
              ),
            ],
            if (_latestBooking?.distanceKm != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.straighten, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    'ระยะทาง: ${_latestBooking!.distanceKm!.toStringAsFixed(1)} กม.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ปุ่มเปิด Google Maps สำหรับนำทางจริง
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: _openGoogleMapsNavigation,
            icon: const Icon(Icons.navigation, size: 28),
            label: const Text(
              'เปิด Google Maps นำทาง',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 4,
            ),
          ),
        ),
        const SizedBox(height: 8),
        
        // ปุ่มกลับไปตำแหน่งปัจจุบัน
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _goToCurrentLocation,
            icon: const Icon(Icons.my_location, size: 20),
            label: const Text('กลับไปตำแหน่งปัจจุบัน'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.blue.shade700,
              side: BorderSide(color: Colors.blue.shade700, width: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        
        // ✅ ปุ่มอัพเดทข้อมูลด้วยตนเอง
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _isUpdating ? null : _checkForUpdates,
            icon: Icon(
              _isUpdating ? Icons.hourglass_empty : Icons.refresh,
              size: 20,
            ),
            label: Text(_isUpdating ? 'กำลังอัพเดท...' : 'รีเฟรชข้อมูล'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.green.shade700,
              side: BorderSide(color: Colors.green.shade700, width: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLocationError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.location_off,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'ไม่สามารถเข้าถึงตำแหน่งได้',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'กรุณาเปิด GPS และอนุญาตให้แอปเข้าถึงตำแหน่ง',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _initMap,
            icon: const Icon(Icons.refresh),
            label: const Text('ลองอีกครั้ง'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openGoogleMapsNavigation() async {
    // ใช้ข้อมูลล่าสุด
    final booking = _latestBooking ?? widget.booking;
    
    // ต้องมีปลายทาง
    if (booking.destination == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ ไม่พบข้อมูลปลายทาง'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // ตรวจสอบว่ามีตำแหน่งปัจจุบันหรือไม่
    if (_currentPosition == null) {
      await _getCurrentLocation();
      if (_currentPosition == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ กรุณาเปิด GPS และอนุญาตให้แอปเข้าถึงตำแหน่ง'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    // เตรียม origin (ตำแหน่งปัจจุบัน)
    // 🔧 DEBUG: ใช้พิกัดจำลองในประเทศไทยสำหรับ development
    final debugMode = true; // เปลี่ยนเป็น false สำหรับ production
    final originParam = debugMode 
        ? '13.7563,100.5018' // กรุงเทพฯ (mock location)
        : '${_currentPosition!.latitude},${_currentPosition!.longitude}';
    String destParam;
    bool isPlusCode = false;
    
    // ✅ ถ้ามีพิกัดปลายทางที่ถูกต้อง (ไม่ใช่ 0.0) ใช้พิกัด (แม่นยำที่สุด)
    if (booking.destinationLatitude != null && 
        booking.destinationLongitude != null &&
        booking.destinationLatitude! != 0.0 &&
        booking.destinationLongitude! != 0.0) {
      destParam = '${booking.destinationLatitude},${booking.destinationLongitude}';
      print('📍 Using GPS coordinates: $destParam');
    } else {
      // ตรวจสอบว่าเป็น Plus Code หรือไม่
      final destination = booking.destination!.trim();
      
      // Plus Code pattern: มักมีเครื่องหมาย + หรือรูปแบบ XXXX+XX
      // รวมถึง Plus Code แบบสั้น เช่น "2040"
      isPlusCode = destination.contains('+') || 
                   RegExp(r'^[23456789CFGHJMPQRVWX]{4,8}\+?[23456789CFGHJMPQRVWX]{0,2}$', caseSensitive: false).hasMatch(destination);
      
      if (isPlusCode) {
        print('📍 Detected Plus Code: $destination');
        
        // ถ้าเป็น Plus Code แบบสั้น (ไม่มีพื้นที่อ้างอิง) ให้เพิ่มพื้นที่อ้างอิงจากตำแหน่งปัจจุบัน
        String fullPlusCode = destination;
        if (!destination.contains(',') && destination.length < 8) {
          // เพิ่มพื้นที่อ้างอิง Bangkok, Thailand สำหรับ Plus Code แบบสั้น
          fullPlusCode = '$destination Bangkok, Thailand';
          print('📍 Extended Plus Code: $fullPlusCode');
        }
        destParam = Uri.encodeComponent(fullPlusCode);
      } else {
        print('📍 Using address: $destination');
        destParam = Uri.encodeComponent(destination);
      }
    }

    // สร้าง URL schemes พร้อม origin และ destination
    List<String> schemes;
    
    // ใช้ Google Maps Directions API พร้อม origin และ destination
    schemes = [
      // Google Maps app - พร้อม origin และ destination
      'comgooglemaps://?saddr=$originParam&daddr=$destParam&directionsmode=driving',
      
      // Google Navigation - พร้อม origin
      'google.navigation:q=$destParam&origin=$originParam&mode=d',
      
      // Web URL - Directions API พร้อม origin และ destination
      'https://www.google.com/maps/dir/?api=1&origin=$originParam&destination=$destParam&travelmode=driving&dir_action=navigate',
      
      // Backup: Web URL - แบบ search ธรรมดา (สำหรับ Plus Code)
      'https://www.google.com/maps/search/?api=1&query=$destParam',
    ];
    
    print('🗺️ Navigating from: $originParam to: ${booking.destination}');
    print('🗺️ URL destination param: $destParam');

    for (final urlString in schemes) {
      try {
        print('🚀 Trying: $urlString');
        final uri = Uri.parse(urlString);
        
        if (await canLaunchUrl(uri)) {
          await launchUrl(
            uri, 
            mode: LaunchMode.externalApplication,
          );
          
          if (mounted) {
            // ✅ เริ่ม background tracking เพื่อให้ส่งตำแหน่งต่อเนื่อง
            try {
              final booking = _latestBooking ?? widget.booking;
              await BackgroundLocationService.setActiveBookingId(booking.id);
              await BackgroundLocationService.initializeService();
              print('✅ Navigation: Background tracking activated');
            } catch (e) {
              print('⚠️ Navigation: Background tracking error: $e');
            }

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🧭 เปิด Google Maps นำทางแล้ว\n'
                              '📍 ติดตามตำแหน่งต่อเนื่อง (แม้ปิดแอป)'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
          }
          return;
        }
      } catch (e) {
        print('❌ Failed to launch: $urlString - Error: $e');
        continue;
      }
    }

    // ถ้าทุกวิธีล้มเหลว ให้เปิด Google Maps พื้นฐาน
    try {
      final fallbackUrl = 'https://maps.google.com?q=${booking.destination}';
      final uri = Uri.parse(fallbackUrl);
      
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🗺️ เปิด Google Maps แล้ว (โหมดค้นหา)'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }
    } catch (e) {
      print('❌ Fallback also failed: $e');
    }

    // ถ้าทุกวิธีล้มเหลวจริงๆ
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '❌ ไม่สามารถเปิด Google Maps ได้\n'
            'ปลายทาง: ${booking.destination}\n'
            'ลองคัดลอกที่อยู่ไปค้นหาใน Google Maps โดยตรง',
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'คัดลอกที่อยู่',
            textColor: Colors.white,
            onPressed: () {
              // คัดลอกที่อยู่ไปยัง clipboard
              Clipboard.setData(ClipboardData(text: booking.destination!));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('📋 คัดลอกที่อยู่แล้ว'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ),
      );
    }
  }

  void _goToCurrentLocation() {
    if (_currentPosition != null && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
            ),
            zoom: 16,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }
}
