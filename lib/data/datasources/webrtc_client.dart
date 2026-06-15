import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class WebRTCClient {
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;

  // Configuration for WebRTC with robust NAT traversal (Global STUN + TURN)
  // TURN servers are required for mobile data (Symmetric NAT) connections.
  // Using personal metered.ca TURN credentials (20GB/month free)
  final Map<String, dynamic> _configuration = {
    'iceServers': [
      // STUN servers (works on WiFi & simple NAT)
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      // TURN servers — required for mobile data (Symmetric NAT / 4G)
      // Personal metered.ca credentials — 20 GB/month free
      //
      // ORDER MATTERS: WebRTC tries candidates top-to-bottom.
      // TCP TURN (port 443) listed first because:
      //   • Mobile carriers often block/throttle UDP
      //   • TCP is more reliable on congested 4G networks
      //   • Port 443 passes through most firewalls (HTTPS port)
      {
        'urls': 'turns:a.relay.metered.ca:443',  // TCP+TLS — most reliable on mobile
        'username': 'a5eaa03ef3aef5dd7dbd66c9',
        'credential': 'QwG/QE1Gg4K2UfRz',
      },
      {
        'urls': 'turn:a.relay.metered.ca:443',    // TCP — fallback
        'username': 'a5eaa03ef3aef5dd7dbd66c9',
        'credential': 'QwG/QE1Gg4K2UfRz',
      },
      {
        'urls': 'turn:a.relay.metered.ca:80?transport=tcp',
        'username': 'a5eaa03ef3aef5dd7dbd66c9',
        'credential': 'QwG/QE1Gg4K2UfRz',
      },
      {
        'urls': 'turn:a.relay.metered.ca:80',     // UDP — fastest but less reliable on 4G
        'username': 'a5eaa03ef3aef5dd7dbd66c9',
        'credential': 'QwG/QE1Gg4K2UfRz',
      },
    ],
    'sdpSemantics': 'unified-plan',
    'iceTransportPolicy': 'all',
    // Aggressive ICE restart on connection drop
    'iceCandidatePoolSize': 10,
  };

  // Callbacks
  Function(RTCIceCandidate candidate)? onIceCandidate;
  Function(RTCDataChannelState state)? onDataChannelState;
  Function(RTCDataChannelMessage message)? onDataMessage;
  Function(RTCPeerConnectionState state)? onConnectionState;
  Function(int amount)? onBufferedAmountLow;

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
    _dataChannel?.close();
    _peerConnection?.close();
    _dataChannel = null;
    _peerConnection = null;
    _initialized = false; // Allow re-initialization for next session
  }
}
