import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../data/datasources/webrtc_client.dart';

/// Manages completely offline WebRTC signaling by exchanging compressed SDP
/// strings instead of using a WebSocket server.
///
/// Flow (same-WiFi, no internet needed):
///   Sender   → [createOfferCode]              → shows QR / code to receiver
///   Receiver → [processOfferAndCreateAnswer]  → shows QR / code to sender
///   Sender   → [processAnswerCode]            → both peers connected!
class OfflineSignalingService {
  final WebRTCClient _webrtcClient;

  Completer<void>? _iceGatheringCompleter;

  // No STUN/TURN → only local (host) candidates → ICE gathering finishes fast
  static const Map<String, dynamic> _offlineIceConfig = {
    'iceServers': [],
    'sdpSemantics': 'unified-plan',
    'iceTransportPolicy': 'all',
    'iceCandidatePoolSize': 0,
  };

  OfflineSignalingService(this._webrtcClient);

  /// [Sender] Creates a WebRTC offer. Waits for ICE gathering to complete
  /// (host candidates embedded in SDP), then returns a compressed code string.
  Future<String> createOfferCode() async {
    await _webrtcClient.initializeOffline(_offlineIceConfig);
    await _webrtcClient.createDataChannel();

    _iceGatheringCompleter = Completer<void>();
    _webrtcClient.onIceGatheringStateChange = _onIceGatheringState;

    await _webrtcClient.createOffer();
    debugPrint('[Offline] Offer created — waiting for ICE gathering...');

    await Future.any([
      _iceGatheringCompleter!.future,
      Future.delayed(const Duration(seconds: 8)),
    ]);

    final sdp = await _webrtcClient.getLocalDescriptionSdp();
    if (sdp == null || sdp.isEmpty) throw Exception('Failed to get offer SDP');
    debugPrint('[Offline] Offer ICE done. SDP len=${sdp.length}');
    return _compress(sdp);
  }

  /// [Receiver] Decodes the sender's offer code, creates an answer, waits for
  /// ICE gathering, then returns the compressed answer code.
  Future<String> processOfferAndCreateAnswer(String offerCode) async {
    final offerSdp = _decompress(offerCode);

    await _webrtcClient.initializeOffline(_offlineIceConfig);
    _iceGatheringCompleter = Completer<void>();
    _webrtcClient.onIceGatheringStateChange = _onIceGatheringState;

    await _webrtcClient.setRemoteDescription(
      RTCSessionDescription(offerSdp, 'offer'),
    );
    await _webrtcClient.createAnswer();
    debugPrint('[Offline] Answer created — waiting for ICE gathering...');

    await Future.any([
      _iceGatheringCompleter!.future,
      Future.delayed(const Duration(seconds: 8)),
    ]);

    final sdp = await _webrtcClient.getLocalDescriptionSdp();
    if (sdp == null || sdp.isEmpty) throw Exception('Failed to get answer SDP');
    debugPrint('[Offline] Answer ICE done. SDP len=${sdp.length}');
    return _compress(sdp);
  }

  /// [Sender] Applies the receiver's answer code to complete the handshake.
  Future<void> processAnswerCode(String answerCode) async {
    final answerSdp = _decompress(answerCode);
    await _webrtcClient.setRemoteDescription(
      RTCSessionDescription(answerSdp, 'answer'),
    );
    debugPrint('[Offline] Answer applied — WebRTC handshake complete!');
  }

  void dispose() {
    _iceGatheringCompleter = null;
    _webrtcClient.onIceGatheringStateChange = null;
  }

  void _onIceGatheringState(RTCIceGatheringState state) {
    debugPrint('[Offline] ICE gathering state: $state');
    if (state == RTCIceGatheringState.RTCIceGatheringStateComplete) {
      if (_iceGatheringCompleter != null && !_iceGatheringCompleter!.isCompleted) {
        _iceGatheringCompleter!.complete();
      }
    }
  }

  String _compress(String sdp) {
    final bytes = utf8.encode(sdp);
    final toEncode = kIsWeb ? bytes : gzip.encode(bytes);
    return base64Url.encode(toEncode).replaceAll('=', '');
  }

  String _decompress(String code) {
    final padded = _padBase64(code);
    final bytes = base64Url.decode(padded);
    final decoded = kIsWeb ? bytes : gzip.decode(bytes);
    return utf8.decode(decoded);
  }

  static String _padBase64(String s) {
    switch (s.length % 4) {
      case 2: return '$s==';
      case 3: return '$s=';
      default: return s;
    }
  }
}
