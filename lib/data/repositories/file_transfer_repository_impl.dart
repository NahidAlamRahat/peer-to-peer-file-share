import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
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
const int _wifiWindowSize = 262144; // 256 KB (safe for low latency)
const int _mobileWindowSize = 2097152; // 2 MB (for high latency TURN)

/// Max single WebRTC chunk size (32 KB).
/// 32KB ensures zero SCTP fragmentation issues on older Androids.
const int _chunkSize = 32768; // 32 KB

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

  /// Called when Chrome Incognito mode is detected.
  @override
  Function()? onIncognitoDetected;

  /// Completer that unblocks the sender when receiver ACKs a window.
  Completer<void>? _windowAckCompleter;

  /// Completer that unblocks the sender after receiver saves the full file.
  final Map<String, Completer<void>> _ackCompleters = {};

  // ── Receiver state ────────────────────────────────────────────────────────
  String? _receivingFileId;
  String? _receivingFileName;
  int _receivingTotalSize = 0;
  int _receivedBytes = 0;
  int _lastWindowAckBytes = 0;
  int _receivingFileIndex = 1;
  int _receivingTotalFiles = 1;
  P2PFileSaver? _fileSaver;

  /// The window size we expect per window (sent in metadata).
  int _remoteWindowSize = _wifiWindowSize;

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
    _lastWindowAckBytes = 0;
    _receivingFileIndex = 1;
    _receivingTotalFiles = 1;
    _fileSaver = null;
  }

  // ── SENDER ────────────────────────────────────────────────────────────────

  @override
  Future<void> sendFiles(List<ShareFile> files) async {
    _isCancelled = false;

    // Determine optimal window size based on connectivity
    int activeWindowSize = _wifiWindowSize;
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.mobile)) {
        activeWindowSize = _mobileWindowSize;
        debugPrint('📱 [P2P] Mobile data detected. Using 2MB window size.');
      } else {
        debugPrint('📶 [P2P] WiFi/Other detected. Using 256KB window size.');
      }
    } catch (e) {
      debugPrint('Error checking connectivity: $e');
    }

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
            'windowSize': activeWindowSize, // tell receiver how large each window is
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
        '🚀 [P2P-ACK] Sending $fileName ($totalSize bytes) with ${activeWindowSize ~/ 1024}KB windows',
      );

      int loopCount = 0;

      Future<void> sendChunks(Uint8List bytes, int start, int end) async {
        int offset = start;
        while (offset < end) {
          if (_isCancelled) return;

          final sliceEnd = (offset + _chunkSize < end)
              ? offset + _chunkSize
              : end;
          final slice = bytes.sublist(offset, sliceEnd);

          _webrtcClient.sendDataMessageBinary(slice);
          bytesSent += slice.length;
          windowBytesSent += slice.length;
          offset = sliceEnd;
          loopCount++;

          // Yield to event loop every ~2MB (16 × 128KB) to prevent thread
          // starvation on mobile browsers. Each sendDataMessageBinary() is a
          // synchronous Dart→JS interop call (~0.5-1ms on mobile). 16 calls =
          // ~8-16ms of blocking — safe. Going higher risks jank on slow phones.
          if (loopCount % 16 == 0) {
            await Future.delayed(Duration.zero);
          }

          // Emit sender progress (actual bytes sent over network)
          _emitProgress(
            controller: _progressController,
            fileId: fileId,
            fileName: fileName,
            totalSize: totalSize,
            bytesTransferred: bytesSent,
            fileIndex: i + 1,
            totalFiles: files.length,
          );

          if (windowBytesSent >= activeWindowSize) {
            // Force emit UI before waiting for ACK so user sees progress
            _lastEmitTime = 0; 
            _emitProgress(
              controller: _progressController,
              fileId: fileId,
              fileName: fileName,
              totalSize: totalSize,
              bytesTransferred: bytesSent,
              fileIndex: i + 1,
              totalFiles: files.length,
            );

            _windowAckCompleter = Completer<void>();
            try {
              await _windowAckCompleter!.future.timeout(const Duration(seconds: 15));
            } catch (e) {
              if (!_isCancelled) {
                _progressController.addError('Connection to peer was lost.');
                haltTransfer();
                return;
              }
            }
            windowBytesSent = 0;
          }
        }
      }

      if (file.readStream != null) {
        await for (final rawChunk in file.readStream!) {
          if (_isCancelled) break;
          // Flutter file streams return Uint8List — cast avoids an unnecessary
          // memory copy. Fallback to fromList only for non-Uint8List streams.
          final chunkBytes = rawChunk is Uint8List
              ? rawChunk
              : Uint8List.fromList(rawChunk);
          await sendChunks(chunkBytes, 0, chunkBytes.length);
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

      // Send ACK if window is full
      if (_receivedBytes - _lastWindowAckBytes >= _remoteWindowSize) {
        _lastWindowAckBytes = _receivedBytes;
        _webrtcClient.sendDataMessage(
          RTCDataChannelMessage(jsonEncode({'type': 'ack-window'})),
        );
      }

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
            _fileSaver!.setOnIncognitoDetected(() {
              // Incognito mode detected. Abort transfer and notify UI.
              debugPrint('⚠️ [P2P-ACK] Incognito mode detected. Aborting transfer.');
              cancelTransfer(myRole: 'receiver');
              onIncognitoDetected?.call();
            });
            await _fileSaver!.init(_receivingFileName ?? 'file', fileSize: _receivingTotalSize);
            
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
              
              if (_receivingFileIndex >= _receivingTotalFiles) {
                _fileReceivedController.add(savedPath);
              }
              
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

          case 'ack-window':
            // Unblock sender's window wait
            if (_windowAckCompleter != null && !_windowAckCompleter!.isCompleted) {
              _windowAckCompleter!.complete();
            }
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
