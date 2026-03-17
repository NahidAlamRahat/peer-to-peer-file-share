import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

/// Mobile implementation: saves file to storage
Future<void> saveReceivedFile(String fileName, Uint8List bytes) async {
  late Directory dir;
  if (Platform.isAndroid) {
    dir = Directory('/storage/emulated/0/Download');
  } else {
    dir = await getApplicationDocumentsDirectory();
  }

  File savePath = File('${dir.path}/$fileName');
  int counter = 1;
  while (await savePath.exists()) {
    final nameWithoutExt = fileName.split('.').first;
    final ext = fileName.contains('.') ? '.${fileName.split('.').last}' : '';
    savePath = File('${dir.path}/$nameWithoutExt ($counter)$ext');
    counter++;
  }
  await savePath.writeAsBytes(bytes);
}
