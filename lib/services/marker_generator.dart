import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MarkerGenerator {
  /// สร้าง Custom Marker สำหรับรถ
  static Future<BitmapDescriptor> createVehicleMarker({
    required String licensePlate,
    required double heading,
    Color color = Colors.blue,
  }) async {
    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);
    const size = Size(120, 120);

    // วาดพื้นหลัง
    final bgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    // วาดวงกลมพื้นหลัง
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(center, 40, bgPaint);
    canvas.drawCircle(center, 40, borderPaint);

    // วาดไอคอนรถ
    _drawTruckIcon(canvas, center);

    // วาดป้ายทะเบียน
    if (licensePlate.isNotEmpty) {
      _drawLicensePlate(canvas, licensePlate, size);
    }

    // แปลงเป็น Image
    final picture = pictureRecorder.endRecording();
    final image = await picture.toImage(
      size.width.toInt(),
      size.height.toInt(),
    );
    
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  /// วาดไอคอนรถบรรทุก
  static void _drawTruckIcon(Canvas canvas, Offset center) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // ตัวรถ (สี่เหลี่ยม)
    final truckRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: 40, height: 24),
      const Radius.circular(4),
    );
    canvas.drawRRect(truckRect, paint);

    // หัวรถ (ด้านหน้า)
    final cabRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(center.dx + 12, center.dy),
        width: 16,
        height: 18,
      ),
      const Radius.circular(3),
    );
    canvas.drawRRect(cabRect, paint);

    // ล้อ
    final wheelPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(center.dx - 10, center.dy + 12), 4, wheelPaint);
    canvas.drawCircle(Offset(center.dx + 10, center.dy + 12), 4, wheelPaint);
  }

  /// วาดป้ายทะเบียน
  static void _drawLicensePlate(Canvas canvas, String text, Size size) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();

    // วาดพื้นหลังป้าย
    final plateRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        (size.width - textPainter.width - 12) / 2,
        size.height - 24,
        textPainter.width + 12,
        20,
      ),
      const Radius.circular(4),
    );

    final platePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final plateBorderPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawRRect(plateRect, platePaint);
    canvas.drawRRect(plateRect, plateBorderPaint);

    // วาดข้อความ
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        size.height - 22,
      ),
    );
  }

  /// สร้าง Marker ธรรมดาสำหรับจุดรับ-ส่ง
  static Future<BitmapDescriptor> createLocationMarker({
    required String label,
    required Color color,
    IconData icon = Icons.location_on,
  }) async {
    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);
    const size = Size(100, 140);

    // วาดหมุด (Pin Shape)
    final path = Path()
      ..moveTo(size.width / 2, size.height - 10)
      ..lineTo(size.width / 2 - 10, size.height - 30)
      ..arcToPoint(
        Offset(size.width / 2 + 10, size.height - 30),
        radius: const Radius.circular(50),
        clockwise: false,
      )
      ..close();

    final pinPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final pinBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawPath(path, pinPaint);
    canvas.drawPath(path, pinBorderPaint);

    // วาดวงกลมตรงกลาง
    final center = Offset(size.width / 2, size.height / 2 - 10);
    canvas.drawCircle(center, 30, pinPaint);
    canvas.drawCircle(center, 30, pinBorderPaint);

    // วาดไอคอน
    final iconPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final iconPath = Path()
      ..addOval(Rect.fromCircle(center: center, radius: 15));
    
    canvas.drawPath(iconPath, iconPaint);

    // วาดข้อความ
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        center.dy - textPainter.height / 2,
      ),
    );

    // แปลงเป็น Image
    final picture = pictureRecorder.endRecording();
    final image = await picture.toImage(
      size.width.toInt(),
      size.height.toInt(),
    );
    
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  /// โหลด Icon จาก Assets
  static Future<BitmapDescriptor> getMarkerIcon(String assetPath) async {
    final ByteData data = await rootBundle.load(assetPath);
    final ui.Codec codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: 100,
    );
    final ui.FrameInfo fi = await codec.getNextFrame();
    final ByteData? byteData = await fi.image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    
    return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
  }
}
