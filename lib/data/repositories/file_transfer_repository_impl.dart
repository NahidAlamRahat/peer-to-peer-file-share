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
  final List<int> _receivedChunks = [];

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
    _receivedChunks.clear();
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
  Future<void> sendFiles(List<ShareFile> files) async {
    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final String fileId = const Uuid().v4();
      final String fileName = file.name;
      final int totalSize = file.size;
      final Uint8List bytes = file.bytes;

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

      while (bytesSent < totalSize) {
        final int remaining = totalSize - bytesSent;
        final int currentChunkSize = remaining < _chunkSize ? remaining : _chunkSize;
        final chunk = bytes.sublist(bytesSent, bytesSent + currentChunkSize);

        // Flow control: Wait if buffer is getting full
        if (_webrtcClient.bufferedAmount > _maxBufferSize) {
          _bufferCompleter = Completer<void>();
          debugPrint('⏳ [P2P] Buffer full (${_webrtcClient.bufferedAmount} bytes). Waiting...');
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

        if (bytesSent % (1024 * 1024) == 0 || bytesSent == totalSize) {
          final percent = (bytesSent / totalSize * 100).toInt();
          debugPrint('📊 [P2P] Sent: $percent% (${(bytesSent / (1024 * 1024)).toStringAsFixed(2)} MB)');
        }
      }

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
      _receivedChunks.addAll(message.binary);
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
          _receivedChunks.clear();
        } else if (decoded['type'] == 'eof') {
          // Save the file using platform-specific implementation
          final bytes = Uint8List.fromList(_receivedChunks);
          await saveReceivedFile(_receivingFileName ?? 'file', bytes);
          _fileReceivedController.add(_receivingFileName ?? 'file');
          _receivedChunks.clear();
        }
      } catch (e) {
        debugPrint('Error parsing text message: $e');
      }
    }
  }
}
