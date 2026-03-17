import 'package:equatable/equatable.dart';

class FileChunkInfo extends Equatable {
  final String fileId;
  final String fileName;
  final int totalSize;
  final int bytesTransferred;

  const FileChunkInfo({
    required this.fileId,
    required this.fileName,
    required this.totalSize,
    required this.bytesTransferred,
  });

  double get progress => totalSize == 0 ? 0 : bytesTransferred / totalSize;

  FileChunkInfo copyWith({
    String? fileId,
    String? fileName,
    int? totalSize,
    int? bytesTransferred,
  }) {
    return FileChunkInfo(
      fileId: fileId ?? this.fileId,
      fileName: fileName ?? this.fileName,
      totalSize: totalSize ?? this.totalSize,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
    );
  }

  @override
  List<Object?> get props => [fileId, fileName, totalSize, bytesTransferred];
}
