import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/di/injection_container.dart';
import '../../core/services/offline_signaling_service.dart';
import '../../core/services/sdp_relay_service.dart';
import '../../core/utils/platform_file_picker.dart';
import '../../data/datasources/webrtc_client.dart';
import '../../domain/entities/peer_session.dart';
import '../../domain/entities/share_file.dart';
import '../blocs/connection/connection_bloc.dart';
import '../blocs/connection/connection_event.dart';
import '../blocs/transfer/transfer_bloc.dart';
import '../blocs/transfer/transfer_event.dart';
import 'transfer_screen.dart';

class OfflineSendScreen extends StatefulWidget {
  const OfflineSendScreen({super.key});

  @override
  State<OfflineSendScreen> createState() => _OfflineSendScreenState();
}

enum _Step { pickFiles, showOffer, connecting }

class _OfflineSendScreenState extends State<OfflineSendScreen> {
  late final OfflineSignalingService _offlineSvc;
  late final WebRTCClient _webrtcClient;

  _Step _step = _Step.pickFiles;
  List<ShareFile> _files = [];
  String _offerCode = '';
  String _sessionCode = '';   // short relay code shown below QR
  String _errorMsg = '';
  bool _isLoading = false;

  final _answerController = TextEditingController();
  bool _showManualInput = false;
  Timer? _pollTimer;            // polls relay for answer automatically

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
          _errorMsg = 'Connection failed. Please try again.';
          _step = _Step.showOffer;
        });
      }
    };
  }

  @override
  void dispose() {
    _offlineSvc.dispose();
    _answerController.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final picked = await pickFilesLocally();
    if (picked == null || picked.isEmpty) return;
    setState(() => _files = picked);
    await _generateOffer();
  }

  Future<void> _generateOffer() async {
    setState(() { _isLoading = true; _errorMsg = ''; _sessionCode = ''; });
    try {
      final code = await _offlineSvc.createOfferCode();
      if (!mounted) return;
      setState(() { _offerCode = code; _step = _Step.showOffer; _isLoading = false; });
      // Upload to relay in background to get session code
      _uploadToRelay(code);
    } catch (e) {
      if (!mounted) return;
      setState(() { _errorMsg = 'Something went wrong. Please try again.'; _isLoading = false; });
    }
  }

  Future<void> _uploadToRelay(String offerCode) async {
    try {
      final code = await SdpRelayService.uploadOffer(offerCode);
      if (!mounted) return;
      setState(() => _sessionCode = code);
      // Start auto-polling for the receiver's answer
      _startPollingForAnswer(code);
    } catch (_) {
      // Relay unavailable — QR only mode, no session code shown
    }
  }

  void _startPollingForAnswer(String sessionCode) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_step != _Step.showOffer) { _pollTimer?.cancel(); return; }
      try {
        final answer = await SdpRelayService.pollAnswer(sessionCode);
        if (answer != null && mounted) {
          _pollTimer?.cancel();
          await _applyAnswer(answer);
        }
      } catch (_) { /* ignore poll errors */ }
    });
  }

  Future<void> _applyAnswer(String code) async {
    if (code.isEmpty) return;
    setState(() { _step = _Step.connecting; _errorMsg = ''; _isLoading = true; });
    try {
      await _offlineSvc.processAnswerCode(code.trim());
    } catch (e) {
      if (!mounted) return;
      setState(() { _errorMsg = 'Invalid code. Please ask the receiver to try again.'; _step = _Step.showOffer; _isLoading = false; });
    }
  }

  void _onConnected() {
    if (!mounted) return;
    context.read<ConnectionBloc>().add(OfflineConnectedEvent(SessionRole.sender));
    context.read<TransferBloc>().add(SendFilesEvent(_files));
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TransferScreen(role: SessionRole.sender)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send Files'),
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
      ),
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
      case _Step.pickFiles:   return _buildPickFiles(theme);
      case _Step.showOffer:   return _buildShowOffer(theme);
      case _Step.connecting:  return _buildConnecting(theme);
    }
  }

  // ── Step 1: Pick files ──────────────────────────────────────────────────────
  Widget _buildPickFiles(ThemeData theme) {
    return Center(
      key: const ValueKey('pick'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Icon
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.send_rounded, size: 34, color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 16),
              Text('Send Files', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
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
                    _buildStep(theme, '1', 'Select the files you want to send', Icons.folder_open_rounded),
                    _buildStep(theme, '2', 'Show the QR code to the other device', Icons.qr_code_rounded),
                    _buildStep(theme, '3', 'Scan the code they show back', Icons.qr_code_scanner_rounded),
                    _buildStep(theme, '4', 'Files transfer instantly!', Icons.check_circle_rounded, isLast: true),
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
              // Button — not full width
              FilledButton.icon(
                onPressed: _isLoading ? null : _pickFiles,
                icon: _isLoading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.folder_open_rounded, size: 18),
                label: Text(_isLoading ? 'Preparing...' : 'Select Files'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 32),
                  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
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

  // ── Step 2: Show QR + scan answer ──────────────────────────────────────────
  Widget _buildShowOffer(ThemeData theme) {
    return SingleChildScrollView(
      key: const ValueKey('offer'),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Step 2 header
          _buildStepHeader('Step 1 of 2', 'Show this QR to the other device', Icons.qr_code_rounded, theme),
          const SizedBox(height: 20),
          // Files info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              Icon(Icons.attach_file_rounded, color: theme.colorScheme.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text('${_files.length} file${_files.length > 1 ? "s" : ""} ready to send', style: const TextStyle(fontWeight: FontWeight.w500))),
              TextButton(onPressed: _pickFiles, child: const Text('Change')),
            ]),
          ),
          const SizedBox(height: 16),
          // QR Code
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 24, offset: const Offset(0, 6))],
            ),
            child: QrImageView(data: _offerCode, version: QrVersions.auto, size: 200, backgroundColor: Colors.white, errorCorrectionLevel: QrErrorCorrectLevel.L),
          ),
          const SizedBox(height: 16),
          // Session code below QR
          if (_sessionCode.isNotEmpty) ...[           
            Text('or share this session code', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3), width: 1.5),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  _sessionCode,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 6,
                    color: theme.colorScheme.primary,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _sessionCode));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session code copied!')));
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  tooltip: 'Copy session code',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ]),
            ),
            const SizedBox(height: 4),
            Text('Receiver types this code — no QR scan needed', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.4))),
          ] else ...[          
            SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary.withValues(alpha: 0.4)),
            ),
            const SizedBox(height: 4),
            Text('Generating session code...', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.4))),
          ],
          const SizedBox(height: 28),
          Divider(color: theme.dividerColor.withValues(alpha: 0.4)),
          const SizedBox(height: 20),
          // Step 2 header
          _buildStepHeader('Step 2 of 2', 'Now scan the code from their screen', Icons.qr_code_scanner_rounded, theme),
          const SizedBox(height: 16),
          if (!kIsWeb) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _openQrScanner(context),
                icon: const Icon(Icons.camera_alt_rounded),
                label: const Text('Scan Their QR Code'),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
            const SizedBox(height: 12),
          ],
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: _showManualInput
                ? Column(children: [
                    TextField(
                      controller: _answerController,
                      decoration: const InputDecoration(
                        labelText: 'Paste their code here',
                        hintText: 'Code from the other device',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.paste_rounded),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 10),
                    SizedBox(width: double.infinity, child: FilledButton(onPressed: () => _applyAnswer(_answerController.text), child: const Text('Connect & Start Transfer'))),
                  ])
                : TextButton.icon(
                    onPressed: () => setState(() => _showManualInput = true),
                    icon: const Icon(Icons.keyboard_rounded, size: 16),
                    label: Text(kIsWeb ? 'Paste their code instead' : 'Enter code manually'),
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

  // ── Connecting ──────────────────────────────────────────────────────────────
  Widget _buildConnecting(ThemeData theme) {
    return Center(
      key: const ValueKey('conn'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(width: 56, height: 56, child: CircularProgressIndicator(strokeWidth: 3, color: theme.colorScheme.primary)),
          const SizedBox(height: 24),
          Text('Connecting...', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Establishing connection with the other device', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5)), textAlign: TextAlign.center),
          if (_errorMsg.isNotEmpty) ...[const SizedBox(height: 16), _buildError(_errorMsg)],
        ]),
      ),
    );
  }

  Widget _buildStep(ThemeData theme, String number, String text, IconData icon, {bool isLast = false}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
        ],
      ),
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
    Navigator.push(context, MaterialPageRoute(builder: (_) => _QrScanPage(onScanned: (code) { Navigator.pop(context); _applyAnswer(code); })));
  }
}

class _QrScanPage extends StatefulWidget {
  final void Function(String code) onScanned;
  const _QrScanPage({required this.onScanned});
  @override State<_QrScanPage> createState() => _QrScanPageState();
}
class _QrScanPageState extends State<_QrScanPage> {
  bool _scanned = false;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Scan the other device's screen"), centerTitle: true),
      body: MobileScanner(onDetect: (capture) {
        if (_scanned) return;
        final barcode = capture.barcodes.firstOrNull;
        if (barcode?.rawValue != null) { _scanned = true; widget.onScanned(barcode!.rawValue!); }
      }),
    );
  }
}
