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

  final _sessionStateController = StreamController<SessionState>.broadcast();
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _serverErrorController = StreamController<String>.broadcast();
  final _statusMessageController = StreamController<String>.broadcast();
  
  Completer<String>? _createSessionCompleter;
  String? _currentSessionId;
  SessionRole? _currentRole;

  PeerRepositoryImpl(this._signalingService, this._webrtcClient);

  @override
  Stream<SessionState> get sessionStateStream => _sessionStateController.stream;

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  /// Emits a user-friendly error string when the signaling server is unreachable
  Stream<String> get serverErrorStream => _serverErrorController.stream;

  /// Emits granular status messages (e.g. "Registering...", "Ready")
  Stream<String> get statusMessageStream => _statusMessageController.stream;

  @override
  Future<void> initialize() async {
    _signalingService.connect();
    await _webrtcClient.initialize();
    _setupListeners();
  }

  void _setupListeners() {
    _signalingService.onSessionCreated = (data) async {
      _currentSessionId = data['sessionId'];
      _currentRole = SessionRole.sender;
      
      // Update UI state to connecting
      _sessionStateController.add(SessionState.connecting);

      // Resolve the creation completer if exists
      if (_createSessionCompleter != null && !_createSessionCompleter!.isCompleted) {
        _createSessionCompleter!.complete(_currentSessionId!);
      }

      // We are sender, we offer.
      await _webrtcClient.createDataChannel();
    };

    _signalingService.onSessionJoined = (data) async {
      if (_currentRole == SessionRole.sender) {
        // We are the sender, someone joined. Create an offer and send it.
        RTCSessionDescription offer = await _webrtcClient.createOffer();
        _signalingService.sendOffer(_currentSessionId!, offer.toMap());
      } else {
        // We are the receiver, we just successfully joined.
        // Wait for offer from sender.
      }
    };

    _signalingService.onOfferReceived = (data) async {
      final sdp = data['sdp'];
      await _webrtcClient.setRemoteDescription(
        RTCSessionDescription(sdp['sdp'], sdp['type'])
      );

      RTCSessionDescription answer = await _webrtcClient.createAnswer();
      _signalingService.sendAnswer(_currentSessionId!, answer.toMap());
    };

    _signalingService.onAnswerReceived = (data) async {
      final sdp = data['sdp'];
      await _webrtcClient.setRemoteDescription(
        RTCSessionDescription(sdp['sdp'], sdp['type'])
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
        _signalingService.sendIceCandidate(_currentSessionId!, candidate.toMap());
      }
    };

    _webrtcClient.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _sessionStateController.add(SessionState.connected);
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
                 state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _sessionStateController.add(SessionState.failed);
      }
    };
    
    _signalingService.onSessionError = (data) {
      debugPrint("Signaling Error: ${data['message']}");
      // Don't emit SessionState.failed here — that would block the UI
      // before any action is taken (it's a background reconnect loop).
    };

    _signalingService.onConnectionError = (errMsg) {
      debugPrint('Signaling server connection error: $errMsg');
      if (!_serverErrorController.isClosed) {
        _serverErrorController.add(errMsg);
      }
    };

    _signalingService.onRegistered = (clientId) {
      debugPrint('Registered with client ID: $clientId');
      if (!_statusMessageController.isClosed) {
        _statusMessageController.add('Server connection established. Ready to share.');
      }
    };

    _signalingService.onPeerDisconnected = (data) {
      debugPrint("Peer disconnected");
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
    
    // Proactively check connection
    if (!_signalingService.isConnected) {
      debugPrint('⚠️ [REPO] Not connected. Attempting quick reconnect...');
      _signalingService.connect();
      // Wait a bit for connection
      await Future.delayed(const Duration(seconds: 2));
    }

    _currentRole = SessionRole.sender;
    _createSessionCompleter = Completer<String>();
    
    _signalingService.createSession();
    
    return Future.any([
      _createSessionCompleter!.future,
      Future.delayed(const Duration(seconds: 15), () => throw 'Timeout creating session'),
    ]).whenComplete(() {
      _createSessionCompleter = null;
    });
  }

  @override
  Future<void> joinSession(String sessionId) async {
    debugPrint('🔗 [REPO] Attempting to join session: $sessionId');
    _currentRole = SessionRole.receiver;
    _currentSessionId = sessionId;
    _sessionStateController.add(SessionState.connecting);
    _signalingService.joinSession(sessionId);
  }

  @override
  Future<void> dispose() async {
    debugPrint('🗑️ [REPO] Disposing PeerRepositoryImpl');
    _signalingService.dispose();
    _webrtcClient.dispose();
    await _sessionStateController.close();
    await _messageController.close();
    await _serverErrorController.close();
    await _statusMessageController.close();
  }
}
