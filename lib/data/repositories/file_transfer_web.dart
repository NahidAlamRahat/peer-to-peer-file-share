import 'dart:async';
import 'dart:typed_data';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
// ignore: deprecated_member_use
import 'dart:js' as js;
import 'package:flutter/foundation.dart';
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
  void Function()? _onCancel;
  void Function()? _onIncognitoDetected; // Called when SW is not working (e.g., incognito)
  Completer<void>? _swAckCompleter;  // Waits for 'started' ACK from SW

  // Pause/Resume state
  Completer<void>? _pauseCompleter;

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
  Future<void> init(String fileName, {int fileSize = 0}) async {
    // Revoke previous blob URL if any
    if (_blobUrl != null) {
      html.Url.revokeObjectUrl(_blobUrl!);
      _blobUrl = null;
    }
    _fileName = fileName;
    _chunks.clear();
    _streamId = null;
    _useStream = false;

    // ── Wait for SW controller (handles first-load race) ─────────────────────
    // index.html waits for controllerchange before booting Flutter, so this
    // should almost always be instant. But as a safety net we retry up to
    // 1 second in case of a tiny race.
    var sw = html.window.navigator.serviceWorker?.controller;
    if (sw == null) {
      // SW may still be activating (first visit). Poll up to 5 s — by the time
      // the user has scanned QR and connected, it will almost always be ready.
      debugPrint('⏳ [P2P-SW] controller null — waiting up to 5s...');
      for (var i = 0; i < 50 && sw == null; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        sw = html.window.navigator.serviceWorker?.controller;
      }
      if (sw != null) {
        debugPrint('✅ [P2P-SW] controller ready after ${sw == null ? 5000 : 0}ms retry.');
      }
    }

    // Check if Incognito mode in Chrome using our JS helper
    bool isIncognito = false;
    final incognitoCompleter = Completer<bool>();
    if (js.context.hasProperty('checkIncognito')) {
      js.context.callMethod('checkIncognito', [
        (bool result) { incognitoCompleter.complete(result); }
      ]);
      isIncognito = await incognitoCompleter.future;
    }

    if (sw != null && !isIncognito) {
      _useStream = true;
      _streamId = const Uuid().v4();
      _channel = html.MessageChannel();

      final msg = {
        'type': 'start',
        'id': _streamId,
        'filename': _fileName,
        'mimeType': _getMimeType(_fileName),
      };
      
      // Listen for cancel and pause/resume events from the Service Worker
      _channel!.port1.onMessage.listen((event) {
        final dynamic data = event.data;
        if (data is String) {
          if (data == 'started') {
            // SW acknowledged — stream entry is ready
            if (_swAckCompleter != null && !_swAckCompleter!.isCompleted) {
              _swAckCompleter!.complete();
            }
          } else {
             try {
               // We send JSON string from sw.js to avoid Dart JS interop object wrapping issues
               if (data.contains('"type":"cancelled"') || data.contains('"type": "cancelled"')) {
                 // User cancelled from Chrome's download bar → call onCancel → go home
                 _onCancel?.call();
               } else if (data.contains('"type":"pause"') || data.contains('"type": "pause"')) {
                 if (_pauseCompleter == null || _pauseCompleter!.isCompleted) {
                   _pauseCompleter = Completer<void>();
                   debugPrint('⏸ [P2P-ACK] Received pause signal from browser download manager');
                 }
               } else if (data.contains('"type":"resume"') || data.contains('"type": "resume"')) {
                 if (_pauseCompleter != null && !_pauseCompleter!.isCompleted) {
                   _pauseCompleter!.complete();
                   debugPrint('▶ [P2P-ACK] Received resume signal from browser download manager');
                 }
               }
             } catch (_) {}
          }
        }
      });

      // Send start signal
      sw.postMessage(msg, [_channel!.port2]);

      // Wait for SW to acknowledge (max 2s). If timeout = incognito or SW not active.
      _swAckCompleter = Completer<void>();
      try {
        await _swAckCompleter!.future.timeout(const Duration(seconds: 2));
      } catch (_) {
        debugPrint('⚠️ [P2P-SW] Service Worker ACK timeout — likely incognito mode.');
        _useStream = false;
        _swAckCompleter = null;
        _onIncognitoDetected?.call();
        return; // Fall back to blob mode (addChunk will buffer in memory)
      }
      _swAckCompleter = null;

      // Trigger the browser's download manager using a hidden IFrame.
      final iframe = html.IFrameElement()
        ..id = 'pt-download-$_streamId'
        ..style.display = 'none'
        ..src = '/pt-download-stream/$_streamId';
      html.document.body?.append(iframe);
    } else {
      // ── No SW available ───────────────────────────────────────────────────
      if (isIncognito) {
        debugPrint('⚠️ [P2P-SW] Incognito mode detected. Disabling Service Worker streams.');
        _onIncognitoDetected?.call();
        return;
      }

      // SW unavailable (unsupported browser, failed registration, etc.).
      // Blob fallback is only safe for small files (<= 50 MB).
      // For large files it will exhaust browser memory and crash the tab.
      const int blobSafeLimit = 50 * 1024 * 1024; // 50 MB
      if (fileSize > blobSafeLimit) {
        debugPrint('❌ [P2P-SW] SW unavailable and file is ${fileSize ~/ 1048576} MB — cannot safely buffer in RAM.');
        throw Exception(
          'Your browser does not support background downloads required for large files. '
          'Please reload the page and try again, or use Chrome/Edge.',
        );
      }
      debugPrint('⚠️ [P2P-SW] SW unavailable — using in-memory blob fallback (file: ${fileSize ~/ 1024} KB).');
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
      // Anchor was already removed during init, nothing to clean up here
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
  void setOnCancel(void Function() onCancel) {
    _onCancel = onCancel;
  }

  @override
  void setOnIncognitoDetected(void Function() onIncognito) {
    _onIncognitoDetected = onIncognito;
  }

  @override
  Future<void> waitForReady() async {
    if (_pauseCompleter != null && !_pauseCompleter!.isCompleted) {
      await _pauseCompleter!.future;
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

