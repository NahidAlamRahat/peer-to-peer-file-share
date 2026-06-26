// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../../domain/entities/share_file.dart';

Future<List<ShareFile>?> pickFilesPlatform() async {
  final completer = Completer<List<ShareFile>?>();
  
  // Create native HTML file input
  final input = html.FileUploadInputElement();
  input.multiple = true;
  
  // Listen for file selection
  input.onChange.listen((e) {
    final files = input.files;
    if (files == null || files.isEmpty) {
      completer.complete(null);
      return;
    }
    
    final List<ShareFile> shareFiles = [];
    
    for (final file in files) {
      // Lazy stream generation for each file
      Stream<List<int>> createLazyStream(html.File f) async* {
        const chunkSize = 262144; // 256 KB chunks
        int offset = 0;
        final reader = html.FileReader();
        
        while (offset < f.size) {
          final end = (offset + chunkSize < f.size) ? offset + chunkSize : f.size;
          final slice = f.slice(offset, end);
          
          final chunkCompleter = Completer<List<int>>();
          
          // Use .first to ensure we only get one event per read
          final loadSub = reader.onLoadEnd.listen((_) {
            if (reader.result is Uint8List) {
              chunkCompleter.complete(reader.result as Uint8List);
            } else if (reader.result is ByteBuffer) {
               chunkCompleter.complete(Uint8List.view(reader.result as ByteBuffer));
            } else {
               chunkCompleter.complete(reader.result as List<int>);
            }
          });
          
          final errSub = reader.onError.listen((_) {
            chunkCompleter.completeError(Exception('Failed to read file chunk'));
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
    
    completer.complete(shareFiles);
  });
  
  // Trigger file dialog
  input.click();
  
  return completer.future;
}
