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

// ── Chunk sizes ──────────────────────────────────────────────────────────────
/// We now use a single chunk size (16 KB) for all transfers to balance overhead and speed.
const int _chunkSize = 16384; // 16 KB

// ── Window sizes ─────────────────────────────────────────────────────────────
/// Unified Window: 64KB. To prevent Android WebRTC receivers from crashing due
/// to OS UDP buffer overflows (limit ~212KB), ALL senders (including Web/PC) 
/// must use a conservative 64KB window. This ensures 100% stability across all
/// platforms (Web-to-App, App-to-App).
const int _unifiedWindowSize = 65536; // 64 KB

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
  String _remoteTransferMode = 'wifi';
  int _remoteWindowSize = 8388608;
  int _windowBytesReceived = 0;
  int _lastRxProgressPingMs = 0;

  /// Window ACK completer — created fresh by ack_window handler (race-free).
  Completer<void>? _windowAckCompleter;

  /// True while receiver is awaiting fileSaver.init() — binary chunks
  /// that arrive during this window are queued here and replayed after init.
  bool _isInitializing = false;
  final List<Uint8List> _initQueue = [];

  // ── Serial message processing queue ──────────────────────────────────────
  // Problem: _handleDataMessage is async. When waitForReady() yields the event
  // loop (browser pause signal), the next DataChannel message (e.g. EOF) can
  // be processed immediately — BEFORE the current binary chunk's addChunk()
  // has been called. This causes _fileSaver to become null mid-chunk, losing
  // the last bytes and causing the browser to show "Cancelled".
  //
  // Fix: all incoming messages are serialised through this queue. Each message
  // is fully processed (including any awaits) before the next one starts.
  final List<RTCDataChannelMessage> _msgQueue = [];
  bool _isProcessingMsg = false;

  /// Receiver-side stall watchdog.
  /// Restarted on every binary chunk arrival with an adaptive timeout
  /// calculated from the measured receive speed:
  ///   timeout = clamp(chunkSize / speed × 4, 20 s, 120 s)
  /// At 10 KB/s → ~26 s. At 50 KB/s → ~20 s. Falls back to 90 s if unknown.
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
        RTCDataChannelMessage(jsonEncode({'type': 'cancel', 'who': myRole})),
      );
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
    _windowAckCompleter?.completeError(Exception('Transfer stopped'));
    _windowAckCompleter = null;
  }

  @override
  void resetTransferState() {
    _isCancelled = false;
    _drainCompleter = null;
    // ✅ Create a fresh completer — next session is ready immediately.
    // Do NOT leave null: sender loop expects it to exist before the first window fill.
    _windowAckCompleter = Completer<void>();
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
    // Drain the serial queue — any in-flight messages after cancel are irrelevant.
    // _msgQueue.clear(); // REMOVED: This causes chunks of the next file to be deleted if they arrive back-to-back with metadata!
    // NOTE: _isProcessingMsg is intentionally NOT reset here.
    // If a message is mid-processing it will see _isCancelled=true and exit early.
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

      final connectivityResult = await Connectivity().checkConnectivity();
      final bool onMobileNetwork = !connectivityResult.contains(ConnectivityResult.wifi) && 
                                   connectivityResult.contains(ConnectivityResult.mobile);

      // To maximize stability on Mobile-to-Mobile transfers, we ALWAYS use
      // the mobile window (64 KB). The Android WebRTC stack often drops connections
      // if we push 256 KB bursts, even on fast WiFi.
      isMobile = !kIsWeb; // If it's a mobile app, always use the safer profile.

      debugPrint(
        '📱 [P2P] Platform Detected → Safe Profile (${_unifiedWindowSize ~/ 1024} KB window)',
      );
    } catch (e) {
      // Any error → safe fallback using connectivity_plus
      debugPrint(
        '⚠️ [P2P] Connection type detection failed, using connectivity fallback: $e',
      );
      try {
        final connectivityResult = await Connectivity().checkConnectivity();
        isMobile = !connectivityResult.contains(ConnectivityResult.wifi) && 
                   connectivityResult.contains(ConnectivityResult.mobile);
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
            'transferMode': 'safe',
            'windowSize': _unifiedWindowSize,
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

      // Sender-side speed tracking (for debug logging only).
      // Helps diagnose if SCTP back-pressure is slowing us down.
      int txLastLogBytes = 0;
      int txLastLogMs = DateTime.now().millisecondsSinceEpoch;

      // Initialize the completer ONCE before the loop so early ACKs aren't dropped.
      // ack_window handler will create the NEXT completer — no race condition.
      _windowAckCompleter = Completer<void>();

      final int chunkSize = _chunkSize;

      // ── Inner send loop — Pipeline + Adaptive Backpressure ────────────────
      Future<void> sendChunks(Uint8List bytes, int start, int end) async {
        int offset = start;

        while (offset < end) {
          if (_isCancelled) return;

          // ── Guard 1: Data channel must be open ───────────────────────────
          if (_webrtcClient.dataChannelState !=
              RTCDataChannelState.RTCDataChannelOpen) {
            if (!_isCancelled) {
              debugPrint(
                '⚠️ [P2P] Data channel closed mid-transfer — halting.',
              );
              _progressController.addError(
                'Connection to peer was lost during transfer.',
              );
              haltTransfer();
            }
            return;
          }

          final int windowSize = _unifiedWindowSize;
          if (bytesSinceLastAck >= windowSize) {
            debugPrint(
              '⏸ [P2P-TX] Window full — sent ${bytesSinceLastAck ~/ 1024} KB, waiting for ack_window...',
            );

            try {
              // 120-second timeout — if receiver never acks, it's dead (browser closed, etc.)
              await _windowAckCompleter!.future
                  .timeout(const Duration(seconds: 120));
            } on TimeoutException {
              if (!_isCancelled) {
                debugPrint('⏰ [P2P-TX] ack_window timeout — receiver unresponsive.');
                _progressController.addError(
                  'Receiver stopped responding. Please try again.',
                );
                haltTransfer();
              }
              return;
            } catch (e) {
              if (!_isCancelled) {
                _progressController.addError(
                  'Receiver is not responding (Window ACK timeout).',
                );
                haltTransfer();
                return;
              }
              return;
            }

            bytesSinceLastAck = 0;
            _windowAckCompleter = Completer<void>();

            if (_webrtcClient.dataChannelState !=
                RTCDataChannelState.RTCDataChannelOpen) {
              if (!_isCancelled) {
                _progressController.addError(
                  'Connection to peer was lost during transfer.',
                );
                haltTransfer();
              }
              return;
            }
          }

          if (_isCancelled) return;

          // ── Send chunk ──────────────────────────────────────────────────
          final sliceEnd = (offset + _chunkSize < end)
              ? offset + _chunkSize
              : end;
          final slice = bytes.sublist(offset, sliceEnd);

          // Wait for SCTP send buffer to drain if it's filling up.
          // Without this, Android WebRTC overflows its 16MB SCTP buffer
          // and crashes the data channel mid-transfer.
          // Note: on Web, bufferedAmount is reliable; on Android it may return 0,
          // so this is a best-effort guard that still helps when the value is reported.
          try {
            await _webrtcClient.waitForBufferDrain();
          } catch (_) {
            // Disposed or cancelled — exit immediately
            return;
          }
          if (_isCancelled) return;

          _webrtcClient.sendDataMessageBinary(slice);

          bytesSent += slice.length;
          bytesSinceLastAck += slice.length;
          offset = sliceEnd;
          loopCount++;

          // ── Timing & Throttling ─────────────────────────────────────────
          // Always yield every chunk to the Dart event loop.
          // This ensures:
          //  1. ICE keepalive (STUN ping) packets are never blocked.
          //  2. ack_window messages from receiver are processed promptly.
          //  3. Android OS networking stack has time to flush UDP buffers.
          // Unified 4ms delay + 16KB chunk = ~4 MB/s. Safe for ALL platforms.
          await Future.delayed(const Duration(milliseconds: 4));

          // Calculate and log speed occasionally
          if (loopCount % 8 == 0) {
            final nowMs = DateTime.now().millisecondsSinceEpoch;
            final elapsedMs = nowMs - txLastLogMs;
            if (elapsedMs > 1000) {
              // Log at most once per second
              final speedKbps =
                  ((bytesSent - txLastLogBytes) / elapsedMs * 1000) / 1024;
              debugPrint(
                '🚀 [P2P-TX] Sender speed: ${speedKbps.toStringAsFixed(1)} KB/s',
              );
              txLastLogMs = nowMs;
              txLastLogBytes = bytesSent;
            }
          }
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

      // Handle any pending un-ACKed partial window before EOF.
      // If the final window didn't reach the threshold, the completer is still
      // pending. Complete it so cleanup is clean (ack_window may never arrive
      // if the last window was partial).
      if (bytesSinceLastAck > 0 && bytesSinceLastAck < _unifiedWindowSize) {
        if (_windowAckCompleter != null && !_windowAckCompleter!.isCompleted) {
          _windowAckCompleter!.complete();
        }
      }

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
        _progressController.addError(
          'Connection to peer was lost while saving the file.',
        );
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

  // ── Public entry point: enqueue and drain serially ──────────────────────
  Future<void> _handleDataMessage(RTCDataChannelMessage message) async {
    _msgQueue.add(message);
    if (_isProcessingMsg) return; // Another message is already being processed
    _isProcessingMsg = true;
    while (_msgQueue.isNotEmpty) {
      final msg = _msgQueue.removeAt(0);
      await _processDataMessage(msg);
    }
    _isProcessingMsg = false;
  }

  // ── Actual processing (called one at a time — strictly ordered) ───────────
  Future<void> _processDataMessage(RTCDataChannelMessage message) async {
    if (_isCancelled) return;

    if (message.isBinary) {
      try {
        // If fileSaver is still initializing (await init() hasn't returned yet),
        // queue the chunk so it is NOT silently dropped.
        // ✅ Do NOT increment _receivedBytes here — only during drain to avoid double-count.
        if (_isInitializing) {
          _initQueue.add(message.binary);
          // Watchdog not needed during init — data IS arriving, just queued.
          return;
        }

        // Binary chunk — write to file saver
        // IMPORTANT: Do NOT await waitForReady() BEFORE counting/ACKing the window.
        // If the browser download bar pauses, waitForReady() blocks indefinitely,
        // which delays the ack_window back to the sender, causing a deadlock.
        // Instead: count the bytes and send the ack_window FIRST, then write.
        // The Service Worker buffers chunks internally if the download is paused.
        _receivedBytes += message.binary.length;
        _windowBytesReceived += message.binary.length;

        // Send window ACK back to sender to unblock their Guard 2 FIRST
        if (_windowBytesReceived >= _remoteWindowSize) {
          _windowBytesReceived = 0;
          if (!kIsWeb) {
            await _fileSaver?.flush();
          }
          _webrtcClient.sendDataMessage(
            RTCDataChannelMessage(jsonEncode({'type': 'ack_window'})),
          );
          debugPrint(
            '📨 [P2P-RX] Sent ack_window (received ${_receivedBytes ~/ 1024} KB total)',
          );
        }

        // NOW write to disk (web: after acking, so browser pause doesn't deadlock sender)
        if (kIsWeb) await _fileSaver?.waitForReady();
        _fileSaver?.addChunk(message.binary);

        // Send progress update to sender every ~200ms so sender UI stays perfectly in sync
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        if (nowMs - _lastRxProgressPingMs > 200) {
          _lastRxProgressPingMs = nowMs;
          _webrtcClient.sendDataMessage(
            RTCDataChannelMessage(
              jsonEncode({
                'type': 'rx_progress',
                'bytes': _receivedBytes,
                'fileId': _receivingFileId,
                'fileName': _receivingFileName,
                'totalSize': _receivingTotalSize,
                'fileIndex': _receivingFileIndex,
                'totalFiles': _receivingTotalFiles,
              }),
            ),
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
      } catch (e) {
        debugPrint('❌ [P2P-RX] Error processing binary chunk: $e');
        _progressController.addError('Storage Error: $e');
        cancelTransfer(myRole: 'receiver');
      }
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
              _remoteWindowSize = decoded['windowSize'] as int;
            } else {
              _remoteWindowSize = _unifiedWindowSize;
            }

            _fileSaver = getFileSaver();
            _fileSaver!.setOnCancel(() {
              debugPrint('🛑 [P2P-ACK] Cancelled from Browser UI.');
              cancelTransfer(myRole: 'receiver');
              onSelfCancelled?.call();
            });
            _fileSaver!.setOnIncognitoDetected(() {
              debugPrint(
                '⚠️ [P2P-ACK] Incognito mode detected. Aborting transfer.',
              );
              cancelTransfer(myRole: 'receiver');
              onIncognitoDetected?.call();
            });

            // Guard: mark initializing so any binary chunks that arrive
            // during the async init() call are queued, not silently dropped.
            _isInitializing = true;
            await _fileSaver!.init(
              _receivingFileName ?? 'file',
              fileSize: _receivingTotalSize,
            );
            _isInitializing = false;

            // Drain any chunks that arrived during init().
            // ✅ Reset _windowBytesReceived BEFORE drain to avoid extra ACKs
            //    from chunks that were already partially counted before.
            if (_initQueue.isNotEmpty) {
              debugPrint(
                '📦 [P2P-ACK] Draining ${_initQueue.length} queued chunks from init window.',
              );
              _windowBytesReceived = 0; // ✅ Clean slate before drain
              for (final queued in _initQueue) {
                if (kIsWeb) await _fileSaver?.waitForReady();
                _fileSaver?.addChunk(queued);
                _receivedBytes +=
                    queued.length; // ✅ Count here, NOT in init queue
                _windowBytesReceived += queued.length;
                if (_windowBytesReceived >= _remoteWindowSize) {
                  _windowBytesReceived = 0;
                  // Apply true disk-level backpressure before asking for more data
                  if (!kIsWeb) {
                    await _fileSaver?.flush();
                  }
                  _webrtcClient.sendDataMessage(
                    RTCDataChannelMessage(jsonEncode({'type': 'ack_window'})),
                  );
                }
              }
              _initQueue.clear();
            }

            // Emit initial progress so receiver UI switches to progress screen
            _emitProgress(
              controller: _progressController,
              fileId: _receivingFileId ?? '',
              fileName: _receivingFileName ?? '',
              totalSize: _receivingTotalSize,
              bytesTransferred: _receivedBytes,
              fileIndex: _receivingFileIndex,
              totalFiles: _receivingTotalFiles,
            );

            debugPrint(
              '📥 [P2P-ACK] Receiving $_receivingFileName ($_receivingTotalSize bytes) '
              '— mode: $_remoteTransferMode, window: ${_remoteWindowSize ~/ 1024} KB',
            );
            break;

          case 'eof':
            // All data received — cancel watchdog, save file, notify sender
            _receiveWatchdog?.cancel();
            _receiveWatchdog = null;
            // ✅ Reset byte counters NOW, before the next file's metadata/chunks arrive.
            // Without this, if next-file binary chunks arrive before 'metadata',
            // they get added to the stale counter from this file, causing
            // receiver to show MORE bytes than sender has sent.
            _receivedBytes = 0;
            _windowBytesReceived = 0;
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

          case 'rx_progress':
            // Sender receives real-time progress from receiver
            // This prevents the sender UI from "jumping" instantly to 8MB
            _emitProgress(
              controller: _progressController,
              fileId: decoded['fileId'] ?? '',
              fileName: decoded['fileName'] ?? '',
              totalSize: decoded['totalSize'] ?? 0,
              bytesTransferred: decoded['bytes'] ?? 0,
              fileIndex: decoded['fileIndex'] ?? 1,
              totalFiles: decoded['totalFiles'] ?? 1,
            );
            break;

          case 'ack':
            // Final save ACK — unblock sender's post-EOF wait
            final fileId = decoded['fileId'] as String?;
            if (fileId != null) _ackCompleters[fileId]?.complete();
            break;

          case 'ack_window':
            // Window ACK — unblock sender's Guard 2 (memory safety check).
            if (_windowAckCompleter != null &&
                !_windowAckCompleter!.isCompleted) {
              _windowAckCompleter!.complete();
            }
            // ✅ DO NOT recreate the completer here! The sender loop will recreate it
            //    after it unblocks. Recreating it here caused a race condition where
            //    an early ACK would recreate the completer BEFORE the sender loop
            //    awaited it, causing the sender to await the NEW pending completer and deadlock.
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
