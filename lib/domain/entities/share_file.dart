import 'dart:typed_data';

/// A cross-platform file representation that works on both mobile and web.
/// Instead of using dart:io File (which is unavailable on web),
/// we hold the raw bytes stream and the file name.
/// Uses readAsByteStream() from file_picker 12.x for memory-safe large file support.
class ShareFile {
  final String name;
  final int size;
  final Stream<List<int>>? readStream;
  // bytes kept for backward compat with web Blob path if needed
  final Uint8List? bytes;

  const ShareFile({
    required this.name,
    required this.size,
    this.readStream,
    this.bytes,
  });
}
