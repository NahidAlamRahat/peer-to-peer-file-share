import 'package:equatable/equatable.dart';

abstract class ConnectionEvent extends Equatable {
  const ConnectionEvent();

  @override
  List<Object?> get props => [];
}

class CreateSessionEvent extends ConnectionEvent {}

class JoinSessionEvent extends ConnectionEvent {
  final String sessionId;
  const JoinSessionEvent(this.sessionId);

  @override
  List<Object?> get props => [sessionId];
}

class SessionStateChangedEvent extends ConnectionEvent {
  final dynamic state;
  const SessionStateChangedEvent(this.state);

  @override
  List<Object?> get props => [state];
}

class ResetConnectionEvent extends ConnectionEvent {}

class SendMessageEvent extends ConnectionEvent {
  final Map<String, dynamic> payload;
  const SendMessageEvent(this.payload);

  @override
  List<Object?> get props => [payload];
}

class MessageReceivedEvent extends ConnectionEvent {
  final Map<String, dynamic> payload;
  const MessageReceivedEvent(this.payload);

  @override
  List<Object?> get props => [payload];
}

class ServerErrorEvent extends ConnectionEvent {
  final String message;
  const ServerErrorEvent(this.message);

  @override
  List<Object?> get props => [message];
}

class StatusUpdateEvent extends ConnectionEvent {
  final String message;
  const StatusUpdateEvent(this.message);

  @override
  List<Object?> get props => [message];
}
