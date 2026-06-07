import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/file_chunk_info.dart';
import '../../domain/entities/share_file.dart';
import '../../domain/repositories/file_transfer_repository.dart';
import '../datasources/webrtc_client.dart';
import 'file_saver.dart';

// Web-only download trigger
import 'file_transfer_web.dart'
    if (dart.library.io) 'file_transfer_mobile.dart';

/// How many bytes sender sends per "window" before waiting for receiver ACK.
/// 10MB window → sender is at most 10MB ahead of receiver.
/// We keep this at 10MB because the absolute safe maximum for WebRTC (SCTP buffer limit)
/// on Mobile (especially iOS/Safari) is 16MB. Above that, the connection might drop.
const int _windowSize = 10485760; // 10 MB per window

/// Max single WebRTC chunk size (64 KB).
/// Modern browsers and native WebRTC implementations handle 64KB-256KB perfectly well.
/// 64KB reduces event loop overhead and JS interop crossings by 4x compared to 16KB.
const int _chunkSize = 65536; // 64 KB

int _lastEmitTime = 0;

void _emitProgress({
  required StreamController<FileChunkInfo> controller,
  required String fileId,
  required String fileName,
  required int totalSize,
  required int bytesTransferred,
  required int fileIndex,
  required int totalFiles,
}) {
  if (controller.isClosed) return;

  final now = DateTime.now().millisecondsSinceEpoch;
  // Always emit if it's 0% or 100%, otherwise limit to 10 FPS (100ms) to prevent UI thread starvation!
  // Emitting 800 times a second (every 64KB chunk on 50MB/s connection) destroys WebRTC performance.
  if (bytesTransferred == 0 ||
      bytesTransferred == totalSize ||
      now - _lastEmitTime > 100) {
    _lastEmitTime = now;
    controller.add(
      FileChunkInfo(
        fileId: fileId,
        fileName: fileName,
        totalSize: totalSize,
        bytesTransferred: bytesTransferred,
        fileIndex: fileIndex,
        totalFiles: totalFiles,
      ),
    );
  }
}

class FileTransferRepositoryImpl implements FileTransferRepository {
  final WebRTCClient _webrtcClient;

  final _progressController = StreamController<FileChunkInfo>.broadcast();
  final _fileReceivedController = StreamController<String>.broadcast();

  // ── Sender state ──────────────────────────────────────────────────────────
  bool _isCancelled = false;

  @override
  bool get isCancelled => _isCancelled;

  @override
  Function(String cancellerRole)? onPeerCancelled;

  /// Called when the LOCAL receiver cancels from the browser's native download bar.
  @override
  Function()? onSelfCancelled;

  /// Called when Service Worker is unavailable (e.g., incognito mode).
  @override
  Function()? onSwUnavailableWarning;

  /// Completer that unblocks the sender when receiver ACKs a window.
  Completer<void>? _windowAckCompleter;

  /// Completer that unblocks the sender after receiver saves the full file.
  final Map<String, Completer<void>> _ackCompleters = {};

  // ── Receiver state ────────────────────────────────────────────────────────
  String? _receivingFileId;
  String? _receivingFileName;
  int _receivingTotalSize = 0;
  int _receivedBytes = 0;
  int _receivingFileIndex = 1;
  int _receivingTotalFiles = 1;
  P2PFileSaver? _fileSaver;

  /// The window size we expect per window (sent in metadata).
  int _remoteWindowSize = _windowSize;

  FileTransferRepositoryImpl(this._webrtcClient) {
    _webrtcClient.onDataMessage = _handleDataMessage;
  }

  // ── Public API ────────────────────────────────────────────────────────────

  @override
  Stream<FileChunkInfo> get transferProgressStream =>
      _progressController.stream;

  @override
  Stream<String> get onFileReceivedStream => _fileReceivedController.stream;

  @override
  void saveFileManually(String filePath) {
    _fileSaver?.triggerManualDownload(filePath);
  }

  @override
  /// [myRole] must be 'sender' or 'receiver' so the peer knows who cancelled.
  void cancelTransfer({String myRole = 'sender'}) {
    if (_isCancelled) return; // idempotent
    _isCancelled = true;
    // Tell peer who cancelled so they can show the right message
    try {
      _webrtcClient.sendDataMessage(
          RTCDataChannelMessage(jsonEncode({'type': 'cancel', 'who': myRole})));
    } catch (e) {
      debugPrint('Failed to send cancel message to peer: $e');
    }
    if (_windowAckCompleter != null && !_windowAckCompleter!.isCompleted) {
      _windowAckCompleter!.completeError(Exception('Transfer cancelled'));
    }
    _windowAckCompleter = null;
    for (final c in _ackCompleters.values) {
      if (!c.isCompleted) c.completeError('Transfer cancelled');
    }
    _ackCompleters.clear();
    _fileSaver?.discard();
    _fileSaver = null;
  }

  @override
  void haltTransfer() {
    // Stop locally WITHOUT sending any cancel message to peer.
    // Used when a network error occurs so we don't show a false cancel on peer's screen.
    _isCancelled = true;
    if (_windowAckCompleter != null && !_windowAckCompleter!.isCompleted) {
      _windowAckCompleter!.completeError(Exception('Transfer halted'));
    }
    _windowAckCompleter = null;
    for (final c in _ackCompleters.values) {
      if (!c.isCompleted) c.completeError('Transfer halted');
    }
    _ackCompleters.clear();
    _fileSaver?.discard();
    _fileSaver = null;
  }

  @override
  void resetTransferState() {
    _isCancelled = false;
    _windowAckCompleter = null;
    for (final c in _ackCompleters.values) {
      if (!c.isCompleted) c.completeError('Transfer reset');
    }
    _ackCompleters.clear();
    _resetReceiveState();
  }

  void _resetReceiveState() {
    _receivingFileId = null;
    _receivingFileName = null;
    _receivingTotalSize = 0;
    _receivedBytes = 0;
    _receivingFileIndex = 1;
    _receivingTotalFiles = 1;
    _fileSaver = null;
  }

  // ── SENDER ────────────────────────────────────────────────────────────────

  @override
  Future<void> sendFiles(List<ShareFile> files) async {
    _isCancelled = false;

    // Wait for data channel to open (max 10 s)
    int waitCounter = 0;
    while (_webrtcClient.dataChannelState !=
        RTCDataChannelState.RTCDataChannelOpen) {
      if (_isCancelled) return;
      if (waitCounter > 100) {
        _progressController.addError(
          'Timeout waiting for peer DataChannel to open',
        );
        haltTransfer();
        return;
      }
      await Future.delayed(const Duration(milliseconds: 100));
      waitCounter++;
    }

    // Give receiver 300 ms to attach listeners
    await Future.delayed(const Duration(milliseconds: 300));

    for (int i = 0; i < files.length; i++) {
      if (_isCancelled) break;

      final file = files[i];
      final String fileId = const Uuid().v4();
      final String fileName = file.name;
      final int totalSize = file.size;

      // ── 1. Send metadata ─────────────────────────────────────────────────
      _webrtcClient.sendDataMessage(
        RTCDataChannelMessage(
          jsonEncode({
            'type': 'metadata',
            'fileId': fileId,
            'fileName': fileName,
            'totalSize': totalSize,
            'fileIndex': i + 1,
            'totalFiles': files.length,
            'windowSize': _windowSize, // tell receiver how large each window is
          }),
        ),
      );

      // Emit 0% progress immediately to switch UI to progress screen
      _emitProgress(
        controller: _progressController,
        fileId: fileId,
        fileName: fileName,
        totalSize: totalSize,
        bytesTransferred: 0,
        fileIndex: i + 1,
        totalFiles: files.length,
      );

      // ── 2. Send data in ACK-gated windows ────────────────────────────────
      int bytesSent = 0;
      int windowBytesSent = 0; // bytes sent in the current window

      debugPrint(
        '🚀 [P2P-ACK] Sending $fileName ($totalSize bytes) with ${_windowSize ~/ 1024}KB windows',
      );

      int loopCount = 0;

      Future<void> sendChunks(Uint8List bytes, int start, int end) async {
        int offset = start;
        while (offset < end) {
          if (_isCancelled) return;

          // Backpressure: If WebRTC's internal buffer has more than 10MB, wait.
          // This prevents memory issues when disk read speed is faster than network speed.
          while (_webrtcClient.bufferedAmount > 10 * 1024 * 1024) {
            if (_isCancelled) return;
            await Future.delayed(const Duration(milliseconds: 10));
          }

          final sliceEnd = (offset + _chunkSize < end)
              ? offset + _chunkSize
              : end;
          final slice = bytes.sublist(offset, sliceEnd);

          _webrtcClient.sendDataMessageBinary(slice);
          bytesSent += slice.length;
          offset = sliceEnd;
          loopCount++;

          // Yield to event loop every ~1MB (16 * 64KB) to prevent thread starvation
          // on mobile browsers. If the JS main thread is totally blocked, WebRTC
          // cannot flush UDP sockets and throughput drops to a crawl!
          if (loopCount % 16 == 0) {
            await Future.delayed(Duration.zero);
          }

          // Emit sender progress
          _emitProgress(
            controller: _progressController,
            fileId: fileId,
            fileName: fileName,
            totalSize: totalSize,
            bytesTransferred: bytesSent,
            fileIndex: i + 1,
            totalFiles: files.length,
          );
        }
      }

      if (file.readStream != null) {
        await for (final rawChunk in file.readStream!) {
          if (_isCancelled) break;
          await sendChunks(Uint8List.fromList(rawChunk), 0, rawChunk.length);
        }
      } else if (file.bytes != null) {
        await sendChunks(file.bytes!, 0, file.bytes!.length);
      }

      if (_isCancelled) break;

      // ── 3. Send EOF and wait for receiver to save the file ───────────────
      final ackCompleter = Completer<void>();
      _ackCompleters[fileId] = ackCompleter;

      _webrtcClient.sendDataMessage(
        RTCDataChannelMessage(jsonEncode({'type': 'eof', 'fileId': fileId})),
      );

      try {
        // Wait max 60s for receiver to save the file (it can take time for large files)
        await ackCompleter.future.timeout(const Duration(seconds: 60));
        debugPrint('✅ [P2P-ACK] Receiver saved $fileName');
      } on TimeoutException {
        debugPrint('⚠️ [P2P-ACK] EOF ACK timeout (60s) — peer likely gone.');
        _progressController.addError('Connection to peer was lost while saving the file.');
        haltTransfer();
        return;
      } catch (e) {
        if (!_isCancelled) {
          throw Exception('Receiver did not acknowledge save: $e');
        }
      }
      _ackCompleters.remove(fileId);
    }

    // Cancelled — return quietly. Bloc's CancelTransferEvent already handles UI.
    if (_isCancelled) return;
  }

  // ── RECEIVER ──────────────────────────────────────────────────────────────

  Future<void> _handleDataMessage(RTCDataChannelMessage message) async {
    if (_isCancelled) return;

    if (message.isBinary) {
      // Binary chunk — write to file saver
      _fileSaver?.addChunk(message.binary);
      _receivedBytes += message.binary.length;

      // Emit receiver progress
      _emitProgress(
        controller: _progressController,
        fileId: _receivingFileId ?? '',
        fileName: _receivingFileName ?? '',
        totalSize: _receivingTotalSize,
        bytesTransferred: _receivedBytes,
        fileIndex: _receivingFileIndex,
        totalFiles: _receivingTotalFiles,
      );
    } else {
      try {
        final decoded = jsonDecode(message.text) as Map<String, dynamic>;
        final type = decoded['type'] as String? ?? '';

        switch (type) {
          case 'metadata':
            _resetReceiveState();
            _receivingFileId = decoded['fileId'];
            _receivingFileName = decoded['fileName'];
            _receivingTotalSize = decoded['totalSize'];
            _receivingFileIndex = decoded['fileIndex'] ?? 1;
            _receivingTotalFiles = decoded['totalFiles'] ?? 1;
            _fileSaver = getFileSaver();
            _fileSaver!.setOnCancel(() {
              // Triggered when user cancels download from browser's native UI (Option B)
              debugPrint('🛑 [P2P-ACK] Cancelled from Browser UI.');
              cancelTransfer(myRole: 'receiver');
              onSelfCancelled?.call();
            });
            _fileSaver!.setOnSwUnavailable(() {
              // Service Worker not active — likely incognito mode. Show a warning.
              debugPrint('⚠️ [P2P-ACK] SW unavailable — incognito mode? Falling back to blob download.');
              onSwUnavailableWarning?.call();
            });
            await _fileSaver!.init(_receivingFileName ?? 'file');
            
            // Emit 0% progress immediately so receiver UI switches to progress screen
            _emitProgress(
              controller: _progressController,
              fileId: _receivingFileId ?? '',
              fileName: _receivingFileName ?? '',
              totalSize: _receivingTotalSize,
              bytesTransferred: 0,
              fileIndex: _receivingFileIndex,
              totalFiles: _receivingTotalFiles,
            );
            
            debugPrint(
              '📥 [P2P-ACK] Receiving $_receivingFileName ($_receivingTotalSize bytes)',
            );
            break;

          case 'eof':
            // All data received — save file and notify sender
            if (_fileSaver != null) {
              final savedPath = await _fileSaver!.closeAndSave();
              _fileReceivedController.add(savedPath);
              _fileSaver = null;
              _webrtcClient.sendDataMessage(
                RTCDataChannelMessage(
                  jsonEncode({'type': 'ack', 'fileId': decoded['fileId']}),
                ),
              );
              debugPrint('💾 [P2P-ACK] File saved. Sent final ACK.');
            }
            break;

          case 'ack':
            // Final save ACK — unblock sender's post-EOF wait
            final fileId = decoded['fileId'] as String?;
            if (fileId != null) _ackCompleters[fileId]?.complete();
            break;

          case 'cancel':
            _isCancelled = true;
            _windowAckCompleter?.complete();
            _windowAckCompleter = null;
            await _fileSaver?.discard();
            _fileSaver = null;
            // Notify bloc so the PEER (not canceller) sees a message
            final who = decoded['who'] as String? ?? 'peer';
            onPeerCancelled?.call(who);
            debugPrint('🛑 [P2P-ACK] Cancelled by $who.');
            break;

          default:
            debugPrint('⚠️ [P2P-ACK] Unknown message type: $type');
        }
      } catch (e) {
        debugPrint('❌ [P2P-ACK] Error handling message: $e');
        if (!_progressController.isClosed) {
          _progressController.addError('System Error: $e');
        }
      }
    }
  }
}
