import 'dart:typed_data';

/// Abstract interface to handle progressive file saving
/// without keeping the entire file in Dart Heap Memory.
abstract class P2PFileSaver {
  Future<void> init(String fileName);
  void addChunk(Uint8List chunk);
  Future<String> closeAndSave();
}
