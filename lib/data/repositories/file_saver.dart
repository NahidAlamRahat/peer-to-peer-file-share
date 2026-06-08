import 'dart:typed_data';

/// Abstract interface to handle progressive file saving
/// without keeping the entire file in Dart Heap Memory.
abstract class P2PFileSaver {
  /// [fileSize] is the total size in bytes — used by the web saver
  /// to decide whether an in-memory blob fallback is safe.
  Future<void> init(String fileName, {int fileSize = 0});
  void addChunk(Uint8List chunk);
  Future<String> closeAndSave();
  Future<void> discard();
  void triggerManualDownload(String path);
  void setOnCancel(void Function() onCancel);
  void setOnIncognitoDetected(void Function() onIncognito) {} // no-op by default
  Future<void> waitForReady();
}
