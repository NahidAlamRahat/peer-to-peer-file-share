import '../entities/share_file.dart';
import '../entities/file_chunk_info.dart';

abstract class FileTransferRepository {
  /// Send multiple files sequentially
  Future<void> sendFiles(List<ShareFile> files);

  /// Stream of transfer progress (both sending and receiving)
  Stream<FileChunkInfo> get transferProgressStream;

  /// Stream that emits the fully received file path when a transfer completes
  Stream<String> get onFileReceivedStream;

  /// Interrupts the current transfer queue.
  
  /// Triggers a native manual file download/save process for platforms that block auto-downloads (Web).
  void saveFileManually(String filePath);
  
  void cancelTransfer();
}
