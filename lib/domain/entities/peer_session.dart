import 'package:equatable/equatable.dart';

enum SessionRole { sender, receiver }
enum SessionState { disconnected, connecting, connected, failed, offline }

class PeerSession extends Equatable {
  final String sessionId;
  final SessionRole role;
  final SessionState state;

  const PeerSession({
    required this.sessionId,
    required this.role,
    this.state = SessionState.disconnected,
  });

  PeerSession copyWith({
    String? sessionId,
    SessionRole? role,
    SessionState? state,
  }) {
    return PeerSession(
      sessionId: sessionId ?? this.sessionId,
      role: role ?? this.role,
      state: state ?? this.state,
    );
  }

  @override
  List<Object?> get props => [sessionId, role, state];
}
