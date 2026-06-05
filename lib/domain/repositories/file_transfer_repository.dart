import '../entities/share_file.dart';
import '../entities/file_chunk_info.dart';

abstract class FileTransferRepository {
  /// Send multiple files sequentially
  Future<void> sendFiles(List<ShareFile> files);

  /// Stream of transfer progress (both sending and receiving)
  Stream<FileChunkInfo> get transferProgressStream;

  /// Stream that emits the fully received file path when a transfer completes
  Stream<String> get onFileReceivedStream;

  /// Triggers a native manual file download/save for platforms that block auto-downloads (Web).
  void saveFileManually(String filePath);

  /// Cancel the current transfer.
  /// [myRole] = 'sender' or 'receiver' — sent to peer so they see the right message.
  void cancelTransfer({String myRole = 'sender'});

  /// Resets the internal transfer state (like cancel flags) between sessions.
  void resetTransferState();

  /// Callback fired when the REMOTE peer cancels. Set this from the bloc.
  set onPeerCancelled(Function(String cancellerRole)? callback);
}
