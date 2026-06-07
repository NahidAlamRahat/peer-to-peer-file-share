import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'file_saver.dart';

P2PFileSaver getFileSaver() => MobileFileSaver();

class MobileFileSaver implements P2PFileSaver {
  IOSink? _sink;
  late File _file;

  @override
  Future<void> init(String fileName) async {
    late Directory dir;
    if (Platform.isAndroid) {
      dir = Directory('/storage/emulated/0/Download');
    } else {
      dir = await getApplicationDocumentsDirectory();
    }

    File savePath = File('${dir.path}/$fileName');
    int counter = 1;
    while (await savePath.exists()) {
      // Use lastIndexOf to correctly handle filenames like "my.doc.v2.pdf"
      final lastDot = fileName.lastIndexOf('.');
      final nameWithoutExt = lastDot > 0 ? fileName.substring(0, lastDot) : fileName;
      final ext = lastDot > 0 ? fileName.substring(lastDot) : '';
      savePath = File('${dir.path}/$nameWithoutExt ($counter)$ext');
      counter++;
    }
    
    _file = savePath;
    _sink = _file.openWrite();
  }

  @override
  void addChunk(Uint8List chunk) {
    _sink?.add(chunk);
  }

  @override
  Future<String> closeAndSave() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
    return _file.path;
  }

  @override
  Future<void> discard() async {
    await _sink?.close();
    _sink = null;
    if (await _file.exists()) {
      await _file.delete();
    }
  }

  @override
  void triggerManualDownload(String path) {
    // No-op for mobile. The file is already safely on disk.
  }

  @override
  void setOnCancel(void Function() onCancel) {
    // Mobile file saver doesn't have a native cancel callback
  }

  @override
  void setOnIncognitoDetected(void Function() onIncognito) {
    // Only used for Web
  }

  @override
  Future<void> waitForReady() async {
    // Mobile writes directly to disk, no backpressure waiting needed
  }
}
