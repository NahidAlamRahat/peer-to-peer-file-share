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

  TransferBloc({required this.fileTransferRepository})
    : super(TransferInitial()) {
    on<SendFilesEvent>(_onSendFiles);
    on<TransferProgressEvent>(_onTransferProgress);
    on<TransferCompletedEvent>(_onTransferCompleted);
    on<TransferErrorEvent>(_onTransferError);
    on<CancelTransferEvent>(_onCancelTransfer);
    on<PeerCancelledEvent>(_onPeerCancelled);
    on<SelfCancelledFromBrowserEvent>(_onSelfCancelledFromBrowser);
    on<SwUnavailableWarningEvent>(_onSwUnavailableWarning);
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

    // Wire up SW-unavailable callback for incognito mode warning
    fileTransferRepository.onSwUnavailableWarning = () {
      add(SwUnavailableWarningEvent());
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
    // If cancelled or any terminal state already set, silently drop progress — do NOT emit TransferInitial.
    // Emitting TransferInitial here was causing the false 'Verifying Connection...' screen flash.
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

    emit(
      TransferInProgress(
        fileId: event.fileId,
        fileName: event.fileName,
        totalSize: event.totalSize,
        bytesTransferred: event.bytesTransferred,
        transferSpeed: _currentSpeed,
        fileIndex: event.fileIndex,
        totalFiles: event.totalFiles,
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
      // DO NOT call resetTransferState() here! It will synchronously clear the isCancelled flag 
      // and allow suspended async tasks to resume and emit progress.
    } catch (e) {
      debugPrint('Error during cancel: $e');
    }
    // Reset speed counters
    _lastUpdate = null;
    _lastBytes = 0;
    _currentSpeed = 0;
    // DO NOT emit TransferInitial here — it causes a visible 'Verifying Connection...' flash
    // for 600ms before navigation. Navigation handles the screen transition.
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

  void _onSwUnavailableWarning(
    SwUnavailableWarningEvent event,
    Emitter<TransferState> emit,
  ) {
    // Don't change the main transfer state — just emit a side-effect state
    // so the screen can show a snackbar. The transfer continues via blob fallback.
    final current = state;
    emit(TransferSwUnavailableWarning());
    emit(current); // Restore previous state immediately
  }

  @override
  Future<void> close() {
    fileTransferRepository.onPeerCancelled = null;
    fileTransferRepository.onSelfCancelled = null;
    fileTransferRepository.onSwUnavailableWarning = null;
    _progressSubscription?.cancel();
    _fileReceivedSubscription?.cancel();
    return super.close();
  }
}
