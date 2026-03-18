import 'package:equatable/equatable.dart';
import '../../../domain/entities/share_file.dart';

abstract class TransferEvent extends Equatable {
  const TransferEvent();

  @override
  List<Object?> get props => [];
}

class SendFilesEvent extends TransferEvent {
  final List<ShareFile> files;
  const SendFilesEvent(this.files);

  @override
  List<Object?> get props => [files];
}

class TransferProgressEvent extends TransferEvent {
  final String fileId;
  final String fileName;
  final int totalSize;
  final int bytesTransferred;
  final int fileIndex;
  final int totalFiles;

  const TransferProgressEvent({
    required this.fileId,
    required this.fileName,
    required this.totalSize,
    required this.bytesTransferred,
    required this.fileIndex,
    required this.totalFiles,
  });

  @override
  List<Object?> get props => [fileId, fileName, totalSize, bytesTransferred, fileIndex, totalFiles];
}

class TransferCompletedEvent extends TransferEvent {
  final String filePath;
  const TransferCompletedEvent(this.filePath);

  @override
  List<Object?> get props => [filePath];
}

class TransferBatchCompletedEvent extends TransferEvent {
  final List<String> filePaths;
  const TransferBatchCompletedEvent(this.filePaths);

  @override
  List<Object?> get props => [filePaths];
}

class TransferErrorEvent extends TransferEvent {
  final String error;
  const TransferErrorEvent(this.error);
  
  @override
  List<Object?> get props => [error];
}

class CancelTransferEvent extends TransferEvent {}

class SaveFileManuallyEvent extends TransferEvent {
  final String filePath;
  const SaveFileManuallyEvent(this.filePath);

  @override
  List<Object?> get props => [filePath];
}
