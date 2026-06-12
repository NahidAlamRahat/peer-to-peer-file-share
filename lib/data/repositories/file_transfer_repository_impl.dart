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

/// Max single WebRTC chunk size (32 KB).
/// 32KB ensures zero SCTP fragmentation issues on older Androids.
const int _chunkSize = 32768; // 32 KB

/// How many bytes sender sends per "window" before waiting for receiver ACK.
/// 2MB gives maximum throughput on local WiFi (same router / hotspot).
/// The ACK counter prevents the race-condition freeze — window size is safe.
const int _wifiWindowSize = 2097152; // 2 MB

/// Mobile data (TURN relay): tight in-flight limit.
/// Keeps only 8 chunks (256 KB) in flight at once. This guarantees we never 
/// overflow the OS/WebRTC internal buffer on mobile data, which causes silent
/// packet drops and stuck transfers (like sticking at 0.97MB).
const int _mobileMaxInFlight = 8; // 8 × 32 KB = 256 KB max in-flight

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
  // Always emit 0% and 100%; otherwise limit to 10 FPS (100ms) to prevent UI starvation.
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

  // ── Flow control state ──────────────────────────────────────────
  /// Completer that unblocks the sender when the WebRTC native buffer drains.
  Completer<void>? _drainCompleter;

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

  /// Transfer mode sent by sender in metadata: 'wifi' or 'mobile'.
  String _remoteTransferMode = 'wifi';
  /// Window size used for ACK in WiFi mode.
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
    try {
      _webrtcClient.sendDataMessage(
          RTCDataChannelMessage(jsonEncode({'type': 'cancel', 'who': myRole})));
    } catch (e) {
      debugPrint('Failed to send cancel message to peer: $e');
    }
    _unblockSender();
    _fileSaver?.discard();
    _fileSaver = null;
  }

  @override
  void haltTransfer() {
    _isCancelled = true;
    _unblockSender();
    _fileSaver?.discard();
    _fileSaver = null;
  }

  void _unblockSender() {
    if (_drainCompleter != null && !_drainCompleter!.isCompleted) {
      _drainCompleter!.completeError(Exception('Transfer stopped'));
    }
    _drainCompleter = null;
    for (final c in _ackCompleters.values) {
      if (!c.isCompleted) c.completeError('Transfer stopped');
    }
    _ackCompleters.clear();
  }

  @override
  void resetTransferState() {
    _isCancelled = false;
    _drainCompleter = null;
    for (final c in _ackCompleters.values) {
      if (!c.isCompleted) c.completeError('Transfer stopped');
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
    _drainCompleter = null;

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

    // ── Detect actual WebRTC connection path ─────────────────────────────────
    // We use WebRTC's own getStats() instead of connectivity_plus.
    // ICE often connects via 'relay' instantly but upgrades to 'host' (direct P2P)
    // a second later. We poll up to 2 seconds to allow this upgrade to happen
    // before locking in the mode.
    bool isMobile = false;
    try {
      String candidateType = 'unknown';
      for (int i = 0; i < 5; i++) {
        candidateType = await _webrtcClient.getSelectedCandidateType();
        if (candidateType == 'host' || candidateType == 'srflx') {
          break; // Upgraded to direct connection!
        }
        if (i < 4) await Future.delayed(const Duration(milliseconds: 400));
      }

      if (candidateType == 'relay') {
        // TURN relay path: same protocol as mobile data mode
        isMobile = true;
        debugPrint('📡 [P2P] TURN relay detected → Pipeline mode (${_mobileMaxInFlight * _chunkSize ~/ 1024} KB in-flight)');
      } else if (candidateType == 'host' || candidateType == 'srflx') {
        // Direct P2P path: use large window for maximum throughput
        isMobile = false;
        debugPrint('📶 [P2P] Direct P2P ($candidateType) → Window mode (${_wifiWindowSize ~/ (1024 * 1024)} MB windows)');
      } else {
        // Stats not available — fall back to connectivity_plus as best-effort
        final connectivityResult = await Connectivity().checkConnectivity();
        isMobile = connectivityResult.contains(ConnectivityResult.mobile);
        debugPrint(isMobile
            ? '📱 [P2P] Mobile data (connectivity fallback) → Pipeline mode'
            : '📶 [P2P] WiFi (connectivity fallback) → Window mode');
      }
    } catch (e) {
      // Any error → safe fallback using connectivity_plus
      debugPrint('⚠️ [P2P] Connection type detection failed, using connectivity fallback: $e');
      try {
        final connectivityResult = await Connectivity().checkConnectivity();
        isMobile = connectivityResult.contains(ConnectivityResult.mobile);
      } catch (_) {
        isMobile = false; // Last resort: assume WiFi mode
      }
    }

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
            // Tell receiver which protocol to use for ACK-ing
            'transferMode': isMobile ? 'mobile' : 'wifi',
            'windowSize': _wifiWindowSize,     // used in wifi mode
            'maxInFlight': _mobileMaxInFlight, // used in mobile mode
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

      // ── 2. Send data ──────────────────────────────────────────────────────
      int bytesSent = 0;
      int loopCount = 0;

      Future<void> sendChunks(Uint8List bytes, int start, int end) async {
        int offset = start;
        const int maxBufferSize = 256 * 1024; // 256 KB max native buffer size
        
        while (offset < end) {
          if (_isCancelled) return;

          // 1. SCTP NATIVE FLOW CONTROL ─────────────────────────────────────
          // If the native WebRTC buffer is full, wait for it to drain.
          // This entirely prevents dropping chunks and silent connection kills.
          if (_webrtcClient.bufferedAmount > maxBufferSize) {
            _drainCompleter = Completer<void>();
            _webrtcClient.setBufferedAmountLowThreshold(maxBufferSize ~/ 2); // 128 KB
            
            _webrtcClient.onBufferedAmountLow = (int amount) {
              if (_drainCompleter != null && !_drainCompleter!.isCompleted) {
                _drainCompleter!.complete();
              }
            };
            
            try {
              // Wait for buffer to drain or timeout
              await _drainCompleter!.future.timeout(const Duration(seconds: 30));
            } catch (e) {
              if (!_isCancelled) {
                _progressController.addError('Connection to peer is stalled.');
                haltTransfer();
                return;
              }
            }
            _webrtcClient.onBufferedAmountLow = null;
            _drainCompleter = null;
          }

          if (_isCancelled) return;

          // 2. Send chunk
          final sliceEnd = (offset + _chunkSize < end) ? offset + _chunkSize : end;
          final slice = bytes.sublist(offset, sliceEnd);
          _webrtcClient.sendDataMessageBinary(slice);
          
          bytesSent += slice.length;
          offset = sliceEnd;
          loopCount++;

          // 3. Keep UI responsive
          if (loopCount % 16 == 0) {
            await Future.delayed(Duration.zero);
          }

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
        // Wait max 120s for receiver to save (large files can take time)
        await ackCompleter.future.timeout(const Duration(seconds: 120));
        debugPrint('✅ [P2P-ACK] Receiver saved $fileName');
      } on TimeoutException {
        debugPrint('⚠️ [P2P-ACK] EOF ACK timeout (120s) — peer likely gone.');
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

    if (_isCancelled) return;
  }

  // ── RECEIVER ──────────────────────────────────────────────────────────────

  Future<void> _handleDataMessage(RTCDataChannelMessage message) async {
    if (_isCancelled) return;

    if (message.isBinary) {
      // Binary chunk — write to file saver
      _fileSaver?.addChunk(message.binary);
      _receivedBytes += message.binary.length;

      // No application-level ACKs needed anymore; native WebRTC SCTP handles flow control.

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
            _remoteTransferMode = decoded['transferMode'] ?? 'wifi';
            _remoteWindowSize = decoded['windowSize'] ?? _wifiWindowSize;
            _fileSaver = getFileSaver();
            _fileSaver!.setOnCancel(() {
              debugPrint('🛑 [P2P-ACK] Cancelled from Browser UI.');
              cancelTransfer(myRole: 'receiver');
              onSelfCancelled?.call();
            });
            _fileSaver!.setOnIncognitoDetected(() {
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
              '📥 [P2P-ACK] Receiving $_receivingFileName ($_receivingTotalSize bytes) — mode: $_remoteTransferMode',
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

          case 'cancel':
            _isCancelled = true;
            _unblockSender();
            await _fileSaver?.discard();
            _fileSaver = null;
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
