import 'package:equatable/equatable.dart';

abstract class TransferState extends Equatable {
  const TransferState();

  @override
  List<Object?> get props => [];
}

class TransferInitial extends TransferState {}

class TransferInProgress extends TransferState {
  final String fileId;
  final String fileName;
  final int totalSize;
  final int bytesTransferred;
  final double transferSpeed; // bytes per second
  final int fileIndex;
  final int totalFiles;

  /// True when no progress has been made for 10+ seconds.
  /// Used to show a "transfer is slow" warning in the UI.
  final bool isStalled;

  /// Estimated seconds remaining based on current speed.
  /// Null when speed is 0 or transfer is complete.
  final int? estimatedSecondsLeft;

  const TransferInProgress({
    required this.fileId,
    required this.fileName,
    required this.totalSize,
    required this.bytesTransferred,
    required this.transferSpeed,
    required this.fileIndex,
    required this.totalFiles,
    this.isStalled = false,
    this.estimatedSecondsLeft,
  });

  double get progress => totalSize == 0 ? 0 : bytesTransferred / totalSize;

  @override
  List<Object?> get props => [fileId, fileName, totalSize, bytesTransferred, transferSpeed, fileIndex, totalFiles, isStalled, estimatedSecondsLeft];
}

class TransferSuccess extends TransferState {
  final String filePath;
  const TransferSuccess(this.filePath);

  @override
  List<Object?> get props => [filePath];
}

class TransferFailure extends TransferState {
  final String error;
  const TransferFailure(this.error);

  @override
  List<Object?> get props => [error];
}

/// Shown only on the PEER's screen when the other side cancels.
/// The canceller themselves goes home silently — no message shown to them.
class TransferCancelledByPeer extends TransferState {
  /// e.g. "Sender cancelled the transfer."
  final String message;
  const TransferCancelledByPeer(this.message);

  @override
  List<Object?> get props => [message];
}

/// Fired when the local user (receiver) cancels from the browser's download bar.
/// Triggers silent navigation to home — no error shown.
class TransferCancelledBySelf extends TransferState {}

/// Fired when Chrome Incognito mode is detected.
/// Shows a blocking popup dialog.
class TransferIncognitoError extends TransferState {}
