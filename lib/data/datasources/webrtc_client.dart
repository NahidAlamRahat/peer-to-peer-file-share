import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class WebRTCClient {
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;

  // Configuration for WebRTC with robust NAT traversal (Global STUN + TURN)
  // TURN servers are required for mobile data (Symmetric NAT) connections.
  // Using Metered.ca Open Relay — free public TURN, no account needed,
  // no bandwidth kill (unlike ExpressTURN which cut connections after 10-20MB).
  final Map<String, dynamic> _configuration = {
    'iceServers': [
      // ── STUN servers ────────────────────────────────────────────────────────
      // Used for WiFi→WiFi and simple NAT traversal (no relay needed).
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},

      // ── TURN servers (Metered.ca Open Relay) ────────────────────────────────
      // Required for 4G→4G, 5G→5G, and any Symmetric NAT connection.
      // Open Relay is a free public service — no account, no connection kill.
      // Multiple ports/protocols for maximum compatibility across all carriers.
      {
        'urls': 'turn:openrelay.metered.ca:80',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': 'turn:openrelay.metered.ca:443',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': 'turn:openrelay.metered.ca:443?transport=tcp',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': 'turn:openrelay.metered.ca:80?transport=tcp',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ],
    'sdpSemantics': 'unified-plan',
    'iceTransportPolicy': 'all',
    'iceCandidatePoolSize': 10,
  };

  // Callbacks
  Function(RTCIceCandidate candidate)? onIceCandidate;
  Function(RTCDataChannelState state)? onDataChannelState;
  Function(RTCDataChannelMessage message)? onDataMessage;
  Function(RTCPeerConnectionState state)? onConnectionState;
  Function(int amount)? onBufferedAmountLow;

  // Buffer drain completer — resolves when bufferedAmount drops below threshold
  Completer<void>? _bufferDrainCompleter;

  // High-water mark: if bufferedAmount exceeds this, block sending
  // 256 KB is safe — Android SCTP limit is 16 MB but we stay far below
  static const int _bufferHighWaterMark = 262144; // 256 KB
  static const int _bufferLowWaterMark  = 65536;  //  64 KB

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized && _peerConnection != null) return; // Already ready

    // Close previous connection if it exists (safe re-initialization)
    _dataChannel?.close();
    await _peerConnection?.close();
    _dataChannel = null;
    _peerConnection = null;

    _peerConnection = await createPeerConnection(_configuration, {});

    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (onIceCandidate != null) {
        onIceCandidate!(candidate);
      }
    };

    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      if (onConnectionState != null) {
        onConnectionState!(state);
      }
    };

    // When we're receiver, we handle the datachannel created by the sender
    _peerConnection!.onDataChannel = (RTCDataChannel channel) {
      _dataChannel = channel;
      _setupDataChannelListeners();
    };

    _initialized = true;
  }

  Future<void> createDataChannel() async {
    if (_peerConnection == null) return;

    final RTCDataChannelInit dataChannelDict = RTCDataChannelInit()
      ..ordered = true       // Ordered delivery — essential for file integrity
      ..protocol = 'p2p-ft'; // Named protocol for easier debugging

    _dataChannel = await _peerConnection!.createDataChannel(
      'file_transfer_channel',
      dataChannelDict,
    );
    _setupDataChannelListeners();
  }

  void _setupDataChannelListeners() {
    _dataChannel?.onDataChannelState = (RTCDataChannelState state) {
      if (onDataChannelState != null) {
        onDataChannelState!(state);
      }
    };

    _dataChannel?.onMessage = (RTCDataChannelMessage message) {
      if (onDataMessage != null) {
        onDataMessage!(message);
      }
    };

    _dataChannel?.onBufferedAmountLow = (int amount) {
      // Unblock any sender waiting for buffer to drain
      if (_bufferDrainCompleter != null && !_bufferDrainCompleter!.isCompleted) {
        _bufferDrainCompleter!.complete();
      }
      if (onBufferedAmountLow != null) {
        onBufferedAmountLow!(amount);
      }
    };
  }

  int get bufferedAmount => _dataChannel?.bufferedAmount ?? 0;
  RTCDataChannelState? get dataChannelState => _dataChannel?.state;

  void setBufferedAmountLowThreshold(int threshold) {
    _dataChannel?.bufferedAmountLowThreshold = threshold;
  }

  /// Blocks until the DataChannel's send buffer drains below [_bufferLowWaterMark].
  /// This prevents SCTP buffer overflow which crashes the data channel on Android.
  /// Call this before every sendDataMessageBinary() call.
  Future<void> waitForBufferDrain() async {
    if (_dataChannel == null) return;
    // If buffer is already below high water mark, send immediately
    if ((_dataChannel?.bufferedAmount ?? 0) < _bufferHighWaterMark) return;

    // Set low-water threshold so onBufferedAmountLow fires when safe
    _dataChannel?.bufferedAmountLowThreshold = _bufferLowWaterMark;

    // Wait for the low event
    _bufferDrainCompleter ??= Completer<void>();
    await _bufferDrainCompleter!.future;
    _bufferDrainCompleter = null;
  }

  Future<RTCSessionDescription> createOffer() async {
    RTCSessionDescription offer = await _peerConnection!.createOffer({});
    await _peerConnection!.setLocalDescription(offer);
    return offer;
  }

  Future<RTCSessionDescription> createAnswer() async {
    RTCSessionDescription answer = await _peerConnection!.createAnswer({});
    await _peerConnection!.setLocalDescription(answer);
    return answer;
  }

  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    await _peerConnection!.setRemoteDescription(description);
  }

  Future<void> addCandidate(RTCIceCandidate candidate) async {
    await _peerConnection!.addCandidate(candidate);
  }

  void sendDataMessage(RTCDataChannelMessage message) {
    if (_dataChannel != null && _dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
      _dataChannel!.send(message);
    }
  }
  
  void sendDataMessageBinary(Uint8List bytes) {
    if (_dataChannel != null && _dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
      _dataChannel!.send(RTCDataChannelMessage.fromBinary(bytes));
    }
  }

  /// Returns the ICE candidate type of the active (nominated) connection:
  ///   'host'  → local network direct P2P  (fastest — same WiFi/hotspot)
  ///   'srflx' → STUN reflexive direct P2P (fast — different network, NAT traversal)
  ///   'relay' → TURN relay server         (limited by TURN bandwidth)
  ///   'unknown' → stats not available yet
  ///
  /// This is the only reliable way to know if data is going through TURN,
  /// because connectivity_plus only reports the local network type (WiFi/mobile)
  /// and cannot detect whether WebRTC chose a TURN relay path regardless.
  Future<String> getSelectedCandidateType() async {
    if (_peerConnection == null) return 'unknown';
    try {
      final stats = await _peerConnection!.getStats();

      // Step 1: Find the nominated (active) candidate-pair
      String? activePairLocalId;
      String? activePairRemoteId;
      for (final stat in stats) {
        if (stat.type == 'candidate-pair') {
          final nominated = stat.values['nominated'];
          final state = stat.values['state'];
          // 'nominated' is the definitive signal; fall back to 'succeeded' state
          if (nominated == true || state == 'succeeded') {
            activePairLocalId = stat.values['localCandidateId'] as String?;
            activePairRemoteId = stat.values['remoteCandidateId'] as String?;
            if (activePairLocalId != null || activePairRemoteId != null) break;
          }
        }
      }

      if (activePairLocalId == null && activePairRemoteId == null) return 'unknown';

      // Step 2: Look up the candidates to read their types
      String localType = 'unknown';
      String remoteType = 'unknown';

      for (final stat in stats) {
        if (stat.type == 'local-candidate' && stat.id == activePairLocalId) {
          localType = stat.values['candidateType'] as String? ?? 'unknown';
        } else if (stat.type == 'remote-candidate' && stat.id == activePairRemoteId) {
          remoteType = stat.values['candidateType'] as String? ?? 'unknown';
        }
      }

      debugPrint('🔍 [ICE] Active candidate pair: local=$localType, remote=$remoteType');

      if (localType == 'relay' || remoteType == 'relay') {
        return 'relay';
      }
      
      // If neither is relay, just return the local type as fallback
      return localType != 'unknown' ? localType : remoteType;
    } catch (e) {
      debugPrint('⚠️ [ICE] getStats() error: $e');
    }
    return 'unknown';
  }

  void dispose() {
    // Unblock any pending waitForBufferDrain() so the send loop exits cleanly
    if (_bufferDrainCompleter != null && !_bufferDrainCompleter!.isCompleted) {
      _bufferDrainCompleter!.completeError(Exception('Disposed'));
    }
    _bufferDrainCompleter = null;
    _dataChannel?.close();
    _peerConnection?.close();
    _dataChannel = null;
    _peerConnection = null;
    _initialized = false; // Allow re-initialization for next session
  }
}
