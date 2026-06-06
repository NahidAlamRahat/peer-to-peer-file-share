import 'dart:typed_data';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'package:uuid/uuid.dart';
import 'file_saver.dart';

P2PFileSaver getFileSaver() => WebFileSaver();

class WebFileSaver implements P2PFileSaver {
  final List<dynamic> _chunks = [];
  late String _fileName;
  String? _blobUrl; // Track blob URL for proper cleanup
  
  // Streaming fields
  String? _streamId;
  html.MessageChannel? _channel;
  bool _useStream = false;

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
    // Revoke previous blob URL if any
    if (_blobUrl != null) {
      html.Url.revokeObjectUrl(_blobUrl!);
      _blobUrl = null;
    }
    _fileName = fileName;
    _chunks.clear();
    _streamId = null;
    _useStream = false;

    // Check if ServiceWorker is active
    final sw = html.window.navigator.serviceWorker?.controller;
    if (sw != null) {
      _useStream = true;
      _streamId = const Uuid().v4();
      _channel = html.MessageChannel();

      final msg = {
        'type': 'start',
        'id': _streamId,
        'filename': _fileName,
        'mimeType': _getMimeType(_fileName),
      };
      
      // Send start signal
      sw.postMessage(msg, [_channel!.port2]);

      // Give SW a split second to set up the stream map
      await Future.delayed(const Duration(milliseconds: 100));

      // Trigger the browser's download manager IMMEDIATELY using a hidden iframe
      final iframe = html.IFrameElement()
        ..id = 'pt-download-$_streamId'
        ..style.display = 'none'
        ..src = '/pt-download-stream/$_streamId';
      html.document.body?.append(iframe);
    }
  }

  @override
  void addChunk(Uint8List chunk) {
    if (_useStream && _streamId != null) {
      final sw = html.window.navigator.serviceWorker?.controller;
      if (sw != null) {
        sw.postMessage({
          'type': 'chunk',
          'id': _streamId,
          'data': chunk, 
        });
      }
    } else {
      // Fallback
      _chunks.add(chunk);
    }
  }

  @override
  Future<String> closeAndSave() async {
    if (_useStream && _streamId != null) {
      final sw = html.window.navigator.serviceWorker?.controller;
      if (sw != null) {
        sw.postMessage({
          'type': 'end',
          'id': _streamId,
        });
      }
      // Remove the hidden iframe
      final iframe = html.document.getElementById('pt-download-$_streamId');
      if (iframe != null) iframe.remove();

      return 'streamed'; // Special token so UI knows it's already on disk
    } else {
      // Fallback: use memory blob
      final mimeType = _getMimeType(_fileName);
      final blob = html.Blob(_chunks, mimeType);
      final url = html.Url.createObjectUrlFromBlob(blob);
      _blobUrl = url; 

      html.AnchorElement(href: url)
        ..setAttribute('download', _fileName)
        ..click();

      return url; 
    }
  }

  @override
  void triggerManualDownload(String path) {
    if (path == 'streamed') return; // Already on disk!
    if (path.startsWith('blob:')) {
      html.AnchorElement(href: path)
        ..setAttribute('download', _fileName)
        ..click();
    }
  }

  @override
  Future<void> discard() async {
    if (_useStream && _streamId != null) {
      final sw = html.window.navigator.serviceWorker?.controller;
      if (sw != null) {
        sw.postMessage({
          'type': 'abort',
          'id': _streamId,
        });
      }
    }
    if (_blobUrl != null) {
      html.Url.revokeObjectUrl(_blobUrl!);
      _blobUrl = null;
    }
    _chunks.clear();
  }
}

