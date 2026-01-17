import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../models/tracking_models.dart';
import '../models/driver.dart';
import '../services/tracking_service.dart';
import '../services/gps_service.dart';
import '../services/marker_generator.dart';
import '../widgets/bottom_nav_bar.dart';

class TrackingScreen extends StatefulWidget {
  final ActiveBooking booking;
  final Driver? driver;

  const TrackingScreen({
    super.key,
    required this.booking,
    this.driver,
  });

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  final TrackingService _trackingService = TrackingService();
  final GpsService _gpsService = GpsService();
  
  GoogleMapController? _mapController;
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStreamSubscription;
  Timer? _updateTimer;
  
  TrackingSettings _settings = TrackingSettings();
  List<TrackingHistory> _routeHistory = [];
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  
  bool _isLoading = true;
  bool _isTracking = false;
  double _currentSpeed = 0.0;

  @override
  void initState() {
    super.initState();
    _initializeTracking();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _updateTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _initializeTracking() async {
    try {
      final settings = await _trackingService.loadSettings();
      if (settings != null) {
        setState(() {
          _settings = TrackingSettings(
            trackingRefreshInterval: settings.trackingInterval,
            autoCenterMap: true,
            showRouteHistory: true,
            showSpeedIndicator: true,
            notificationEnabled: true,
          );
        });
      }

      await _loadRouteHistory();

      final hasPermission = await _gpsService.checkAndRequestPermissions();
      if (!hasPermission) {
        _showError('กรุณาอนุญาตการเข้าถึงตำแหน่ง');
        return;
      }

      await _startTracking();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error initializing tracking: $e');
      setState(() {
        _isLoading = false;
      });
      _showError('เกิดข้อผิดพลาดในการเริ่มต้นระบบติดตาม');
    }
  }

  Future<void> _loadRouteHistory() async {
    if (!_settings.showRouteHistory) return;
    
    final history = await _trackingService.getTrackingHistory(
      bookingId: widget.booking.id,
      hours: 24,
    );
    
    if (history.isNotEmpty) {
      setState(() {
        _routeHistory = history.map((item) => TrackingHistory.fromJson(item)).toList();
        _updatePolylines();
      });
    }
  }

  Future<void> _startTracking() async {
    setState(() {
      _isTracking = true;
    });

    final position = await _gpsService.getCurrentPosition();
    if (position != null) {
      _updatePosition(position);
    }

    _positionStreamSubscription = _gpsService.getPositionStream().listen(
      (position) {
        _updatePosition(position);
      },
      onError: (error) {
        print('❌ Position stream error: $error');
      },
    );

    _startUpdateTimer();
  }

  void _startUpdateTimer() {
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(
      Duration(seconds: _settings.trackingRefreshInterval),
      (timer) {
        if (_currentPosition != null && _isTracking) {
          _sendLocationUpdate();
        }
      },
    );
  }

  void _updatePosition(Position position) {
    setState(() {
      _currentPosition = position;
      _currentSpeed = position.speed * 3.6;
    });

    _updateMarkers();

    if (_settings.autoCenterMap && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLng(
          LatLng(position.latitude, position.longitude),
        ),
      );
    }
  }

  Future<void> _sendLocationUpdate() async {
    if (_currentPosition == null) return;

    final success = await _trackingService.updateLocation(
      bookingId: widget.booking.id,
      latitude: _currentPosition!.latitude,
      longitude: _currentPosition!.longitude,
      speed: _currentSpeed,
      heading: _currentPosition!.heading,
    );

    if (!success) {
      print('⚠️ Failed to send location update');
    }
  }

  Future<void> _updateMarkers() async {
    final markers = <Marker>{};

    if (_currentPosition != null) {
      final vehicleIcon = await MarkerGenerator.createVehicleMarker(
        licensePlate: widget.booking.vehicle?['license_plate'] ?? 'N/A',
        heading: _currentPosition!.heading,
        color: Colors.blue[700]!,
      );
      
      markers.add(
        Marker(
          markerId: const MarkerId('current_vehicle'),
          position: LatLng(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
          ),
          icon: vehicleIcon,
          rotation: _currentPosition!.heading,
          anchor: const Offset(0.5, 0.5),
          infoWindow: InfoWindow(
            title: '🚚 ${widget.booking.vehicle?['license_plate'] ?? 'รถขนส่ง'}',
            snippet: _settings.showSpeedIndicator
                ? '🚗 ความเร็ว: ${_currentSpeed.toStringAsFixed(1)} km/h'
                : null,
          ),
        ),
      );
    }

    final pickupIcon = await MarkerGenerator.createLocationMarker(
      label: '📦',
      color: Colors.green,
    );
    
    markers.add(
      Marker(
        markerId: const MarkerId('pickup'),
        position: _parseLocation(widget.booking.pickupLocation),
        icon: pickupIcon,
        anchor: const Offset(0.5, 1.0),
        infoWindow: InfoWindow(
          title: '📍 จุดรับสินค้า',
          snippet: widget.booking.pickupLocation,
        ),
      ),
    );

    final destIcon = await MarkerGenerator.createLocationMarker(
      label: '🎯',
      color: Colors.red,
    );
    
    markers.add(
      Marker(
        markerId: const MarkerId('destination'),
        position: _parseLocation(widget.booking.destination),
        icon: destIcon,
        anchor: const Offset(0.5, 1.0),
        infoWindow: InfoWindow(
          title: '🎯 ปลายทาง',
          snippet: widget.booking.destination,
        ),
      ),
    );

    setState(() {
      _markers = markers;
    });
  }

  void _updatePolylines() {
    if (!_settings.showRouteHistory || _routeHistory.isEmpty) {
      setState(() {
        _polylines = {};
      });
      return;
    }

    final points = _routeHistory.map((h) => LatLng(h.latitude, h.longitude)).toList();

    setState(() {
      _polylines = {
        Polyline(
          polylineId: const PolylineId('route'),
          points: points,
          color: Colors.blue,
          width: 4,
          patterns: [PatternItem.dash(20), PatternItem.gap(10)],
        ),
      };
    });
  }

  LatLng _parseLocation(String location) {
    try {
      final parts = location.split(',');
      if (parts.length >= 2) {
        final lat = double.tryParse(parts[0].trim());
        final lng = double.tryParse(parts[1].trim());
        if (lat != null && lng != null) {
          return LatLng(lat, lng);
        }
      }
    } catch (e) {
      print('⚠️ Error parsing location: $e');
    }
    return const LatLng(13.7563, 100.5018);
  }

  void _stopTracking() {
    setState(() {
      _isTracking = false;
    });
    _positionStreamSubscription?.cancel();
    _updateTimer?.cancel();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('📍 ติดตามการขนส่ง'),
          backgroundColor: Colors.blue[700],
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('📍 ${widget.booking.name}'),
        backgroundColor: Colors.blue[700],
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadRouteHistory();
              _updateMarkers();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _currentPosition != null
                  ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                  : _parseLocation(widget.booking.pickupLocation),
              zoom: 14,
            ),
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            compassEnabled: true,
            zoomControlsEnabled: true,
            mapType: MapType.normal,
            onMapCreated: (controller) {
              _mapController = controller;
            },
          ),
          
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: _buildInfoCard(),
          ),
          
          if (_settings.showSpeedIndicator)
            Positioned(
              bottom: 100,
              right: 16,
              child: _buildSpeedIndicator(),
            ),
          
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: _buildControlButtons(),
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

  Widget _buildInfoCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '🚚 ${widget.booking.vehicle?['license_plate'] ?? 'ไม่ระบุ'}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _buildStatusChip(),
              ],
            ),
            const Divider(height: 16),
            Text(
              '👤 คนขับ: ${widget.booking.driver?['name'] ?? 'ไม่ระบุ'}',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              '📍 จาก: ${widget.booking.pickupLocation}',
              style: const TextStyle(fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              '🎯 ไป: ${widget.booking.destination}',
              style: const TextStyle(fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip() {
    final statusInfo = _getStatusInfo(widget.booking.trackingStatus);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: statusInfo['color'],
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        statusInfo['text'],
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Map<String, dynamic> _getStatusInfo(String status) {
    switch (status) {
      case 'pending':
        return {'text': 'รอออกเดินทาง', 'color': Colors.orange};
      case 'picked_up':
        return {'text': 'รับสินค้าแล้ว', 'color': Colors.blue};
      case 'in_transit':
        return {'text': 'กำลังขนส่ง', 'color': Colors.green};
      case 'near_destination':
        return {'text': 'ใกล้ถึง', 'color': Colors.purple};
      case 'delivered':
        return {'text': 'ส่งถึงแล้ว', 'color': Colors.teal};
      default:
        return {'text': 'ไม่ทราบสถานะ', 'color': Colors.grey};
    }
  }

  Widget _buildSpeedIndicator() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: Colors.blue[700],
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            const Icon(
              Icons.speed,
              color: Colors.white,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              _currentSpeed.toStringAsFixed(1),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Text(
              'km/h',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {
              if (_isTracking) {
                _stopTracking();
              } else {
                _startTracking();
              }
            },
            icon: Icon(_isTracking ? Icons.pause : Icons.play_arrow),
            label: Text(_isTracking ? 'หยุดติดตาม' : 'เริ่มติดตาม'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isTracking ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
