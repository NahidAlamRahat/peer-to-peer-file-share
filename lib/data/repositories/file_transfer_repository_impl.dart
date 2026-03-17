import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/file_chunk_info.dart';
import '../../domain/repositories/file_transfer_repository.dart';
import '../datasources/webrtc_client.dart';

class FileTransferRepositoryImpl implements FileTransferRepository {
  final WebRTCClient _webrtcClient;

  final _progressController = StreamController<FileChunkInfo>.broadcast();
  final _fileReceivedController = StreamController<String>.broadcast();

  // state for receiving
  String? _receivingFileId;
  String? _receivingFileName;
  int _receivingTotalSize = 0;
  int _receivedBytes = 0;
  IOSink? _fileSink;
  File? _receivingFile;

  FileTransferRepositoryImpl(this._webrtcClient) {
    _webrtcClient.onDataMessage = _handleDataMessage;
    _webrtcClient.setBufferedAmountLowThreshold(65536); // 64 KB
    _webrtcClient.onBufferedAmountLow = (amount) {
      _bufferCompleter?.complete();
      _bufferCompleter = null;
    };
  }

  Completer<void>? _bufferCompleter;
  static const int _maxBufferSize = 1048576; // 1 MB
  static const int _chunkSize = 65536; // 64 KB

  @override
  Stream<FileChunkInfo> get transferProgressStream => _progressController.stream;

  @override
  Stream<String> get onFileReceivedStream => _fileReceivedController.stream;

  @override
  Future<void> sendFile(File file) async {
    if (!await file.exists()) return;

    final String fileId = const Uuid().v4();
    final String fileName = file.uri.pathSegments.last;
    final int totalSize = await file.length();

    // 1. Send metadata block first
    final Map<String, dynamic> metadata = {
      'type': 'metadata',
      'fileId': fileId,
      'fileName': fileName,
      'totalSize': totalSize,
    };
    _webrtcClient.sendDataMessage(RTCDataChannelMessage(jsonEncode(metadata)));

    // 2. Read file in chunks and send
    int bytesSent = 0;
    final RandomAccessFile raf = await file.open(mode: FileMode.read);
    debugPrint('🚀 [P2P] Starting high-speed transfer: $fileName ($totalSize bytes)');

    try {
      while (bytesSent < totalSize) {
        final int remaining = totalSize - bytesSent;
        final int currentChunkSize = remaining < _chunkSize ? remaining : _chunkSize;
        final List<int> chunk = await raf.read(currentChunkSize);
        
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
        ));

        if (bytesSent % (1024 * 1024) == 0 || bytesSent == totalSize) {
          final percent = (bytesSent / totalSize * 100).toInt();
          debugPrint('📊 [P2P] Sent: $percent% (${(bytesSent / (1024 * 1024)).toStringAsFixed(2)} MB)');
        }
      }
    } finally {
      await raf.close();
    }

    // 3. Send End of File
    final Map<String, dynamic> eof = {
      'type': 'eof',
      'fileId': fileId,
    };
    _webrtcClient.sendDataMessage(RTCDataChannelMessage(jsonEncode(eof)));
  }

  Future<void> _handleDataMessage(RTCDataChannelMessage message) async {
    if (message.isBinary) {
      if (_fileSink != null) {
        _fileSink!.add(message.binary);
        _receivedBytes += message.binary.length;
        
        _progressController.add(FileChunkInfo(
          fileId: _receivingFileId ?? '',
          fileName: _receivingFileName ?? '',
          totalSize: _receivingTotalSize,
          bytesTransferred: _receivedBytes,
        ));
      }
    } else {
      // It's a text message (metadata or EOF)
      try {
        final decoded = jsonDecode(message.text);
        if (decoded['type'] == 'metadata') {
          _receivingFileId = decoded['fileId'];
          _receivingFileName = decoded['fileName'];
          _receivingTotalSize = decoded['totalSize'];
          _receivedBytes = 0;

          // Create file in downloads or temp dir
          Directory? dir;
          if (Platform.isAndroid) {
            dir = Directory('/storage/emulated/0/Download');
          } else {
            dir = await getApplicationDocumentsDirectory();
          }

          if (true) {
            final savePath = '${dir.path}/$_receivingFileName';
            _receivingFile = File(savePath);
            int counter = 1;
            while (await _receivingFile!.exists()) {
              final nameWithoutExt = _receivingFileName!.split('.').first;
              final ext = _receivingFileName!.contains('.') ? '.${_receivingFileName!.split('.').last}' : '';
              _receivingFile = File('${dir.path}/$nameWithoutExt ($counter)$ext');
              counter++;
            }
            _fileSink = _receivingFile!.openWrite();
          }
        } else if (decoded['type'] == 'eof') {
          // Finished receiving
          await _fileSink?.flush();
          await _fileSink?.close();
          _fileSink = null;
          
          if (_receivingFile != null) {
            _fileReceivedController.add(_receivingFile!.path);
          }
        }
      } catch (e) {
        debugPrint('Error parsing text message: $e');
      }
    }
  }
}
