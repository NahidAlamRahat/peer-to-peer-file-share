import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../domain/entities/share_file.dart';

Future<List<ShareFile>?> pickFilesPlatform() async {
  if (Platform.isAndroid) {
    await [
      Permission.storage,
      Permission.photos,
      Permission.videos,
    ].request();
  }

  // ignore: deprecated_member_use
  final result = await FilePicker.pickFiles(
    // ignore: deprecated_member_use
    allowMultiple: true,
  );

  if (result == null || result.files.isEmpty) {
    return null;
  }

  final List<ShareFile> shareFiles = [];
  for (final pf in result.files) {
    final path = pf.path;
    if (path == null) {
      continue;
    }
    // Use File stream directly — avoids deprecated readStream / withReadStream
    final file = File(path);
    shareFiles.add(ShareFile(
      name: pf.name,
      size: pf.size,
      readStream: file.openRead(),
    ));
  }

  return shareFiles.isNotEmpty ? shareFiles : null;
}
