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

  /// Halt the transfer locally due to a system error (e.g. network drop).
  /// Does NOT send any cancel message to the peer — avoids false "Receiver cancelled" messages.
  void haltTransfer();

  /// Resets the internal transfer state (like cancel flags) between sessions.
  void resetTransferState();

  /// Whether the transfer is currently cancelled.
  bool get isCancelled;

  /// Callback fired when the REMOTE peer cancels. Set this from the bloc.
  set onPeerCancelled(Function(String cancellerRole)? callback);

  /// Callback fired when the LOCAL receiver cancels from the browser's native download bar.
  /// Used to trigger silent home navigation without showing an error.
  set onSelfCancelled(Function()? callback);

  /// Callback fired when Chrome Incognito mode is detected.
  /// Used to block downloads and show an alert dialog.
  set onIncognitoDetected(Function()? callback);
}
