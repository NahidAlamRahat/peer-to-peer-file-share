import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/file_chunk_info.dart';
import '../../domain/entities/share_file.dart';
import '../../domain/repositories/file_transfer_repository.dart';
import '../datasources/webrtc_client.dart';
import 'file_saver.dart';

// Web-only download trigger
import 'file_transfer_web.dart' if (dart.library.io) 'file_transfer_mobile.dart';

class FileTransferRepositoryImpl implements FileTransferRepository {
  final WebRTCClient _webrtcClient;

  final _progressController = StreamController<FileChunkInfo>.broadcast();
  final _fileReceivedController = StreamController<String>.broadcast();

  // state for receiving
  String? _receivingFileId;
  String? _receivingFileName;
  int _receivingTotalSize = 0;
  int _receivedBytes = 0;
  int _receivingFileIndex = 1;
  int _receivingTotalFiles = 1;
  P2PFileSaver? _fileSaver;
  bool _isCancelled = false;

  FileTransferRepositoryImpl(this._webrtcClient) {
    _webrtcClient.onDataMessage = _handleDataMessage;
    _webrtcClient.setBufferedAmountLowThreshold(65536); // 64 KB
    _webrtcClient.onBufferedAmountLow = (amount) {
      _bufferCompleter?.complete();
      _bufferCompleter = null;
    };
  }

  /// Reset receiving state between transfers
  void resetReceiveState() {
    _receivingFileId = null;
    _receivingFileName = null;
    _receivingTotalSize = 0;
    _receivedBytes = 0;
    _receivingFileIndex = 1;
    _receivingTotalFiles = 1;
    _fileSaver = null;
    _bufferCompleter = null;
  }

  Completer<void>? _bufferCompleter;
  static const int _maxBufferSize = 1048576; // 1 MB
  static const int _chunkSize = 65536; // 64 KB

  @override
  Stream<FileChunkInfo> get transferProgressStream => _progressController.stream;

  @override
  Stream<String> get onFileReceivedStream => _fileReceivedController.stream;

  @override
  void cancelTransfer() {
    _isCancelled = true;
    _webrtcClient.sendDataMessage(RTCDataChannelMessage(jsonEncode({'type': 'cancel'})));
    _fileSaver?.discard();
    _fileSaver = null;
    _progressController.addError('Transfer cancelled');
  }

  @override
  Future<void> sendFiles(List<ShareFile> files) async {
    _isCancelled = false;
    
    // Safety check: Wait for the data channel to be fully OPEN before streaming
    int waitCounter = 0;
    while (_webrtcClient.dataChannelState != RTCDataChannelState.RTCDataChannelOpen) {
      if (_isCancelled) return;
      if (waitCounter > 100) { // 10 seconds timeout
         _progressController.addError('Timeout waiting for peer DataChannel to open');
         return;
      }
      debugPrint('⏳ [P2P] Waiting for data channel to open... (${_webrtcClient.dataChannelState})');
      await Future.delayed(const Duration(milliseconds: 100));
      waitCounter++;
    }
    
    // Give the receiver 300ms to attach onMessage listeners after opening
    await Future.delayed(const Duration(milliseconds: 300));

    for (int i = 0; i < files.length; i++) {
      if (_isCancelled) break;
      final file = files[i];
      final String fileId = const Uuid().v4();
      final String fileName = file.name;
      final int totalSize = file.size;

      // 1. Send metadata block first
      final Map<String, dynamic> metadata = {
        'type': 'metadata',
        'fileId': fileId,
        'fileName': fileName,
        'totalSize': totalSize,
        'fileIndex': i + 1,
        'totalFiles': files.length,
      };
      _webrtcClient.sendDataMessage(RTCDataChannelMessage(jsonEncode(metadata)));

      // 2. Send in chunks
      int bytesSent = 0;
      debugPrint('🚀 [P2P] Starting high-speed transfer: $fileName ($totalSize bytes) [${i+1}/${files.length}]');

      if (file.readStream != null) {
        // Safe Stream iteration using low RAM footprint
        await for (final chunk in file.readStream!) {
          if (_isCancelled) {
             debugPrint('🛑 [P2P] Transfer cancelled during streaming chunk.');
             break;
          }
          final uint8Chunk = Uint8List.fromList(chunk);
          
          if (_webrtcClient.bufferedAmount > _maxBufferSize) {
            _bufferCompleter = Completer<void>();
            await _bufferCompleter!.future;
          }

          _webrtcClient.sendDataMessageBinary(uint8Chunk);
          bytesSent += uint8Chunk.length;

          _progressController.add(FileChunkInfo(
            fileId: fileId,
            fileName: fileName,
            totalSize: totalSize,
            bytesTransferred: bytesSent,
            fileIndex: i + 1,
            totalFiles: files.length,
          ));
        }
      } else if (file.bytes != null) {
        // Fallback for smaller files / platforms lacking chunk streams
        final Uint8List bytes = file.bytes!;
        while (bytesSent < totalSize) {
          if (_isCancelled) {
             debugPrint('🛑 [P2P] Transfer cancelled during byte chunks.');
             break;
          }
          final int remaining = totalSize - bytesSent;
          final int currentChunkSize = remaining < _chunkSize ? remaining : _chunkSize;
          final chunk = bytes.sublist(bytesSent, bytesSent + currentChunkSize);

          if (_webrtcClient.bufferedAmount > _maxBufferSize) {
            _bufferCompleter = Completer<void>();
            await _bufferCompleter!.future;
          }

          _webrtcClient.sendDataMessageBinary(chunk);
          bytesSent += chunk.length;

          _progressController.add(FileChunkInfo(
            fileId: fileId,
            fileName: fileName,
            totalSize: totalSize,
            bytesTransferred: bytesSent,
            fileIndex: i + 1,
            totalFiles: files.length,
          ));
        }
      }
      
      if (_isCancelled) break;

      // 3. Send End of File
      final Map<String, dynamic> eof = {
        'type': 'eof',
        'fileId': fileId,
      };
      _webrtcClient.sendDataMessage(RTCDataChannelMessage(jsonEncode(eof)));
      
      // Small delay between files
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> _handleDataMessage(RTCDataChannelMessage message) async {
    if (message.isBinary) {
      _fileSaver?.addChunk(message.binary);
      _receivedBytes += message.binary.length;

      _progressController.add(FileChunkInfo(
        fileId: _receivingFileId ?? '',
        fileName: _receivingFileName ?? '',
        totalSize: _receivingTotalSize,
        bytesTransferred: _receivedBytes,
        fileIndex: _receivingFileIndex,
        totalFiles: _receivingTotalFiles,
      ));
    } else {
      try {
        final decoded = jsonDecode(message.text);
        if (decoded['type'] == 'metadata') {
          _receivingFileId = decoded['fileId'];
          _receivingFileName = decoded['fileName'];
          _receivingTotalSize = decoded['totalSize'];
          _receivingFileIndex = decoded['fileIndex'] ?? 1;
          _receivingTotalFiles = decoded['totalFiles'] ?? 1;
          _receivedBytes = 0;
          
          _fileSaver = getFileSaver();
          await _fileSaver!.init(_receivingFileName ?? 'file');
        } else if (decoded['type'] == 'eof') {
          // Save the file using platform-specific stream saver
          if (_fileSaver != null) {
            final savedPath = await _fileSaver!.closeAndSave();
            _fileReceivedController.add(savedPath);
            _fileSaver = null;
          }
        } else if (decoded['type'] == 'cancel') {
          _isCancelled = true;
          await _fileSaver?.discard();
          _fileSaver = null;
          _progressController.addError('Transfer cancelled by peer');
          debugPrint('🛑 [P2P] Received cancel signal. Discarding file.');
        }
      } catch (e) {
        debugPrint('Error parsing text message: $e');
        _progressController.addError('System Error: $e');
      }
    }
  }
}
