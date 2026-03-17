import '../entities/peer_session.dart';

abstract class PeerRepository {
  /// Initialize the peer connection
  Future<void> initialize();

  /// Start a session as sender and return the generated Session ID
  Future<String> createSession();

  /// Join an existing session as a receiver using the Session ID
  Future<void> joinSession(String sessionId);

  /// Close the connection and clean up resources
  Future<void> dispose();

  /// Stream of session state changes
  Stream<SessionState> get sessionStateStream;
}
