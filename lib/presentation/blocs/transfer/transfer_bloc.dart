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
  }

  Future<void> _onSendFiles(
    SendFilesEvent event,
    Emitter<TransferState> emit,
  ) async {
    try {
      await fileTransferRepository.sendFiles(event.files);
      if (fileTransferRepository.isCancelled) {
        emit(TransferInitial());
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
    if (fileTransferRepository.isCancelled) {
      emit(TransferInitial());
      return;
    }
    // Don't overwrite a terminal state with progress
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
    
    // Stop any ongoing file operations in the background so it doesn't keep emitting progress
    try {
      fileTransferRepository.cancelTransfer(myRole: 'system_error');
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
    // Emit TransferInitial so if user comes back to transfer screen it's fresh
    emit(TransferInitial());
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

  @override
  Future<void> close() {
    fileTransferRepository.onPeerCancelled = null;
    _progressSubscription?.cancel();
    _fileReceivedSubscription?.cancel();
    return super.close();
  }
}
