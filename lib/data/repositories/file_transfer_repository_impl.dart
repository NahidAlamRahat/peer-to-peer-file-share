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

/// WiFi chunk size (256 KB).
/// Larger chunks drastically reduce per-chunk overhead on fast links.
/// Still below SCTP max message size — no fragmentation issues.
const int _wifiChunkSize = 262144; // 256 KB

/// Mobile data / TURN relay chunk size (16 KB).
const int _mobileChunkSize = 16384; // 16 KB

/// Application-level flow control window sizes.
/// We MUST use this because flutter_webrtc's native bufferedAmount is unreliable on mobile,
/// causing the sender to flood the memory and crash the transfer.
const int _wifiWindowSize = 4194304; // 4 MB for local WiFi
const int _mobileWindowSize = 524288; // 512 KB for TURN Relay

int _lastEmitTime = 0;

void _emitProgress({
  required StreamController<FileChunkInfo> controller,
  required String fileId,
  required String fileName,
  required int totalSize,
  required int bytesTransferred,
  required int fileIndex,
  required int totalFiles,
  bool force = false,
}) {
  if (controller.isClosed) return;

  final now = DateTime.now().millisecondsSinceEpoch;
  // Always emit 0% and 100%, or when forced, or limit to 10 FPS (100ms) to prevent UI starvation.
  if (force ||
      bytesTransferred == 0 ||
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
  int _receivingFileIndex = 1;
  int _receivingTotalFiles = 1;
  P2PFileSaver? _fileSaver;

  /// Transfer mode sent by sender in metadata: 'wifi' or 'mobile'.
  /// Kept for debug logging only.
  String _remoteTransferMode = 'wifi';
  int _remoteWindowSize = 4194304;
  int _windowBytesReceived = 0;
  Completer<void>? _windowAckCompleter;

  /// True while receiver is awaiting fileSaver.init() — binary chunks
  /// that arrive during this window are queued here and replayed after init.
  bool _isInitializing = false;
  final List<Uint8List> _initQueue = [];

  /// Receiver-side stall watchdog.
  /// Restarted on every binary chunk arrival. If no chunk arrives within
  /// 15 s while a transfer is active, the relay/connection is stuck and
  /// we surface a clear error instead of hanging silently.
  Timer? _receiveWatchdog;

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
    _receiveWatchdog?.cancel();
    _receiveWatchdog = null;
    _fileSaver?.discard();
    _fileSaver = null;
  }

  @override
  void haltTransfer() {
    _isCancelled = true;
    _unblockSender();
    _receiveWatchdog?.cancel();
    _receiveWatchdog = null;
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
    _windowAckCompleter?.completeError(Exception('Transfer stopped'));
    _windowAckCompleter = null;
  }

  @override
  void resetTransferState() {
    _isCancelled = false;
    _drainCompleter = null;
    _windowAckCompleter = null;
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
    _receivingFileIndex = 1;
    _receivingTotalFiles = 1;
    _windowBytesReceived = 0;
    _fileSaver = null;
    _isInitializing = false;
    _initQueue.clear();
    _receiveWatchdog?.cancel();
    _receiveWatchdog = null;
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
        debugPrint('📡 [P2P] TURN relay detected → App-Level Windowing (${_mobileWindowSize ~/ 1024} KB windows)');
      } else if (candidateType == 'host' || candidateType == 'srflx') {
        // Direct P2P path: use large window for maximum throughput
        isMobile = false;
        debugPrint('📶 [P2P] Direct P2P ($candidateType) → App-Level Windowing (${_wifiWindowSize ~/ (1024 * 1024)} MB windows)');
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
            'transferMode': isMobile ? 'mobile' : 'wifi',
            'windowSize': isMobile ? _mobileWindowSize : _wifiWindowSize,
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
      int bytesSinceLastAck = 0;
      int loopCount = 0;
      
      // Initialize the completer before the loop so early ACKs aren't dropped
      _windowAckCompleter = Completer<void>();

      // Choose chunk size based on connection type:
      // WiFi/direct P2P → 256 KB chunks for maximum throughput.
      // Mobile/TURN relay → 32 KB chunks to avoid relay buffer overflow.
      final int chunkSize = isMobile ? _mobileChunkSize : _wifiChunkSize;

      // Drain wait timeout:
      //   Mobile/TURN relay → 10 s: relay congestion should be detected fast
      //   WiFi/direct P2P  → 30 s: large local buffers can legitimately be slow
      final Duration drainTimeout = isMobile
          ? const Duration(seconds: 10)
          : const Duration(seconds: 30);

      Future<void> sendChunks(Uint8List bytes, int start, int end) async {
        int offset = start;

        while (offset < end) {
          if (_isCancelled) return;

          // ── Guard: halt immediately if data channel has closed ───────────
          // Without this check, sends are silently dropped and the sender
          // keeps looping until a 120 s EOF-ACK timeout causes a stall.
          if (_webrtcClient.dataChannelState !=
              RTCDataChannelState.RTCDataChannelOpen) {
            if (!_isCancelled) {
              debugPrint(
                  '⚠️ [P2P] Data channel closed mid-transfer — halting.');
              _progressController
                  .addError('Connection to peer was lost during transfer.');
              haltTransfer();
            }
            return;
          }

          // 1. APPLICATION-LEVEL FLOW CONTROL (WINDOW ACKS) ───────────────
          // flutter_webrtc's native bufferedAmount is unreliable on mobile,
          // so we use an explicit application-level ACK system to prevent
          // OOM crashes and relay floods.
          final int windowSize = isMobile ? _mobileWindowSize : _wifiWindowSize;
          if (bytesSinceLastAck >= windowSize) {
            // Force UI update before blocking
            _emitProgress(
              controller: _progressController,
              fileId: fileId,
              fileName: fileName,
              totalSize: totalSize,
              bytesTransferred: bytesSent,
              fileIndex: i + 1,
              totalFiles: files.length,
              force: true,
            );

            try {
              // Wait for the receiver to send 'ack_window' indicating it has
              // processed the current window of bytes.
              await _windowAckCompleter!.future.timeout(drainTimeout);
            } catch (e) {
              if (!_isCancelled) {
                _progressController.addError('Connection to peer is stalled (Window ACK timeout).');
                haltTransfer();
                return;
              }
            }
            
            // Create a new completer for the NEXT window
            _windowAckCompleter = Completer<void>();
            
            // It's possible slice.length pushed bytesSinceLastAck past windowSize,
            // so we subtract windowSize to accurately track remainder.
            bytesSinceLastAck -= windowSize;
          }

          if (_isCancelled) return;

          // 2. Send chunk
          final sliceEnd =
              (offset + chunkSize < end) ? offset + chunkSize : end;
          final slice = bytes.sublist(offset, sliceEnd);
          _webrtcClient.sendDataMessageBinary(slice);

          bytesSent += slice.length;
          bytesSinceLastAck += slice.length;
          offset = sliceEnd;
          loopCount++;

          // 3. Keep UI responsive (yield every 32 chunks)
          if (loopCount % 32 == 0) {
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
      // If fileSaver is still initializing (await init() hasn't returned yet),
      // queue the chunk so it is NOT silently dropped.
      if (_isInitializing) {
        _initQueue.add(message.binary);
        _receivedBytes += message.binary.length;
        // Watchdog not needed during init — data IS arriving, just queued.
        return;
      }

      // ── Receiver-side stall watchdog ─────────────────────────────────────
      // Reset the 15 s countdown on every chunk that arrives.
      // If no chunk arrives for 15 s while the file is still incomplete,
      // the sender/relay is stuck and we surface a clear error.
      _receiveWatchdog?.cancel();
      if (_receivedBytes + message.binary.length < _receivingTotalSize) {
        _receiveWatchdog = Timer(const Duration(seconds: 15), () {
          if (!_isCancelled && !_progressController.isClosed) {
            debugPrint('⏰ [P2P-RX] No data for 15 s — receiver watchdog fired.');
            _progressController.addError(
              'Data stopped arriving. The connection or relay may be congested. '
              'Please try again.',
            );
            haltTransfer();
          }
        });
      }

      // Binary chunk — write to file saver
      _fileSaver?.addChunk(message.binary);
      _receivedBytes += message.binary.length;
      _windowBytesReceived += message.binary.length;

      // Send window ACK back to sender to unblock them
      if (_windowBytesReceived >= _remoteWindowSize) {
        _windowBytesReceived = 0;
        _webrtcClient.sendDataMessage(RTCDataChannelMessage(jsonEncode({'type': 'ack_window'})));
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
            _remoteTransferMode = decoded['transferMode'] ?? 'wifi';
            
            // Backwards compatibility for older senders that didn't send windowSize
            if (decoded['windowSize'] != null) {
              _remoteWindowSize = decoded['windowSize'];
            } else {
              _remoteWindowSize = _remoteTransferMode == 'mobile' ? 524288 : 4194304;
            }
            
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

            // Guard: mark initializing so any binary chunks that arrive
            // during the async init() call are queued, not silently dropped.
            _isInitializing = true;
            await _fileSaver!.init(_receivingFileName ?? 'file', fileSize: _receivingTotalSize);
            _isInitializing = false;

            // Drain any chunks that arrived during init()
            if (_initQueue.isNotEmpty) {
              debugPrint('📦 [P2P-ACK] Draining ${_initQueue.length} queued chunks from init window.');
              for (final queued in _initQueue) {
                _fileSaver?.addChunk(queued);
                _windowBytesReceived += queued.length;
                if (_windowBytesReceived >= _remoteWindowSize) {
                  _windowBytesReceived = 0;
                  _webrtcClient.sendDataMessage(RTCDataChannelMessage(jsonEncode({'type': 'ack_window'})));
                }
              }
              _initQueue.clear();
            }

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
            // All data received — cancel watchdog, save file, notify sender
            _receiveWatchdog?.cancel();
            _receiveWatchdog = null;
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

          case 'ack_window':
            // Window ACK — unblock sender's chunk loop
            if (_windowAckCompleter != null && !_windowAckCompleter!.isCompleted) {
              _windowAckCompleter!.complete();
            }
            break;

          case 'cancel':
            _isCancelled = true;
            _receiveWatchdog?.cancel();
            _receiveWatchdog = null;
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
