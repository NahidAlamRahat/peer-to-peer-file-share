import 'dart:isolate';
void main() async {
  var uri = await Isolate.resolvePackageUri(Uri.parse('package:file_picker/file_picker.dart'));
  print(uri);
}
