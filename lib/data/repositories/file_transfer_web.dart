import 'dart:typed_data';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'file_saver.dart';

P2PFileSaver getFileSaver() => WebFileSaver();

class WebFileSaver implements P2PFileSaver {
  final List<dynamic> _chunks = [];
  late String _fileName;

  String _getMimeType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    const mimeTypes = {
      'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png',
      'gif': 'image/gif', 'webp': 'image/webp', 'svg': 'image/svg+xml',
      'pdf': 'application/pdf', 'txt': 'text/plain',
      'mp4': 'video/mp4', 'mov': 'video/quicktime', 'avi': 'video/x-msvideo',
      'mp3': 'audio/mpeg', 'wav': 'audio/wav',
      'zip': 'application/zip', 'rar': 'application/x-rar-compressed',
      'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    };
    return mimeTypes[ext] ?? 'application/octet-stream';
  }

  @override
  Future<void> init(String fileName) async {
    _fileName = fileName;
    _chunks.clear();
  }

  @override
  void addChunk(Uint8List chunk) {
    // Array of Blob parts inside Javascript, bypassing Dart heap limitations
    _chunks.add(chunk); 
  }

  @override
  Future<String> closeAndSave() async {
    final mimeType = _getMimeType(_fileName);
    final blob = html.Blob(_chunks, mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    
    // Attempt auto-download (might be blocked on mobile)
    html.AnchorElement(href: url)
      ..setAttribute('download', _fileName)
      ..click();
      
    // DO NOT revoke the URL here so the user can manually click a button if blocked
    // html.Url.revokeObjectUrl(url);
    
    // DO NOT clear chunks yet in case they need to re-download. 
    // Wait for discard() or next init().
    
    return url; // Returning the Blob URL to the UI so it can be re-triggered manually
  }

  @override
  void triggerManualDownload(String path) {
    if (path.startsWith('blob:')) {
      html.AnchorElement(href: path)
        ..setAttribute('download', _fileName)
        ..click();
    }
  }

  @override
  Future<void> discard() async {
    _chunks.clear();
  }
}
