import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:typed_data';

class WebRTCClient {
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;

  // Configuration for WebRTC with robust NAT traversal (Global STUN + TURN)
  final Map<String, dynamic> _configuration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun3.l.google.com:19302'},
      {'urls': 'stun:stun4.l.google.com:19302'},
      {'urls': 'stun:stun.stunprotocol.org:3478'},
      // --- ADD YOUR TURN SERVERS HERE FOR PRODUCTION ---
      // {
      //   'urls': 'turn:YOUR_TURN_SERVER_URL:3478',
      //   'username': 'YOUR_USERNAME',
      //   'credential': 'YOUR_PASSWORD'
      // },
    ],
    'sdpSemantics': 'unified-plan',
    'iceTransportPolicy': 'all',
  };

  // Callbacks
  Function(RTCIceCandidate candidate)? onIceCandidate;
  Function(RTCDataChannelState state)? onDataChannelState;
  Function(RTCDataChannelMessage message)? onDataMessage;
  Function(RTCPeerConnectionState state)? onConnectionState;
  Function(int amount)? onBufferedAmountLow;

  Future<void> initialize() async {
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
  }

  Future<void> createDataChannel() async {
    if (_peerConnection == null) return;
    
    RTCDataChannelInit dataChannelDict = RTCDataChannelInit()
      ..ordered = true; // We want an ordered channel for file chunks

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
  
  void sendDataMessageBinary(List<int> bytes) {
    if (_dataChannel != null && _dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
      _dataChannel!.send(RTCDataChannelMessage.fromBinary(Uint8List.fromList(bytes)));
    }
  }

  void dispose() {
    _dataChannel?.close();
    _peerConnection?.close();
    _dataChannel = null;
    _peerConnection = null;
  }
}
