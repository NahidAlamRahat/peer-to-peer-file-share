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
  }

  Future<void> _onSendFiles(
    SendFilesEvent event,
    Emitter<TransferState> emit,
  ) async {
    try {
      await fileTransferRepository.sendFiles(event.files);
      // For sender, successful finish might not trigger onFileReceivedStream 
      // Instead, we can emit success immediately or rely on progress reaching 100%.
      // We'll emit success when progress == 100 on sender side from progress stream.
    } catch (e) {
      emit(TransferFailure(e.toString()));
    }
  }

  void _onTransferProgress(
    TransferProgressEvent event,
    Emitter<TransferState> emit,
  ) {
    final now = DateTime.now();
    if (_lastUpdate != null) {
      final elapsed = now.difference(_lastUpdate!).inMilliseconds;
      if (elapsed > 200) { // Update speed every 200ms
        final bytesDiff = event.bytesTransferred - _lastBytes;
        _currentSpeed = (bytesDiff / elapsed) * 1000; // bytes/sec
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

    // Optional: if sender reached 100% just emit success for sender screen
    if (event.bytesTransferred >= event.totalSize && event.totalSize > 0) {
      // sender sees "sent successfully", we just emit a success with sender marker.
      // But let's leave success for actual file path completion (receiver)
    }
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
    emit(TransferFailure(event.error));
  }

  void _onCancelTransfer(
    CancelTransferEvent event,
    Emitter<TransferState> emit,
  ) {
    fileTransferRepository.cancelTransfer();
    emit(const TransferFailure('Transfer was cancelled by user.'));
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
    emit(TransferInitial());
  }

  @override
  Future<void> close() {
    _progressSubscription?.cancel();
    _fileReceivedSubscription?.cancel();
    return super.close();
  }
}
