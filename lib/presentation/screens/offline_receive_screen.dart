import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/di/injection_container.dart';
import '../../core/services/offline_signaling_service.dart';
import '../../core/services/sdp_relay_service.dart';
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
  final _sessionCodeController = TextEditingController();
  bool _useSessionCode = true;   // default: session code tab

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
    _sessionCodeController.dispose();
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

  Future<void> _processSessionCode(String code) async {
    if (code.trim().isEmpty) return;
    setState(() { _step = _Step.generating; _errorMsg = ''; });
    try {
      final offerCode = await SdpRelayService.download(code.trim());
      await _processOfferSdp(offerCode);
    } catch (e) {
      if (!mounted) return;
      setState(() { _errorMsg = e.toString().replaceFirst('Exception: ', ''); _step = _Step.scan; });
    }
  }

  Future<void> _processOfferSdp(String offerCode) async {
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
    return Center(
      key: const ValueKey('scan'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Icon header
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.download_rounded, size: 34, color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 16),
              Text('Receive Files', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('No internet needed', style: TextStyle(fontSize: 13, color: theme.colorScheme.primary.withValues(alpha: 0.8), fontWeight: FontWeight.w500)),
              const SizedBox(height: 28),
              // How it works card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.15)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('How it works', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface.withValues(alpha: 0.6), letterSpacing: 0.5)),
                    const SizedBox(height: 14),
                    _buildStep(theme, '1', "Scan the QR code on the sender's screen", Icons.qr_code_scanner_rounded),
                    _buildStep(theme, '2', 'Show your QR code back to the sender', Icons.qr_code_rounded),
                    _buildStep(theme, '3', 'Files arrive automatically!', Icons.download_done_rounded, isLast: true),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // WiFi note
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.18)),
                ),
                child: Row(children: [
                  Icon(Icons.wifi_rounded, color: Colors.blue.shade400, size: 16),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Both devices must be on the same Wi-Fi or hotspot', style: TextStyle(fontSize: 12))),
                ]),
              ),
              const SizedBox(height: 28),
              // ── Input: Session code OR paste full code ────────────────────
              // Tab switcher
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _useSessionCode = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _useSessionCode ? theme.colorScheme.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('Session Code', textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                            color: _useSessionCode ? Colors.white : theme.colorScheme.onSurface.withValues(alpha: 0.6))),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _useSessionCode = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: !_useSessionCode ? theme.colorScheme.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('Paste Full Code', textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                            color: !_useSessionCode ? Colors.white : theme.colorScheme.onSurface.withValues(alpha: 0.6))),
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              // Input fields
              if (_useSessionCode) ...[                
                TextField(
                  controller: _sessionCodeController,
                  autofocus: kIsWeb,
                  textCapitalization: TextCapitalization.characters,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 6, color: theme.colorScheme.primary),
                  maxLength: 10,
                  decoration: InputDecoration(
                    labelText: 'Session Code',
                    hintText: 'e.g. A7K9X2',
                    border: const OutlineInputBorder(),
                    counterText: '',
                    helperText: 'Enter the code shown on the sender\'s screen',
                  ),
                  onSubmitted: (v) => _processSessionCode(v),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _processSessionCode(_sessionCodeController.text),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('Connect'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 32),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ] else ...[                
                TextField(
                  controller: _offerController,
                  autofocus: false,
                  decoration: InputDecoration(
                    labelText: "Paste the sender's code",
                    hintText: 'Paste the full code here',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.paste_rounded),
                    helperText: 'Copy the full code from the sender and paste it here',
                  ),
                  maxLines: 4,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _processOffer(_offerController.text),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('Continue'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 32),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
              if (_errorMsg.isNotEmpty) ...[
                const SizedBox(height: 14),
                _buildError(_errorMsg),
              ],
            ],
          ),
        ),
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

}
