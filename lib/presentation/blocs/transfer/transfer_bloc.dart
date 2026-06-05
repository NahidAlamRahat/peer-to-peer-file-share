import 'dart:async';
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

  TransferBloc({required this.fileTransferRepository}) : super(TransferInitial()) {
    on<SendFilesEvent>(_onSendFiles);
    on<TransferProgressEvent>(_onTransferProgress);
    on<TransferCompletedEvent>(_onTransferCompleted);
    on<TransferErrorEvent>(_onTransferError);
    on<CancelTransferEvent>(_onCancelTransfer);
    on<PeerCancelledEvent>(_onPeerCancelled);
    on<SaveFileManuallyEvent>(_onSaveFileManually);
    on<ResetTransferEvent>(_onResetTransfer);

    _progressSubscription = fileTransferRepository.transferProgressStream.listen(
      (info) {
        add(TransferProgressEvent(
          fileId: info.fileId,
          fileName: info.fileName,
          totalSize: info.totalSize,
          bytesTransferred: info.bytesTransferred,
          fileIndex: info.fileIndex,
          totalFiles: info.totalFiles,
        ));
      },
      onError: (e) => add(TransferErrorEvent(e.toString())),
    );

    _fileReceivedSubscription = fileTransferRepository.onFileReceivedStream.listen(
      (path) {
        add(TransferCompletedEvent(path));
      },
      onError: (e) => add(TransferErrorEvent(e.toString())),
    );

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
      emit(const TransferSuccess('__SENT__'));
    } catch (e) {
      // Only emit failure if not already handled by cancel/peer-cancel
      if (state is! TransferCancelledByPeer) {
        emit(TransferFailure(e.toString()));
      }
    }
  }

  void _onTransferProgress(
    TransferProgressEvent event,
    Emitter<TransferState> emit,
  ) {
    // Don't overwrite a terminal state with progress
    if (state is TransferSuccess || state is TransferCancelledByPeer) return;

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

    emit(TransferInProgress(
      fileId: event.fileId,
      fileName: event.fileName,
      totalSize: event.totalSize,
      bytesTransferred: event.bytesTransferred,
      transferSpeed: _currentSpeed,
      fileIndex: event.fileIndex,
      totalFiles: event.totalFiles,
    ));
  }

  void _onTransferCompleted(
    TransferCompletedEvent event,
    Emitter<TransferState> emit,
  ) {
    emit(TransferSuccess(event.filePath));
  }

  void _onTransferError(
    TransferErrorEvent event,
    Emitter<TransferState> emit,
  ) {
    if (state is TransferSuccess || state is TransferCancelledByPeer) return;
    emit(TransferFailure(event.error));
  }

  void _onCancelTransfer(
    CancelTransferEvent event,
    Emitter<TransferState> emit,
  ) {
    // Canceller: go home silently — UI is handled by transfer_screen directly.
    // Just clean up repository state. No state emit here so screen doesn't show error.
    fileTransferRepository.cancelTransfer(myRole: event.myRole);
  }

  void _onPeerCancelled(
    PeerCancelledEvent event,
    Emitter<TransferState> emit,
  ) {
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
    fileTransferRepository.resetTransferState();
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
