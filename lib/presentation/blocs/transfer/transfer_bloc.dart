import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../domain/repositories/file_transfer_repository.dart';
import 'transfer_event.dart';
import 'transfer_state.dart';

class TransferBloc extends Bloc<TransferEvent, TransferState> {
  final FileTransferRepository fileTransferRepository;
  StreamSubscription? _progressSubscription;
  StreamSubscription? _fileReceivedSubscription;

  DateTime? _lastUpdate;
  int _lastBytes = 0;
  double _currentSpeed = 0;

  // ── Stall detection ────────────────────────────────────────────────────────────
  /// Fires when no progress event is received for 10 seconds.
  /// Sets isStalled=true so the UI can show a "slow connection" warning.
  Timer? _stallTimer;
  bool _isStalled = false;
  static const _stallThreshold = Duration(seconds: 10);

  // ── Dead timer (auto-cancel on zero data) ────────────────────────────────
  /// Starts when stall is detected. If STILL stalled after 120 s (0 KB/s
  /// for 2 minutes total) → auto-cancel with a clear error message.
  Timer? _deadTimer;
  static const _deadThreshold = Duration(seconds: 120);

  TransferBloc({required this.fileTransferRepository})
    : super(TransferInitial()) {
    on<SendFilesEvent>(_onSendFiles);
    on<TransferProgressEvent>(_onTransferProgress);
    on<TransferCompletedEvent>(_onTransferCompleted);
    on<TransferErrorEvent>(_onTransferError);
    on<CancelTransferEvent>(_onCancelTransfer);
    on<PeerCancelledEvent>(_onPeerCancelled);
    on<SelfCancelledFromBrowserEvent>(_onSelfCancelledFromBrowser);
    on<IncognitoDetectedEvent>(_onIncognitoDetected);
    on<SaveFileManuallyEvent>(_onSaveFileManually);
    on<ResetTransferEvent>(_onResetTransfer);

    _progressSubscription = fileTransferRepository.transferProgressStream
        .listen((info) {
          add(
            TransferProgressEvent(
              fileId: info.fileId,
              fileName: info.fileName,
              totalSize: info.totalSize,
              bytesTransferred: info.bytesTransferred,
              fileIndex: info.fileIndex,
              totalFiles: info.totalFiles,
            ),
          );
        }, onError: (e) => add(TransferErrorEvent(e.toString())));

    _fileReceivedSubscription = fileTransferRepository.onFileReceivedStream
        .listen((path) {
          add(TransferCompletedEvent(path));
        }, onError: (e) => add(TransferErrorEvent(e.toString())));

    // Wire up peer-cancel callback so repository can inform us when remote cancels
    fileTransferRepository.onPeerCancelled = (cancellerRole) {
      add(PeerCancelledEvent(cancellerRole));
    };

    // Wire up self-cancel callback so repository can inform us when local browser cancels
    fileTransferRepository.onSelfCancelled = () {
      add(SelfCancelledFromBrowserEvent());
    };

    // Wire up Incognito detected callback for showing block dialog
    fileTransferRepository.onIncognitoDetected = () {
      add(IncognitoDetectedEvent());
    };
  }

  Future<void> _onSendFiles(
    SendFilesEvent event,
    Emitter<TransferState> emit,
  ) async {
    try {
      await fileTransferRepository.sendFiles(event.files);
      if (fileTransferRepository.isCancelled) {
        // Transfer was halted (network error) or cancelled by peer.
        // Do NOT emit TransferInitial — the error/cancel state is already set correctly.
        // Emitting TransferInitial here caused the false 'Verifying Connection...' screen.
        return;
      } else {
        emit(const TransferSuccess('__SENT__'));
      }
    } catch (e) {
      // Skip failure if cancelled by us OR by peer — both are intentional stops
      if (!fileTransferRepository.isCancelled && state is! TransferCancelledByPeer) {
        emit(TransferFailure(e.toString()));
      }
    }
  }

  void _onTransferProgress(
    TransferProgressEvent event,
    Emitter<TransferState> emit,
  ) {
    // If cancelled or any terminal state already set, silently drop progress.
    if (fileTransferRepository.isCancelled) return;
    if (state is TransferSuccess || state is TransferCancelledByPeer || state is TransferFailure) return;

    final now = DateTime.now();
    if (_lastUpdate != null) {
      final elapsed = now.difference(_lastUpdate!).inMilliseconds;
      if (elapsed > 200) {
        final bytesDiff = event.bytesTransferred - _lastBytes;
        _currentSpeed = (bytesDiff / elapsed) * 1000;
        _lastUpdate = now;
        _lastBytes = event.bytesTransferred;
      }
    } else {
      _lastUpdate = now;
      _lastBytes = event.bytesTransferred;
    }

    // ── Stall detection: reset timer on every progress tick ───────────────────
    _stallTimer?.cancel();
    if (event.bytesTransferred < event.totalSize) {
      // ✅ Progress resumed — clear stall + dead state immediately.
      // Without this, _isStalled stays true even when data is flowing (e.g. 1 KB/s
      // sends a chunk every 64s), causing the dead timer to fire a false auto-cancel.
      if (_isStalled) {
        _isStalled = false;
        _deadTimer?.cancel();
        _deadTimer = null;
      }

      // Start fresh 10s stall timer. If no progress for 10s → stalled.
      _stallTimer = Timer(_stallThreshold, () {
        if (state is! TransferInProgress) return;
        _isStalled = true;

        // ── Dead timer: if stall persists 120s (no data at all for 2 min) ──
        // Only start if not already running from a previous stall cycle.
        _deadTimer ??= Timer(_deadThreshold, () {
          _deadTimer = null;
          if (_isStalled && state is TransferInProgress && !isClosed) {
            add(const TransferErrorEvent(
              'No data received for 2 minutes. The connection is lost. Please try again.',
            ));
          }
        });

        // Re-emit with isStalled=true so UI updates immediately.
        final s = state as TransferInProgress;
        if (!isClosed) {
          add(TransferProgressEvent(
            fileId: s.fileId,
            fileName: s.fileName,
            totalSize: s.totalSize,
            bytesTransferred: s.bytesTransferred,
            fileIndex: s.fileIndex,
            totalFiles: s.totalFiles,
          ));
        }
      });
    } else {
      // 100% — clear all stall + dead state
      _isStalled = false;
      _stallTimer?.cancel();
      _stallTimer = null;
      _deadTimer?.cancel();
      _deadTimer = null;
    }

    // ── ETA calculation ────────────────────────────────────────────────────────
    // Only show ETA when data is actively flowing (not stalled).
    // When stalled, _currentSpeed is stale — showing it would mislead the user.
    final bytesRemaining = event.totalSize - event.bytesTransferred;
    int? eta;
    if (!_isStalled && _currentSpeed > 0 && bytesRemaining > 0) {
      eta = (bytesRemaining / _currentSpeed).round();
    }

    emit(
      TransferInProgress(
        fileId: event.fileId,
        fileName: event.fileName,
        totalSize: event.totalSize,
        bytesTransferred: event.bytesTransferred,
        transferSpeed: _currentSpeed,
        fileIndex: event.fileIndex,
        totalFiles: event.totalFiles,
        isStalled: _isStalled,
        estimatedSecondsLeft: eta,
      ),
    );
  }

  void _onTransferCompleted(
    TransferCompletedEvent event,
    Emitter<TransferState> emit,
  ) {
    emit(TransferSuccess(event.filePath));
  }

  void _onTransferError(TransferErrorEvent event, Emitter<TransferState> emit) {
    if (fileTransferRepository.isCancelled) return; // cancelled by us — silent
    if (state is TransferSuccess || state is TransferCancelledByPeer || state is TransferFailure) return;
    
    // Use haltTransfer() (NOT cancelTransfer) to stop background loops.
    // cancelTransfer() sends a cancel message to peer — causing a false 'Receiver cancelled' screen!
    // haltTransfer() only stops the local operation silently.
    try {
      fileTransferRepository.haltTransfer();
    } catch (_) {}

    emit(TransferFailure(event.error));
  }

  void _onCancelTransfer(
    CancelTransferEvent event,
    Emitter<TransferState> emit,
  ) {
    try {
      fileTransferRepository.cancelTransfer(myRole: event.myRole);
    } catch (e) {
      debugPrint('Error during cancel: $e');
    }
    // Reset speed + stall + dead counters
    _lastUpdate = null;
    _lastBytes = 0;
    _currentSpeed = 0;
    _isStalled = false;
    _stallTimer?.cancel();
    _stallTimer = null;
    _deadTimer?.cancel();
    _deadTimer = null;
  }

  void _onPeerCancelled(PeerCancelledEvent event, Emitter<TransferState> emit) {
    if (state is TransferSuccess) return; // already done, ignore
    // Build a human-readable message for the PEER's screen
    final msg = event.cancellerRole == 'sender'
        ? 'Sender cancelled the transfer.'
        : 'Receiver cancelled the transfer.';
    emit(TransferCancelledByPeer(msg));
  }

  void _onSaveFileManually(
    SaveFileManuallyEvent event,
    Emitter<TransferState> emit,
  ) {
    fileTransferRepository.saveFileManually(event.filePath);
  }

  void _onResetTransfer(
    ResetTransferEvent event,
    Emitter<TransferState> emit,
  ) {
    try {
      fileTransferRepository.resetTransferState();
    } catch (e) {
      debugPrint('Error during reset: $e');
    }
    _lastUpdate = null;
    _lastBytes = 0;
    _currentSpeed = 0;
    _isStalled = false;
    _stallTimer?.cancel();
    _stallTimer = null;
    _deadTimer?.cancel();
    _deadTimer = null;
    emit(TransferInitial());
  }

  void _onSelfCancelledFromBrowser(
    SelfCancelledFromBrowserEvent event,
    Emitter<TransferState> emit,
  ) {
    _lastUpdate = null;
    _lastBytes = 0;
    _currentSpeed = 0;
    emit(TransferCancelledBySelf());
  }

  void _onIncognitoDetected(
    IncognitoDetectedEvent event,
    Emitter<TransferState> emit,
  ) {
    _lastUpdate = null;
    _lastBytes = 0;
    _currentSpeed = 0;
    emit(TransferIncognitoError());
  }

  @override
  Future<void> close() {
    fileTransferRepository.onPeerCancelled = null;
    fileTransferRepository.onSelfCancelled = null;
    fileTransferRepository.onIncognitoDetected = null;
    _progressSubscription?.cancel();
    _fileReceivedSubscription?.cancel();
    _stallTimer?.cancel();
    _stallTimer = null;
    _deadTimer?.cancel();
    _deadTimer = null;
    return super.close();
  }
}
