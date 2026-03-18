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
      final nameWithoutExt = fileName.split('.').first;
      final ext = fileName.contains('.') ? '.${fileName.split('.').last}' : '';
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
}
