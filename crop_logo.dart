import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

void main() {
  final padded = img.decodeImage(File('assets/logo_padded.png').readAsBytesSync());
  final unpadded = img.decodeImage(File('assets/peertransfer.jpg').readAsBytesSync());

  debugPrint('Padded size: \${padded?.width} x \${padded?.height}');
  debugPrint('Unpadded size: \${unpadded?.width} x \${unpadded?.height}');

  // Save the unpadded version as the favicon
  if (unpadded != null) {
    // Resize to 192x192 for icons and 512x512
    final icon192 = img.copyResize(unpadded, width: 192, height: 192);
    final icon512 = img.copyResize(unpadded, width: 512, height: 512);
    
    // Favicon is usually 32x32 or 64x64, let's just make it 64x64
    final favicon = img.copyResize(unpadded, width: 64, height: 64);
    
    File('web/favicon.png').writeAsBytesSync(img.encodePng(favicon));
    File('web/icons/Icon-192.png').writeAsBytesSync(img.encodePng(icon192));
    File('web/icons/Icon-512.png').writeAsBytesSync(img.encodePng(icon512));
    debugPrint('Successfully generated new favicons from unpadded logo.');
  }
}
