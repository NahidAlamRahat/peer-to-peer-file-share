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
import '../../core/theme/app_sizes.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/platform_file_picker.dart';
import '../../data/datasources/webrtc_client.dart';
import '../../domain/entities/peer_session.dart';
import '../../domain/entities/share_file.dart';
import '../blocs/connection/connection_bloc.dart';
import '../blocs/connection/connection_event.dart';
import '../blocs/transfer/transfer_bloc.dart';
import '../blocs/transfer/transfer_event.dart';
import 'transfer_screen.dart';

/// Offline sender screen — no internet required.
/// Step 1: Pick files → generate offer QR / code.
/// Step 2: Receiver scans offer → shows answer QR / code.
/// Step 3: Sender scans / pastes answer → connected → transfer starts.
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
  String _errorMsg = '';
  bool _isLoading = false;

  final _answerController = TextEditingController();
  bool _showManualInput = false;
  StreamSubscription<void>? _ignore; // keeps dart:async import used

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
    _ignore?.cancel();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final picked = await pickFilesLocally();
    if (picked == null || picked.isEmpty) return;
    setState(() => _files = picked);
    await _generateOffer();
  }

  Future<void> _generateOffer() async {
    setState(() { _isLoading = true; _errorMsg = ''; });
    try {
      final code = await _offlineSvc.createOfferCode();
      if (!mounted) return;
      setState(() {
        _offerCode = code;
        _step = _Step.showOffer;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _errorMsg = 'Failed to create offer: $e'; _isLoading = false; });
    }
  }

  Future<void> _applyAnswer(String code) async {
    if (code.isEmpty) return;
    setState(() { _step = _Step.connecting; _errorMsg = ''; _isLoading = true; });
    try {
      await _offlineSvc.processAnswerCode(code.trim());
      // onConnectionState callback handles navigation on success
    } catch (e) {
      if (!mounted) return;
      setState(() { _errorMsg = 'Invalid answer code: $e'; _step = _Step.showOffer; _isLoading = false; });
    }
  }

  void _onConnected() {
    if (!mounted) return;
    context.read<ConnectionBloc>().add(OfflineConnectedEvent(SessionRole.sender));
    context.read<TransferBloc>().add(SendFilesEvent(_files));
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const TransferScreen(role: SessionRole.sender)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Send'),
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
      case _Step.pickFiles:   return _buildPickFiles(theme);
      case _Step.showOffer:   return _buildOfferAndScanAnswer(theme);
      case _Step.connecting:  return _buildConnecting(theme);
    }
  }

  Widget _buildPickFiles(ThemeData theme) {
    return Center(
      key: const ValueKey('pick'),
      child: Padding(
        padding: EdgeInsets.all(AppSizes.p24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.wifi_off_rounded, size: 72, color: theme.colorScheme.primary),
          AppSpacing.gapH24,
          Text('Offline Transfer', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          AppSpacing.gapH8,
          Text(
            'Transfer files directly over Wi-Fi or hotspot.\nNo internet connection required.',
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          ),
          AppSpacing.gapH32,
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isLoading ? null : _pickFiles,
              icon: _isLoading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.attach_file_rounded),
              label: Text(_isLoading ? 'Generating offer...' : 'Pick Files & Continue'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
          ),
          if (_errorMsg.isNotEmpty) ...[
            AppSpacing.gapH16,
            Text(_errorMsg, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
          ],
        ]),
      ),
    );
  }

  Widget _buildOfferAndScanAnswer(ThemeData theme) {
    return SingleChildScrollView(
      key: const ValueKey('offer'),
      padding: EdgeInsets.all(AppSizes.p24),
      child: Column(children: [
        _buildStepBadge('Step 1 of 2 — Show this to the receiver', Icons.qr_code_rounded, theme),
        AppSpacing.gapH16,
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Icon(Icons.folder_zip_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(child: Text('${_files.length} file(s) selected', style: const TextStyle(fontWeight: FontWeight.w600))),
            TextButton(onPressed: _pickFiles, child: const Text('Change')),
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
            data: _offerCode,
            version: QrVersions.auto,
            size: 220,
            backgroundColor: Colors.white,
            errorCorrectionLevel: QrErrorCorrectLevel.L,
          ),
        ),
        AppSpacing.gapH12,
        OutlinedButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: _offerCode));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offer code copied!')));
          },
          icon: const Icon(Icons.copy_rounded, size: 16),
          label: const Text('Copy Offer Code'),
        ),
        AppSpacing.gapH24,
        Row(children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('Step 2 of 2 — Enter receiver\'s answer', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
          ),
          const Expanded(child: Divider()),
        ]),
        AppSpacing.gapH16,
        if (!kIsWeb) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _openQrScanner(context),
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Scan Receiver\'s QR Code'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ),
          AppSpacing.gapH12,
        ],
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: _showManualInput
              ? Column(children: [
                  TextField(
                    controller: _answerController,
                    decoration: const InputDecoration(
                      labelText: 'Paste answer code here',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.paste_rounded),
                    ),
                    maxLines: 3,
                  ),
                  AppSpacing.gapH12,
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => _applyAnswer(_answerController.text),
                      child: const Text('Connect'),
                    ),
                  ),
                ])
              : TextButton.icon(
                  onPressed: () => setState(() => _showManualInput = true),
                  icon: const Icon(Icons.keyboard_rounded, size: 16),
                  label: const Text('Enter code manually instead'),
                ),
        ),
        if (_errorMsg.isNotEmpty) ...[
          AppSpacing.gapH12,
          Text(_errorMsg, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
        ],
      ]),
    );
  }

  Widget _buildConnecting(ThemeData theme) {
    return Center(
      key: const ValueKey('connecting'),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const CircularProgressIndicator(),
        AppSpacing.gapH24,
        Text('Connecting to receiver...', style: theme.textTheme.titleMedium),
        AppSpacing.gapH8,
        Text('Establishing local P2P connection', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
        if (_errorMsg.isNotEmpty) ...[
          AppSpacing.gapH16,
          Text(_errorMsg, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
        ],
      ]),
    );
  }

  Widget _buildStepBadge(String text, IconData icon, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Flexible(child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.primary))),
      ]),
    );
  }

  void _openQrScanner(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => _QrScanPage(
      onScanned: (code) {
        Navigator.pop(context);
        _applyAnswer(code);
      },
    )));
  }
}

// ── Minimal QR scanner page ──────────────────────────────────────────────────
class _QrScanPage extends StatefulWidget {
  final void Function(String code) onScanned;
  const _QrScanPage({required this.onScanned});

  @override
  State<_QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<_QrScanPage> {
  bool _scanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Receiver\'s QR'), centerTitle: true),
      body: MobileScanner(
        onDetect: (capture) {
          if (_scanned) return;
          final barcode = capture.barcodes.firstOrNull;
          if (barcode?.rawValue != null) {
            _scanned = true;
            widget.onScanned(barcode!.rawValue!);
          }
        },
      ),
    );
  }
}
