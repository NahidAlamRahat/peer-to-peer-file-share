import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class SignalingService {
  final String serverUrl = 'wss://p2p-signaling-server-jy7j.onrender.com';

  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  bool _isConnected = false;
  bool _disposed = false;
  int _reconnectAttempts = 0;
  Timer? _heartbeatTimer;
  static const int _maxReconnectAttempts = 5;

  // Callbacks
  Function(dynamic sessionData)? onSessionCreated;
  Function(dynamic sessionData)? onSessionJoined;
  Function(dynamic sessionData)? onSessionError;
  Function(dynamic offerData)? onOfferReceived;
  Function(dynamic answerData)? onAnswerReceived;
  Function(dynamic candidateData)? onIceCandidateReceived;
  Function(dynamic data)? onPeerDisconnected;
  Function(dynamic data)? onMessageReceived;
  Function(String clientId)? onRegistered;
  Function(String error)? onConnectionError;

  bool get isConnected => _isConnected;

  void connect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();

    // Close old channel cleanly before reconnecting
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _isConnected = false;

    try {
      debugPrint('Attempting to connect to signaling server... (attempt ${_reconnectAttempts + 1})');
      final uri = Uri.parse(serverUrl);
      _channel = WebSocketChannel.connect(uri);

      // The connection result is async; listen to check for errors
      _channel!.stream.listen(
        (message) {
          debugPrint('📥 [WS-RECV] $message');
          if (!_isConnected) {
            _isConnected = true;
            _reconnectAttempts = 0;
            debugPrint('✅ [WS] Connected to signaling server');
          }
          _handleMessage(message as String);
        },
        onDone: () {
          debugPrint('🔌 [WS] Connection closed.');
          _isConnected = false;
          if (!_disposed) _scheduleReconnect();
        },
        onError: (error) {
          debugPrint('❌ [WS-ERR] $error');
          _isConnected = false;
          final errMsg = _friendlyError(error);
          onConnectionError?.call(errMsg);
          if (onSessionError != null) {
            onSessionError!({'message': errMsg});
          }
          if (!_disposed) _scheduleReconnect();
        },
        cancelOnError: false,
      );

      // Verify the channel is writable by doing a ready check (non-blocking)
      _channel!.ready.then((_) {
        if (!_disposed && !_isConnected) { // Check _isConnected to avoid double logging if stream.listen already set it
          _isConnected = true;
          _reconnectAttempts = 0;
          debugPrint('✅ [WS] Connected to signaling server (ready check)');
          _startHeartbeat();
        }
      }).catchError((error) {
        if (_disposed) return;
        _isConnected = false;
        debugPrint('❌ [WS-ERR] WebSocket ready error: $error');
        final errMsg = _friendlyError(error);
        onConnectionError?.call(errMsg);
        if (onSessionError != null) {
          onSessionError!({'message': errMsg});
        }
        _scheduleReconnect();
      });
    } catch (e) {
      _isConnected = false;
      debugPrint('❌ [WS-ERR] Error connecting to signaling server: $e');
      final errMsg = _friendlyError(e);
      onConnectionError?.call(errMsg);
      if (onSessionError != null) {
        onSessionError!({'message': errMsg});
      }
      if (!_disposed) _scheduleReconnect();
    }
  }

  String _friendlyError(dynamic error) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('404')) {
      return 'Signaling server not found (404). Server may be starting up — retrying...';
    } else if (msg.contains('connection refused') || msg.contains('errno = 111')) {
      return 'Cannot reach signaling server. Check your internet connection.';
    } else if (msg.contains('timeout')) {
      return 'Connection timed out. Retrying...';
    }
    return 'Unable to connect to server. Retrying...';
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();

    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('Max reconnect attempts reached. Giving up.');
      onConnectionError?.call(
        'Could not connect to signaling server after $_maxReconnectAttempts attempts. '
        'Please check your internet and try again.',
      );
      return;
    }

    _reconnectAttempts++;
    // Exponential back-off: 3s, 6s, 12s, 24s, 30s (capped)
    final delay = Duration(seconds: (_reconnectAttempts * 3).clamp(3, 30));
    debugPrint('Retrying connection in ${delay.inSeconds}s (attempt $_reconnectAttempts/$_maxReconnectAttempts)...');
    _reconnectTimer = Timer(delay, () {
      if (!_disposed) connect();
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
      if (_isConnected) {
        _send({'type': 'ping'});
      } else {
        timer.cancel();
      }
    });
  }

  void _handleMessage(String message) {
    try {
      final Map<String, dynamic> data = jsonDecode(message);
      final String type = data['type'] ?? '';

      switch (type) {
        case 'session-created':
          if (onSessionCreated != null) onSessionCreated!(data);
          break;
        case 'session-joined':
          if (onSessionJoined != null) onSessionJoined!(data);
          break;
        case 'registered':
          if (onRegistered != null) onRegistered!(data['clientId']);
          break;
        case 'error':
          if (onSessionError != null) onSessionError!(data);
          break;
        case 'offer':
          if (onOfferReceived != null) onOfferReceived!(data);
          break;
        case 'answer':
          if (onAnswerReceived != null) onAnswerReceived!(data);
          break;
        case 'candidate':
          if (onIceCandidateReceived != null) onIceCandidateReceived!(data);
          break;
        case 'peer-disconnected':
          if (onPeerDisconnected != null) onPeerDisconnected!(data);
          break;
        case 'message':
          if (onMessageReceived != null) onMessageReceived!(data);
          break;
        case 'ping':
          _send({'type': 'pong'});
          break;
        case 'pong':
          // Heartbeat received
          break;
        default:
          debugPrint('Unknown message type: $type');
      }
    } catch (e) {
      debugPrint('Failed to parse message: $e');
    }
  }

  void createSession() {
    _send({'type': 'create-session'});
  }

  void joinSession(String sessionId) {
    _send({'type': 'join-session', 'sessionId': sessionId});
  }

  void sendOffer(String sessionId, Map<String, dynamic> offer) {
    _send({'type': 'offer', 'sessionId': sessionId, 'sdp': offer});
  }

  void sendAnswer(String sessionId, Map<String, dynamic> answer) {
    _send({'type': 'answer', 'sessionId': sessionId, 'sdp': answer});
  }

  void sendIceCandidate(String sessionId, Map<String, dynamic> candidate) {
    _send({'type': 'candidate', 'sessionId': sessionId, 'candidate': candidate});
  }

  void sendMessage(String sessionId, Map<String, dynamic> payload) {
    _send({'type': 'message', 'sessionId': sessionId, 'payload': payload});
  }

  void _send(Map<String, dynamic> data) {
    if (_channel != null && _isConnected) {
      try {
        final jsonMsg = jsonEncode(data);
        debugPrint('📤 [WS-SEND] $jsonMsg');
        _channel!.sink.add(jsonMsg);
      } catch (e) {
        debugPrint('❌ [WS-ERR] Failed to send message: $e');
      }
    } else {
      debugPrint('⚠️ [WS] Cannot send message — not connected.');
    }
  }

  void dispose() {
    _disposed = false; // Never permanently dispose the singleton
    _isConnected = false;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _reconnectAttempts = 0;
    
    // Clear session-specific callbacks so they don't fire inappropriately on the next session
    onSessionCreated = null;
    onSessionJoined = null;
    onSessionError = null;
    onOfferReceived = null;
    onAnswerReceived = null;
    onIceCandidateReceived = null;
    onPeerDisconnected = null;
    onMessageReceived = null;
    onRegistered = null;
    onConnectionError = null;

    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }
}
