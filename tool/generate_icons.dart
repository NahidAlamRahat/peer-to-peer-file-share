import 'dart:io';
import 'package:image/image.dart' as img;

void main() async {
  // Load source logo (already circular)
  final logoBytes = await File('assets/logo.png').readAsBytes();
  final logo = img.decodePng(logoBytes)!;

  // Ensure corners are transparent (apply circular mask)
  final masked = _applyCircularMask(logo);

  // Generate favicon (32x32)
  final fav = img.copyResize(masked, width: 32, height: 32,
      interpolation: img.Interpolation.cubic);
  await File('web/favicon.png').writeAsBytes(img.encodePng(fav));
  print('✅ web/favicon.png');

  // Generate Icon-192.png (standard)
  final icon192 = img.copyResize(masked, width: 192, height: 192,
      interpolation: img.Interpolation.cubic);
  await File('web/icons/Icon-192.png').writeAsBytes(img.encodePng(icon192));
  print('✅ web/icons/Icon-192.png');

  // Generate Icon-512.png (standard)
  final icon512 = img.copyResize(masked, width: 512, height: 512,
      interpolation: img.Interpolation.cubic);
  await File('web/icons/Icon-512.png').writeAsBytes(img.encodePng(icon512));
  print('✅ web/icons/Icon-512.png');

  // Maskable icons: add 20% padding so the icon fills the safe zone
  // The safe zone is an 80%-diameter inscribed circle of the full image.
  // To fill the safe zone fully, the logo should cover ~80% of the square.
  final maskable192 = _makeMaskable(masked, 192);
  await File('web/icons/Icon-maskable-192.png').writeAsBytes(img.encodePng(maskable192));
  print('✅ web/icons/Icon-maskable-192.png');

  final maskable512 = _makeMaskable(masked, 512);
  await File('web/icons/Icon-maskable-512.png').writeAsBytes(img.encodePng(maskable512));
  print('✅ web/icons/Icon-maskable-512.png');

  print('\nDone! All icons updated.');
}

/// Apply a circular mask to make corners transparent.
img.Image _applyCircularMask(img.Image src) {
  final size = src.width < src.height ? src.width : src.height;
  final result = img.Image(width: size, height: size,
      numChannels: 4, format: img.Format.uint8);

  final cx = size / 2.0;
  final cy = size / 2.0;
  final r = size / 2.0;

  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      final dx = x - cx;
      final dy = y - cy;
      if (dx * dx + dy * dy <= r * r) {
        final srcX = (x * src.width / size).floor().clamp(0, src.width - 1);
        final srcY = (y * src.height / size).floor().clamp(0, src.height - 1);
        final pixel = src.getPixel(srcX, srcY);
        result.setPixelRgba(x, y, pixel.r.toInt(), pixel.g.toInt(),
            pixel.b.toInt(), 255);
      } else {
        result.setPixelRgba(x, y, 0, 0, 0, 0); // transparent
      }
    }
  }
  return result;
}

/// Create a maskable icon: dark background square + logo centred at 80% size.
img.Image _makeMaskable(img.Image logo, int size) {
  final result = img.Image(width: size, height: size,
      numChannels: 4, format: img.Format.uint8);

  // Fill with dark background (#09090b)
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      result.setPixelRgba(x, y, 9, 9, 11, 255);
    }
  }

  // Logo at 80% of size (fills the safe zone)
  final logoSize = (size * 0.80).round();
  final offset = (size - logoSize) ~/ 2;
  final scaled = img.copyResize(logo, width: logoSize, height: logoSize,
      interpolation: img.Interpolation.cubic);

  img.compositeImage(result, scaled, dstX: offset, dstY: offset);
  return result;
}
