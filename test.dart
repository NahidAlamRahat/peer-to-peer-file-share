import 'dart:isolate';
import 'package:flutter/foundation.dart';

void main() async {
  var uri = await Isolate.resolvePackageUri(Uri.parse('package:file_picker/file_picker.dart'));
  debugPrint(uri?.toString());
}
