import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../domain/entities/peer_session.dart';
import '../../domain/repositories/peer_repository.dart';
import '../datasources/signaling_service.dart';
import '../datasources/webrtc_client.dart';

class PeerRepositoryImpl implements PeerRepository {
  final SignalingService _signalingService;
  final WebRTCClient _webrtcClient;

  // Use non-closing broadcast controllers (singletons live for app lifetime)
  final _sessionStateController = StreamController<SessionState>.broadcast();
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _serverErrorController = StreamController<String>.broadcast();
  final _statusMessageController = StreamController<String>.broadcast();

  Completer<String>? _createSessionCompleter;
  String? _currentSessionId;
  SessionRole? _currentRole;
  Timer? _disconnectTimer; // Debounce for temporary WebRTC disconnects
  String? _pendingJoinSessionId; // Retry join after reconnect

  // ── TURN Fallback State ──
  final List<Map<String, dynamic>> _queuedRelayCandidates = [];
  Timer? _relayFallbackTimer;
  bool _fallbackTriggered = false;

  PeerRepositoryImpl(this._signalingService, this._webrtcClient);

  @override
  Future<String> get activeConnectionType async => await _webrtcClient.getSelectedCandidateType();

  @override
  Stream<SessionState> get sessionStateStream => _sessionStateController.stream;

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  Stream<String> get serverErrorStream => _serverErrorController.stream;
  Stream<String> get statusMessageStream => _statusMessageController.stream;

  bool _listenersSetup = false;

  @override
  Future<void> initialize() async {
    // Only connect the WebSocket — fast, non-blocking
    if (!_signalingService.isConnected) {
      _signalingService.connect();
    }
    // WebRTC initialized lazily on first session — NOT here
    if (!_listenersSetup) {
      _setupListeners();
      _listenersSetup = true;
    }
  }

  void _setupListeners() {
    _signalingService.onSessionCreated = (data) async {
      _currentSessionId = data['sessionId'];
      _currentRole = SessionRole.sender;
      _sessionStateController.add(SessionState.connecting);
      if (_createSessionCompleter != null &&
          !_createSessionCompleter!.isCompleted) {
        _createSessionCompleter!.complete(_currentSessionId!);
      }
      _startRelayFallbackTimer();
      await _webrtcClient.createDataChannel();
    };

    _signalingService.onSessionJoined = (data) async {
      if (_currentRole == SessionRole.sender) {
        RTCSessionDescription offer = await _webrtcClient.createOffer();
        _signalingService.sendOffer(_currentSessionId!, offer.toMap());
      }
      // Receiver just waits for the offer
      _startRelayFallbackTimer();
    };

    _signalingService.onOfferReceived = (data) async {
      final sdp = data['sdp'];
      await _webrtcClient.setRemoteDescription(
        RTCSessionDescription(sdp['sdp'], sdp['type']),
      );
      RTCSessionDescription answer = await _webrtcClient.createAnswer();
      _signalingService.sendAnswer(_currentSessionId!, answer.toMap());
    };

    _signalingService.onAnswerReceived = (data) async {
      final sdp = data['sdp'];
      await _webrtcClient.setRemoteDescription(
        RTCSessionDescription(sdp['sdp'], sdp['type']),
      );
    };

    _signalingService.onIceCandidateReceived = (data) async {
      final candidateMap = data['candidate'];
      final candidate = RTCIceCandidate(
        candidateMap['candidate'],
        candidateMap['sdpMid'],
        candidateMap['sdpMLineIndex'],
      );
      await _webrtcClient.addCandidate(candidate);
    };

    _webrtcClient.onIceCandidate = (candidate) {
      if (_currentSessionId != null) {
        final candidateMap = candidate.toMap();
        final candidateString = candidateMap['candidate'] as String? ?? '';
        
        // If it's a TURN relay candidate, queue it instead of sending immediately.
        if (candidateString.contains('typ relay') && !_fallbackTriggered) {
          debugPrint('⏳ [TURN] Holding relay candidate (STUN priority).');
          _queuedRelayCandidates.add(candidateMap);
        } else {
          _signalingService.sendIceCandidate(
            _currentSessionId!,
            candidateMap,
          );
        }
      }
    };

    _webrtcClient.onConnectionState = (state) {
      debugPrint('🔌 [WebRTC] Connection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _disconnectTimer?.cancel();
        _disconnectTimer = null;
        _pendingJoinSessionId = null; // Join succeeded — no need to retry
        _sessionStateController.add(SessionState.connected);
        
        // Direct P2P succeeded! Cancel fallback and drop relay candidates.
        _relayFallbackTimer?.cancel();
        if (!_fallbackTriggered) {
          debugPrint('✅ [TURN] Direct P2P connected. Dropping ${_queuedRelayCandidates.length} relay candidates.');
          _queuedRelayCandidates.clear();
        }
      } else if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        // WebRTC DISCONNECTED is usually temporary (ICE restart).
        // Wait 5 seconds before treating it as truly failed.
        _disconnectTimer ??= Timer(const Duration(seconds: 5), () {
          _disconnectTimer = null;
          debugPrint(
            '⏰ [WebRTC] Disconnect grace period expired — marking as failed.',
          );
          _sessionStateController.add(SessionState.failed);
        });
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _disconnectTimer?.cancel();
        _disconnectTimer = null;
        _sessionStateController.add(SessionState.failed);
      }
    };

    _signalingService.onSessionError = (data) {
      final msg = data['message']?.toString() ?? 'Session error';
      debugPrint('❌ [REPO] Signaling session error: $msg');
      // Propagate to UI — e.g. "session not found", "session full", etc.
      _pendingJoinSessionId = null; // Don't retry on server-side error
      _sessionStateController.add(SessionState.failed);
      _serverErrorController.add(msg);
    };

    _signalingService.onConnectionError = (errMsg) {
      debugPrint('Signaling server connection error: $errMsg');
      _serverErrorController.add(errMsg);
    };

    _signalingService.onRegistered = (clientId) {
      debugPrint('Registered with client ID: $clientId');
      _statusMessageController.add(
        'Server connection established. Ready to share.',
      );
      // If we were in the middle of joining a session before disconnect, retry now
      if (_pendingJoinSessionId != null) {
        debugPrint(
          '🔄 [REPO] Retrying pending join for session: $_pendingJoinSessionId',
        );
        _signalingService.joinSession(_pendingJoinSessionId!);
      }
    };

    _signalingService.onPeerDisconnected = (data) {
      debugPrint("Peer disconnected");
      _pendingJoinSessionId = null; // Session ended — stop retrying
      _sessionStateController.add(SessionState.offline);
    };

    _signalingService.onMessageReceived = (data) {
      _messageController.add(data['payload']);
    };
  }

  void sendSignalingMessage(Map<String, dynamic> payload) {
    if (_currentSessionId != null) {
      _signalingService.sendMessage(_currentSessionId!, payload);
    }
  }

  @override
  Future<String> createSession() async {
    debugPrint('🔑 [REPO] Requesting to create session...');

    // Initialize WebRTC lazily on first use
    await _webrtcClient.initialize();

    if (!_signalingService.isRegistered) {
      debugPrint(
        '⏳ [REPO] Not registered yet — waiting before creating session...',
      );
      if (!_signalingService.isConnected) {
        _signalingService.connect();
      }
      const maxWait = Duration(seconds: 20);
      const checkInterval = Duration(milliseconds: 300);
      final deadline = DateTime.now().add(maxWait);
      while (!_signalingService.isRegistered &&
          DateTime.now().isBefore(deadline)) {
        await Future.delayed(checkInterval);
      }
    }

    _currentRole = SessionRole.sender;
    _createSessionCompleter = Completer<String>();

    _signalingService.createSession();

    return Future.any([
      _createSessionCompleter!.future,
      Future.delayed(
        const Duration(seconds: 15),
        () => throw 'Timeout creating session',
      ),
    ]).whenComplete(() {
      _createSessionCompleter = null;
    });
  }

  @override
  Future<void> joinSession(String sessionId) async {
    debugPrint('🔗 [REPO] Attempting to join session: $sessionId');

    // Initialize WebRTC lazily on first use
    await _webrtcClient.initialize();

    _currentRole = SessionRole.receiver;
    _currentSessionId = sessionId;
    _pendingJoinSessionId = sessionId; // Track for auto-retry on reconnect
    _sessionStateController.add(SessionState.connecting);

    // Wait until the server sends 'registered' — only then is it safe to join.
    if (!_signalingService.isRegistered) {
      debugPrint('⏳ [REPO] Not registered with server yet — waiting...');
      if (!_signalingService.isConnected) {
        _signalingService.connect();
      }
      const maxWait = Duration(seconds: 20);
      const checkInterval = Duration(milliseconds: 300);
      final deadline = DateTime.now().add(maxWait);
      while (!_signalingService.isRegistered &&
          DateTime.now().isBefore(deadline)) {
        await Future.delayed(checkInterval);
      }
      if (!_signalingService.isRegistered) {
        debugPrint('❌ [REPO] Timed out waiting for server registration.');
        _pendingJoinSessionId = null;
        _sessionStateController.add(SessionState.failed);
        throw Exception('Server unreachable. Please check your internet connection.');
      }
      debugPrint('✅ [REPO] Registered with server — now sending join-session.');
    }

    _signalingService.joinSession(sessionId);

    // After sending the join, wait up to 30s for WebRTC to establish.
    // If it doesn't connect in time, treat as failed.
    const connectTimeout = Duration(seconds: 30);
    final connectDeadline = DateTime.now().add(connectTimeout);
    while (_pendingJoinSessionId == sessionId && DateTime.now().isBefore(connectDeadline)) {
      await Future.delayed(const Duration(seconds: 1));
    }
    // If still pending (never connected, never errored), mark as failed
    if (_pendingJoinSessionId == sessionId) {
      debugPrint('⏰ [REPO] WebRTC connection timed out after 30s.');
      _pendingJoinSessionId = null;
      _sessionStateController.add(SessionState.failed);
      throw Exception('Connection timed out. Please make sure the sender is still waiting on the Share screen.');
    }
  }

  void resetSession() {
    _createSessionCompleter = null;
    _currentSessionId = null;
    _currentRole = null;
    _sessionStateController.add(SessionState.disconnected);
    _webrtcClient.dispose();
    
    _relayFallbackTimer?.cancel();
    _relayFallbackTimer = null;
    _queuedRelayCandidates.clear();
    _fallbackTriggered = false;
  }

  void _startRelayFallbackTimer() {
    _relayFallbackTimer?.cancel();
    _fallbackTriggered = false;
    _queuedRelayCandidates.clear();
    
    // Give STUN 5 seconds to establish a direct connection
    _relayFallbackTimer = Timer(const Duration(seconds: 5), () {
      if (_currentSessionId == null) return;
      
      _fallbackTriggered = true;
      if (_queuedRelayCandidates.isNotEmpty) {
        debugPrint('⏱️ [TURN] 5s STUN timeout. Releasing ${_queuedRelayCandidates.length} relay candidates...');
        for (final candidate in _queuedRelayCandidates) {
          _signalingService.sendIceCandidate(_currentSessionId!, candidate);
        }
        _queuedRelayCandidates.clear();
      }
    });
  }

  @override
  Future<void> dispose() async {
    debugPrint('🗑️ [REPO] Disposing session state');
    _disconnectTimer?.cancel();
    _disconnectTimer = null;
    _currentSessionId = null;
    _currentRole = null;
    _createSessionCompleter = null;
    _pendingJoinSessionId = null; // Clear pending join
    _webrtcClient.dispose();
  }
}
