import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/di/injection_container.dart';
import '../../core/services/offline_signaling_service.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/spacing.dart';
import '../../data/datasources/webrtc_client.dart';
import '../../domain/entities/peer_session.dart';
import '../blocs/connection/connection_bloc.dart';
import '../blocs/connection/connection_event.dart';
import 'transfer_screen.dart';

/// Offline receiver screen — no internet required.
/// Step 1: Scan or paste sender's offer QR / code.
/// Step 2: Show answer QR / code to sender.
/// Step 3: Sender scans answer → both connected → transfer starts.
class OfflineReceiveScreen extends StatefulWidget {
  const OfflineReceiveScreen({super.key});

  @override
  State<OfflineReceiveScreen> createState() => _OfflineReceiveScreenState();
}

enum _Step { scan, generating, showAnswer, connecting }

class _OfflineReceiveScreenState extends State<OfflineReceiveScreen> {
  late final OfflineSignalingService _offlineSvc;
  late final WebRTCClient _webrtcClient;

  _Step _step = _Step.scan;
  String _answerCode = '';
  String _errorMsg = '';

  final _offerController = TextEditingController();
  bool _showManualInput = false;

  @override
  void initState() {
    super.initState();
    _webrtcClient = sl<WebRTCClient>();
    _offlineSvc = OfflineSignalingService(_webrtcClient);

    _webrtcClient.onConnectionState = (state) {
      if (!mounted) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _onConnected();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        setState(() {
          _errorMsg = 'Connection failed. Please ask sender to try again.';
          _step = _Step.showAnswer;
        });
      }
    };
  }

  @override
  void dispose() {
    _offlineSvc.dispose();
    _offerController.dispose();
    super.dispose();
  }

  Future<void> _processOffer(String offerCode) async {
    setState(() { _step = _Step.generating; _errorMsg = ''; });
    try {
      final answer = await _offlineSvc.processOfferAndCreateAnswer(offerCode.trim());
      if (!mounted) return;
      setState(() { _answerCode = answer; _step = _Step.showAnswer; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _errorMsg = 'Invalid offer code: $e'; _step = _Step.scan; });
    }
  }

  void _onConnected() {
    if (!mounted) return;
    context.read<ConnectionBloc>().add(OfflineConnectedEvent(SessionRole.receiver));
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const TransferScreen(role: SessionRole.receiver)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Receive'),
        centerTitle: true,
        actions: [_buildBadge()],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _buildBody(theme),
      ),
    );
  }

  Widget _buildBadge() {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        const Text('No Internet Needed', style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _buildBody(ThemeData theme) {
    switch (_step) {
      case _Step.scan:       return _buildScanStep(theme);
      case _Step.generating: return _buildGenerating(theme);
      case _Step.showAnswer: return _buildShowAnswer(theme);
      case _Step.connecting: return _buildConnecting(theme);
    }
  }

  Widget _buildScanStep(ThemeData theme) {
    return SingleChildScrollView(
      key: const ValueKey('scan'),
      padding: EdgeInsets.all(AppSizes.p24),
      child: Column(children: [
        Icon(Icons.wifi_off_rounded, size: 64, color: theme.colorScheme.primary),
        AppSpacing.gapH16,
        Text('Receive Offline', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        AppSpacing.gapH8,
        Text(
          'Scan or paste the sender\'s QR code / offer code',
          textAlign: TextAlign.center,
          style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
        ),
        AppSpacing.gapH32,
        if (!kIsWeb) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _openQrScanner(context),
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Scan Sender\'s QR Code'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ),
          AppSpacing.gapH16,
        ],
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: _showManualInput
              ? Column(children: [
                  TextField(
                    controller: _offerController,
                    decoration: const InputDecoration(
                      labelText: 'Paste offer code here',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.paste_rounded),
                    ),
                    maxLines: 4,
                  ),
                  AppSpacing.gapH12,
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => _processOffer(_offerController.text),
                      child: const Text('Generate Answer'),
                    ),
                  ),
                ])
              : OutlinedButton.icon(
                  onPressed: () => setState(() => _showManualInput = true),
                  icon: const Icon(Icons.keyboard_rounded, size: 16),
                  label: Text(kIsWeb ? 'Paste offer code' : 'Enter code manually instead'),
                ),
        ),
        if (_errorMsg.isNotEmpty) ...[
          AppSpacing.gapH16,
          Text(_errorMsg, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
        ],
      ]),
    );
  }

  Widget _buildGenerating(ThemeData theme) {
    return Center(
      key: const ValueKey('generating'),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const CircularProgressIndicator(),
        AppSpacing.gapH24,
        Text('Generating answer...', style: theme.textTheme.titleMedium),
        AppSpacing.gapH8,
        Text(
          'Processing offer and preparing local candidates',
          style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
          textAlign: TextAlign.center,
        ),
      ]),
    );
  }

  Widget _buildShowAnswer(ThemeData theme) {
    return SingleChildScrollView(
      key: const ValueKey('answer'),
      padding: EdgeInsets.all(AppSizes.p24),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.qr_code_rounded, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Show this to the sender to complete connection',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.primary),
              ),
            ),
          ]),
        ),
        AppSpacing.gapH16,
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, 4))],
          ),
          child: QrImageView(
            data: _answerCode,
            version: QrVersions.auto,
            size: 220,
            backgroundColor: Colors.white,
            errorCorrectionLevel: QrErrorCorrectLevel.L,
          ),
        ),
        AppSpacing.gapH12,
        OutlinedButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: _answerCode));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Answer code copied!')));
          },
          icon: const Icon(Icons.copy_rounded, size: 16),
          label: const Text('Copy Answer Code'),
        ),
        AppSpacing.gapH16,
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
          ),
          child: Row(children: [
            const Icon(Icons.info_outline_rounded, color: Colors.blue, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Waiting for sender to scan or paste this code. Connection will happen automatically.',
                style: TextStyle(fontSize: 13, color: Colors.blue.shade700),
              ),
            ),
          ]),
        ),
        if (_errorMsg.isNotEmpty) ...[
          AppSpacing.gapH16,
          Text(_errorMsg, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
        ],
      ]),
    );
  }

  Widget _buildConnecting(ThemeData theme) {
    return Center(
      key: const ValueKey('conn'),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const CircularProgressIndicator(),
        AppSpacing.gapH24,
        Text('Connecting...', style: theme.textTheme.titleMedium),
      ]),
    );
  }

  void _openQrScanner(BuildContext context) {
    bool scanned = false;
    Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
      appBar: AppBar(title: const Text('Scan Sender\'s QR'), centerTitle: true),
      body: MobileScanner(
        onDetect: (capture) {
          if (scanned) return;
          final code = capture.barcodes.firstOrNull?.rawValue;
          if (code != null) {
            scanned = true;
            Navigator.pop(context);
            _processOffer(code);
          }
        },
      ),
    )));
  }
}
