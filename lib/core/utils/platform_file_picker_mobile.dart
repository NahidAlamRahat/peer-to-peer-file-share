import 'dart:io';
import 'package:flutter/foundation.dart';
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
    allowMultiple: true,
    withReadStream: true,
  );

  if (result == null || result.files.isEmpty) {
    return null;
  }

  final List<ShareFile> shareFiles = [];
  for (final pf in result.files) {
    final stream = pf.readStream;
    if (stream == null) {
      debugPrint('⚠️ [UI] Skipping ${pf.name} — readStream is null.');
      continue;
    }
    shareFiles.add(ShareFile(
      name: pf.name,
      size: pf.size,
      readStream: stream,
    ));
  }

  return shareFiles.isNotEmpty ? shareFiles : null;
}
