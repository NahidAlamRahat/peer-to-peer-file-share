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
  bool _isManuallyCancelled = false;

  // ── Slow Network detection ──────────────────────────────────────────────────
  Timer? _slowNetworkTimer;
  bool _isNetworkSlow = false;

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

    // ── Slow Network detection ──────────────────────────────────
    _slowNetworkTimer?.cancel();
    _isNetworkSlow = false;
    
    if (event.bytesTransferred < event.totalSize) {
      _slowNetworkTimer = Timer(const Duration(seconds: 3), () {
        if (state is! TransferInProgress || isClosed) return;
        _isNetworkSlow = true;
        _currentSpeed = 0; // Speed is effectively 0 if no progress for 3s
        final s = state as TransferInProgress;
        add(TransferProgressEvent(
          fileId: s.fileId,
          fileName: s.fileName,
          totalSize: s.totalSize,
          bytesTransferred: s.bytesTransferred,
          fileIndex: s.fileIndex,
          totalFiles: s.totalFiles,
        ));
      });
    }

    // ── ETA calculation ────────────────────────────────────────────────────────
    final bytesRemaining = event.totalSize - event.bytesTransferred;
    int? eta;
    if (!_isNetworkSlow && _currentSpeed > 0 && bytesRemaining > 0) {
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
        isNetworkSlow: _isNetworkSlow,
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
    if (_isManuallyCancelled) return; // internally cancelled — silent
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
    _isManuallyCancelled = true;
    try {
      fileTransferRepository.cancelTransfer(myRole: event.myRole);
    } catch (e) {
      debugPrint('Error during cancel: $e');
    }
    // Reset speed
    _lastUpdate = null;
    _lastBytes = 0;
    _currentSpeed = 0;
    _isNetworkSlow = false;
    _slowNetworkTimer?.cancel();
    _slowNetworkTimer = null;
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
    _isNetworkSlow = false;
    _slowNetworkTimer?.cancel();
    _slowNetworkTimer = null;
    _isManuallyCancelled = false;
    emit(TransferInitial());
  }

  void _onSelfCancelledFromBrowser(
    SelfCancelledFromBrowserEvent event,
    Emitter<TransferState> emit,
  ) {
    _isManuallyCancelled = true;
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
    _slowNetworkTimer?.cancel();
    _slowNetworkTimer = null;
    return super.close();
  }
}
