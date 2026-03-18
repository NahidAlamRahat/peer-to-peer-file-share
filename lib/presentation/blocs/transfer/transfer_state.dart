import 'package:equatable/equatable.dart';

abstract class TransferState extends Equatable {
  const TransferState();

  @override
  List<Object?> get props => [];
}

class TransferInitial extends TransferState {}

class TransferInProgress extends TransferState {
  final String fileId;
  final String fileName;
  final int totalSize;
  final int bytesTransferred;
  final double transferSpeed; // bytes per second
  final int fileIndex;
  final int totalFiles;

  const TransferInProgress({
    required this.fileId,
    required this.fileName,
    required this.totalSize,
    required this.bytesTransferred,
    required this.transferSpeed,
    required this.fileIndex,
    required this.totalFiles,
  });

  double get progress => totalSize == 0 ? 0 : bytesTransferred / totalSize;

  @override
  List<Object?> get props => [fileId, fileName, totalSize, bytesTransferred, transferSpeed, fileIndex, totalFiles];
}

class TransferSuccess extends TransferState {
  final String filePath;
  const TransferSuccess(this.filePath);

  @override
  List<Object?> get props => [filePath];
}

class TransferFailure extends TransferState {
  final String error;
  const TransferFailure(this.error);

  @override
  List<Object?> get props => [error];
}
