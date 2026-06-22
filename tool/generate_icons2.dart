import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

void main() async {
  // Load round logo for standard icons and favicon
  final logoBytes = await File('assets/logo.png').readAsBytes();
  final logo = img.decodePng(logoBytes)!;

  // Load square background logo for maskable icons
  final maskableBytes = await File('assets/peertransfer.jpg').readAsBytes();
  final maskableImg = img.decodeJpg(maskableBytes)!;

  // Generate favicon (32x32) from round logo
  final fav = img.copyResize(logo, width: 32, height: 32,
      interpolation: img.Interpolation.cubic);
  await File('web/favicon.png').writeAsBytes(img.encodePng(fav));
  debugPrint('✅ web/favicon.png');

  // Generate Icon-192.png (standard) from round logo
  final icon192 = img.copyResize(logo, width: 192, height: 192,
      interpolation: img.Interpolation.cubic);
  await File('web/icons/Icon-192.png').writeAsBytes(img.encodePng(icon192));
  debugPrint('✅ web/icons/Icon-192.png');

  // Generate Icon-512.png (standard) from round logo
  final icon512 = img.copyResize(logo, width: 512, height: 512,
      interpolation: img.Interpolation.cubic);
  await File('web/icons/Icon-512.png').writeAsBytes(img.encodePng(icon512));
  debugPrint('✅ web/icons/Icon-512.png');

  // Generate Icon-maskable-192.png from square peertransfer.jpg
  final maskable192 = img.copyResize(maskableImg, width: 192, height: 192,
      interpolation: img.Interpolation.cubic);
  await File('web/icons/Icon-maskable-192.png').writeAsBytes(img.encodePng(maskable192));
  debugPrint('✅ web/icons/Icon-maskable-192.png');

  // Generate Icon-maskable-512.png from square peertransfer.jpg
  final maskable512 = img.copyResize(maskableImg, width: 512, height: 512,
      interpolation: img.Interpolation.cubic);
  await File('web/icons/Icon-maskable-512.png').writeAsBytes(img.encodePng(maskable512));
  debugPrint('✅ web/icons/Icon-maskable-512.png');

  debugPrint('\nDone! All icons updated properly.');
}
