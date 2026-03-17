import 'package:equatable/equatable.dart';
import '../../../../domain/entities/peer_session.dart';

abstract class ConnectionStateBloc extends Equatable {
  const ConnectionStateBloc();

  @override
  List<Object?> get props => [];
}

class ConnectionInitial extends ConnectionStateBloc {}

/// Emitted during the connection/session creation phase with a value between 0.0 and 1.0
class ConnectionProgress extends ConnectionStateBloc {
  final double progress;
  final String message;
  const ConnectionProgress(this.progress, this.message);

  @override
  List<Object?> get props => [progress, message];
}

class ConnectionLoading extends ConnectionStateBloc {}

class ConnectionCreated extends ConnectionStateBloc {
  final String sessionId;
  const ConnectionCreated(this.sessionId);

  @override
  List<Object?> get props => [sessionId];
}

class ConnectionConnected extends ConnectionStateBloc {
  final SessionRole role;
  const ConnectionConnected(this.role);

  @override
  List<Object?> get props => [role];
}

class ConnectionFailed extends ConnectionStateBloc {
  final String message;
  const ConnectionFailed(this.message);

  @override
  List<Object?> get props => [message];
}

class ConnectionOffline extends ConnectionStateBloc {}

/// Emitted when the signaling server is unreachable (e.g. Render 404, max retries hit)
class ConnectionServerError extends ConnectionStateBloc {
  final String message;
  const ConnectionServerError(this.message);

  @override
  List<Object?> get props => [message];
}

class ConnectionMessageReceived extends ConnectionStateBloc {
  final Map<String, dynamic> payload;
  const ConnectionMessageReceived(this.payload);
  
  @override
  List<Object?> get props => [payload];
}

/// For minor status text updates that don't change the main state
class ConnectionStatusUpdate extends ConnectionStateBloc {
  final String message;
  const ConnectionStatusUpdate(this.message);

  @override
  List<Object?> get props => [message];
}
