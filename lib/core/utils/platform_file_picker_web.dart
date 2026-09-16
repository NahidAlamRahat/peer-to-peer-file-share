// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
// dart:html is deprecated in favor of package:web but requires adding it as
// an explicit dependency. Since we are using it only for file picking (not DOM
// manipulation), suppressing the info warning here is the simplest safe approach.

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';
import '../../domain/entities/share_file.dart';

Future<List<ShareFile>?> pickFilesPlatform() async {
  final completer = Completer<List<ShareFile>?>();

  // Create native HTML file input and attach to DOM (required for iOS Safari stability)
  final input = html.FileUploadInputElement();
  input.multiple = true;
  input.style.display = 'none';
  html.document.body?.children.add(input);

  StreamSubscription? focusSub;

  void cleanup() {
    focusSub?.cancel();
    input.remove();
  }

  // Listen for file selection
  input.onChange.listen((e) {
    cleanup();
    final files = input.files;
    if (files == null || files.isEmpty) {
      if (!completer.isCompleted) completer.complete(null);
      return;
    }

    final List<ShareFile> shareFiles = [];

    for (final file in files) {
      // Lazy stream generator — reads the file in 256 KB slices on-demand.
      // This avoids loading the entire file into memory upfront.
      Stream<List<int>> createLazyStream(html.File f) async* {
        const chunkSize = 262144; // 256 KB
        int offset = 0;

        while (offset < f.size) {
          final end = (offset + chunkSize < f.size) ? offset + chunkSize : f.size;
          final slice = f.slice(offset, end);

          final chunkCompleter = Completer<List<int>>();
          final reader = html.FileReader();

          final loadSub = reader.onLoadEnd.listen((_) {
            final result = reader.result;
            if (result is ByteBuffer) {
              chunkCompleter.complete(Uint8List.view(result));
            } else if (result is Uint8List) {
              chunkCompleter.complete(result);
            } else {
              chunkCompleter.completeError(
                Exception('Unexpected FileReader result type'),
              );
            }
          });

          final errSub = reader.onError.listen((_) {
            if (!chunkCompleter.isCompleted) {
              chunkCompleter.completeError(
                Exception('Failed to read file chunk'),
              );
            }
          });

          reader.readAsArrayBuffer(slice);

          final data = await chunkCompleter.future;
          yield data;

          loadSub.cancel();
          errSub.cancel();
          offset = end;
        }
      }

      shareFiles.add(ShareFile(
        name: file.name,
        size: file.size,
        readStream: createLazyStream(file),
      ));
    }

    if (!completer.isCompleted) {
      completer.complete(shareFiles.isNotEmpty ? shareFiles : null);
    }
  });

  // Fallback for iOS Safari: when native file picker modal closes, window regains focus.
  // If onChange didn't fire (e.g. user cancelled), resolve with null so UI unblocks.
  focusSub = html.window.onFocus.listen((_) {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!completer.isCompleted) {
        cleanup();
        completer.complete(null);
      }
    });
  });

  // Trigger file dialog
  input.click();

  return completer.future;
}
