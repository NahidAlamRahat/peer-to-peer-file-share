import 'package:equatable/equatable.dart';
import '../../../domain/entities/share_file.dart';

abstract class TransferEvent extends Equatable {
  const TransferEvent();

  @override
  List<Object?> get props => [];
}

class SendFileEvent extends TransferEvent {
  final ShareFile file;
  const SendFileEvent(this.file);

  @override
  List<Object?> get props => [file];
}

class TransferProgressEvent extends TransferEvent {
  final String fileId;
  final String fileName;
  final int totalSize;
  final int bytesTransferred;

  const TransferProgressEvent({
    required this.fileId,
    required this.fileName,
    required this.totalSize,
    required this.bytesTransferred,
  });

  @override
  List<Object?> get props => [fileId, fileName, totalSize, bytesTransferred];
}

class TransferCompletedEvent extends TransferEvent {
  final String filePath;
  const TransferCompletedEvent(this.filePath);

  @override
  List<Object?> get props => [filePath];
}

class TransferErrorEvent extends TransferEvent {
  final String error;
  const TransferErrorEvent(this.error);
  
  @override
  List<Object?> get props => [error];
}
