import 'dart:typed_data';

/// A cross-platform file representation that works on both mobile and web.
/// Instead of using dart:io File (which is unavailable on web),
/// we hold the raw bytes and the file name.
class ShareFile {
  final String name;
  final int size;
  final Stream<List<int>>? readStream;
  final Uint8List? bytes;

  const ShareFile({
    required this.name,
    required this.size,
    this.readStream,
    this.bytes,
  });
}
