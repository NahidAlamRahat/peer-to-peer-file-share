import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/di/injection_container.dart';
import '../../core/services/offline_signaling_service.dart';
import '../../data/datasources/webrtc_client.dart';
import '../../domain/entities/peer_session.dart';
import '../blocs/connection/connection_bloc.dart';
import '../blocs/connection/connection_event.dart';
import 'transfer_screen.dart';

class OfflineReceiveScreen extends StatefulWidget {
  const OfflineReceiveScreen({super.key});

  @override
  State<OfflineReceiveScreen> createState() => _OfflineReceiveScreenState();
}

enum _Step { scan, generating, showAnswer }

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
        setState(() { _errorMsg = 'Connection failed. Ask the sender to try again.'; });
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
      setState(() { _errorMsg = 'Invalid code. Ask the sender to show their QR again.'; _step = _Step.scan; });
    }
  }

  void _onConnected() {
    if (!mounted) return;
    context.read<ConnectionBloc>().add(OfflineConnectedEvent(SessionRole.receiver));
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TransferScreen(role: SessionRole.receiver)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Receive Files'), centerTitle: true, surfaceTintColor: Colors.transparent),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: _buildBody(theme),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    switch (_step) {
      case _Step.scan:       return _buildScanStep(theme);
      case _Step.generating: return _buildGenerating(theme);
      case _Step.showAnswer: return _buildShowAnswer(theme);
    }
  }

  // ── Step 1: Scan sender's QR ────────────────────────────────────────────────
  Widget _buildScanStep(ThemeData theme) {
    return SingleChildScrollView(
      key: const ValueKey('scan'),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How it works', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _buildStep(theme, '1', 'Scan the QR code shown on the sender\'s device', Icons.qr_code_scanner_rounded),
          _buildStep(theme, '2', 'Show the QR code on your screen to the sender', Icons.qr_code_rounded),
          _buildStep(theme, '3', 'Files arrive automatically!', Icons.download_done_rounded, isLast: true),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              Icon(Icons.wifi_rounded, color: Colors.blue.shade400, size: 18),
              const SizedBox(width: 10),
              const Expanded(child: Text('Both devices must be on the same Wi-Fi or hotspot', style: TextStyle(fontSize: 13))),
            ]),
          ),
          const SizedBox(height: 28),
          if (!kIsWeb) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _openQrScanner(context),
                icon: const Icon(Icons.camera_alt_rounded),
                label: const Text("Scan Sender's QR Code"),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),
            const SizedBox(height: 14),
          ],
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: _showManualInput
                ? Column(children: [
                    TextField(
                      controller: _offerController,
                      decoration: const InputDecoration(
                        labelText: "Paste the sender's code",
                        hintText: 'Code from the sender',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.paste_rounded),
                      ),
                      maxLines: 4,
                    ),
                    const SizedBox(height: 10),
                    SizedBox(width: double.infinity, child: FilledButton(onPressed: () => _processOffer(_offerController.text), child: const Text('Continue'))),
                  ])
                : OutlinedButton.icon(
                    onPressed: () => setState(() => _showManualInput = true),
                    icon: const Icon(Icons.keyboard_rounded, size: 16),
                    label: Text(kIsWeb ? "Paste sender's code" : "Can't scan? Enter code manually"),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
          ),
          if (_errorMsg.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildError(_errorMsg),
          ],
        ],
      ),
    );
  }

  // ── Generating ──────────────────────────────────────────────────────────────
  Widget _buildGenerating(ThemeData theme) {
    return Center(
      key: const ValueKey('gen'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(width: 56, height: 56, child: CircularProgressIndicator(strokeWidth: 3, color: theme.colorScheme.primary)),
          const SizedBox(height: 24),
          Text('Almost there...', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Preparing your response code', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
        ]),
      ),
    );
  }

  // ── Step 2: Show answer QR ──────────────────────────────────────────────────
  Widget _buildShowAnswer(ThemeData theme) {
    return SingleChildScrollView(
      key: const ValueKey('answer'),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _buildStepHeader('Step 2 of 2', 'Now show this to the sender', Icons.qr_code_rounded, theme),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 24, offset: const Offset(0, 6))],
            ),
            child: QrImageView(data: _answerCode, version: QrVersions.auto, size: 200, backgroundColor: Colors.white, errorCorrectionLevel: QrErrorCorrectLevel.L),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _answerCode));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copied to clipboard')));
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text("Can't scan? Copy code instead"),
          ),
          const SizedBox(height: 20),
          // Waiting indicator
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Waiting for sender to scan', style: TextStyle(fontWeight: FontWeight.w600, color: theme.colorScheme.primary)),
                const SizedBox(height: 2),
                Text('Transfer will start automatically once connected', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
              ])),
            ]),
          ),
          if (_errorMsg.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildError(_errorMsg),
          ],
        ],
      ),
    );
  }

  Widget _buildStep(ThemeData theme, String number, String text, IconData icon, {bool isLast = false}) {
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle),
            child: Center(child: Text(number, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
          ),
          if (!isLast) Expanded(child: Container(width: 2, color: theme.colorScheme.primary.withValues(alpha: 0.2))),
        ]),
        const SizedBox(width: 14),
        Expanded(child: Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : 20, top: 4),
          child: Row(children: [
            Icon(icon, size: 18, color: theme.colorScheme.primary.withValues(alpha: 0.7)),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
          ]),
        )),
      ]),
    );
  }

  Widget _buildStepHeader(String step, String title, IconData icon, ThemeData theme) {
    return Row(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(20)),
        child: Text(step, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
      ),
      const SizedBox(width: 10),
      Icon(icon, size: 18, color: theme.colorScheme.primary),
      const SizedBox(width: 6),
      Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
    ]);
  }

  Widget _buildError(String msg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.withValues(alpha: 0.3))),
      child: Row(children: [const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18), const SizedBox(width: 8), Expanded(child: Text(msg, style: const TextStyle(color: Colors.red, fontSize: 13)))]),
    );
  }

  void _openQrScanner(BuildContext context) {
    bool scanned = false;
    Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
      appBar: AppBar(title: const Text("Scan Sender's QR Code"), centerTitle: true),
      body: MobileScanner(onDetect: (capture) {
        if (scanned) return;
        final code = capture.barcodes.firstOrNull?.rawValue;
        if (code != null) { scanned = true; Navigator.pop(context); _processOffer(code); }
      }),
    )));
  }
}
