import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_theme.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final MobileScannerController controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: kIsWeb ? null : CameraFacing.back,
  );

  bool _isScanned = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isScanned) return;

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        final String rawValue = barcode.rawValue!;
        // Expected format: https://peertransfer.app/?session=123456...
        if (rawValue.contains('session=')) {
          final uri = Uri.tryParse(rawValue);
          if (uri != null && uri.queryParameters.containsKey('session')) {
            final sessionId = uri.queryParameters['session'];
            if (sessionId != null && sessionId.isNotEmpty) {
              setState(() {
                _isScanned = true;
              });
              controller.stop();
              Navigator.pop(context, sessionId);
              return;
            }
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan QR Code'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [],
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Text(
                    'Scanner Error: ${error.errorCode.name}\n${error.errorDetails?.message ?? "Could not start camera."}',
                    style: const TextStyle(color: Colors.red, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            },
          ),
          // Scanner Overlay
          Container(
            decoration: ShapeDecoration(
              shape: _ScannerOverlayShape(
                borderColor: Theme.of(context).colorScheme.primary,
                borderWidth: 4,
              ),
            ),
          ),
          const Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'Point camera at the sender\'s QR code',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  shadows: [
                    Shadow(color: Colors.black, blurRadius: 4, offset: Offset(0, 1))
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerOverlayShape extends ShapeBorder {
  final Color borderColor;
  final double borderWidth;

  const _ScannerOverlayShape({
    required this.borderColor,
    required this.borderWidth,
  });

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(borderWidth);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => Path();

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final Path path = Path()..addRect(rect);
    final double size = rect.width < rect.height ? rect.width : rect.height;
    final double overlaySize = size * 0.7;
    final Rect overlayRect = Rect.fromCenter(
      center: rect.center,
      width: overlaySize,
      height: overlaySize,
    );
    path.addRect(overlayRect);
    return path..fillType = PathFillType.evenOdd;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final double size = rect.width < rect.height ? rect.width : rect.height;
    final double overlaySize = size * 0.7;
    final Rect overlayRect = Rect.fromCenter(
      center: rect.center,
      width: overlaySize,
      height: overlaySize,
    );

    final Paint borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    final double length = overlaySize * 0.2;

    // Top Left
    canvas.drawLine(overlayRect.topLeft, overlayRect.topLeft + Offset(length, 0), borderPaint);
    canvas.drawLine(overlayRect.topLeft, overlayRect.topLeft + Offset(0, length), borderPaint);

    // Top Right
    canvas.drawLine(overlayRect.topRight, overlayRect.topRight + Offset(-length, 0), borderPaint);
    canvas.drawLine(overlayRect.topRight, overlayRect.topRight + Offset(0, length), borderPaint);

    // Bottom Left
    canvas.drawLine(overlayRect.bottomLeft, overlayRect.bottomLeft + Offset(length, 0), borderPaint);
    canvas.drawLine(overlayRect.bottomLeft, overlayRect.bottomLeft + Offset(0, -length), borderPaint);

    // Bottom Right
    canvas.drawLine(overlayRect.bottomRight, overlayRect.bottomRight + Offset(-length, 0), borderPaint);
    canvas.drawLine(overlayRect.bottomRight, overlayRect.bottomRight + Offset(0, -length), borderPaint);
    
    // Dim background
    final Paint backgroundPaint = Paint()
      ..color = Colors.black.withOpacity(0.6)
      ..style = PaintingStyle.fill;
    
    final Path bgPath = Path()
      ..addRect(rect)
      ..addRect(overlayRect)
      ..fillType = PathFillType.evenOdd;
      
    canvas.drawPath(bgPath, backgroundPaint);
  }

  @override
  ShapeBorder scale(double t) => this;
}
