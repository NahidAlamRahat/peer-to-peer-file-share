import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/di/injection_container.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/spacing.dart';
import '../../domain/entities/peer_session.dart';
import '../blocs/connection/connection_bloc.dart';
import '../blocs/connection/connection_event.dart';
import '../blocs/connection/connection_state.dart';
import '../blocs/transfer/transfer_bloc.dart';
import '../blocs/transfer/transfer_state.dart';
import '../widgets/custom_buttons.dart';
import '../widgets/responsive_layout.dart';
import 'transfer_screen.dart';

class ReceiveScreen extends StatefulWidget {
  /// Session ID from share link (may be null if opened manually).
  final String? autoJoinSessionId;

  /// File info pre-loaded from URL params — shown before connecting.
  final String? preloadedFileName;
  final int?    preloadedFileSize;
  final int?    preloadedFileCount;

  const ReceiveScreen({
    super.key,
    this.autoJoinSessionId,
    this.preloadedFileName,
    this.preloadedFileSize,
    this.preloadedFileCount,
  });

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  final TextEditingController _codeController = TextEditingController();

  bool _waitingForFile = false;
  Map<String, dynamic>? _fileMetadata;
  bool _isSenderOffline = false;
  bool _autoAcceptDownload = false; // true when opened via link — skip confirmation
  bool _sessionExpired = false;


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final transferBloc = sl<TransferBloc>();
      if (transferBloc.state is TransferInProgress) {
        final connectionBloc = context.read<ConnectionBloc>();
        SessionRole role = SessionRole.receiver;
        if (connectionBloc.state is ConnectionConnected) {
          role = (connectionBloc.state as ConnectionConnected).role;
        }
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => TransferScreen(role: role)),
        );
        return;
      }

      if (widget.autoJoinSessionId != null && widget.autoJoinSessionId!.isNotEmpty) {
        _codeController.text = widget.autoJoinSessionId!;
        // If file info is preloaded from URL — DON'T auto-join.
        // Show file preview and wait for user to tap Download.
        if (widget.preloadedFileName == null) {
          // Old-style link (no file info) — auto-join immediately
          _joinSession();
        }
      }
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  /// Called when user manually enters a code and taps Join.
  void _joinSession() {
    final code = _codeController.text.trim();
    if (code.isNotEmpty) {
      setState(() {
        _waitingForFile = true;
        _isSenderOffline = false;
        _fileMetadata = null;
      });
      debugPrint('🔗 [UI] Joining session with code: $code');
      context.read<ConnectionBloc>().add(JoinSessionEvent(code));
    }
  }

  /// Called when receiver taps Download on the link-preview screen.
  /// Connects to sender and auto-accepts the download without extra confirmation.
  void _joinSessionFromLink() {
    setState(() {
      _autoAcceptDownload = true;
      _waitingForFile = true;
      _isSenderOffline = false;
      _fileMetadata = null;
    });
    debugPrint('🔗 [UI] Joining session from link (auto-accept): ${_codeController.text}');
    context.read<ConnectionBloc>().add(JoinSessionEvent(_codeController.text.trim()));
  }

  void _startDownload() {
    if (_fileMetadata != null) {
      // 1. Tell sender we accepted the download
      context.read<ConnectionBloc>().add(
        SendMessageEvent({'action': 'accept_download'}),
      );

      // 2. Head to TransferScreen to begin receiving the chunks
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => TransferScreen(
            role: SessionRole.receiver,
            preflightMetadata: _fileMetadata,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Receive File'), elevation: 0),
      body: BlocConsumer<ConnectionBloc, ConnectionStateBloc>(
        listener: (context, state) {
          if (state is ConnectionMessageReceived) {
            if (state.payload['action'] == 'files_metadata') {
              final count = state.payload['filesCount'];
              final size = state.payload['totalSize'];
              final sizeMB = (size / (1024 * 1024)).toStringAsFixed(2);
              debugPrint('📥 [UI] Received file metadata: $count files ($sizeMB MB)');
              setState(() { _fileMetadata = state.payload; });

              // Auto-accept: if opened via link, skip confirmation and start download
              if (_autoAcceptDownload) {
                debugPrint('⚡ [UI] Auto-accepting download (opened via link)');
                Future.microtask(() => _startDownload());
              }
            }
          } else if (state is ConnectionConnected) {
            debugPrint('🔗 [UI] WebRTC connected. Waiting for file metadata.');
          } else if (state is ConnectionOffline) {
            setState(() { _isSenderOffline = true; });
          } else if (state is ConnectionFailed) {
            final msg = state.message.toLowerCase();
            final isSessionError = msg.contains('session') || msg.contains('not found') || msg.contains('timed out') || msg.contains('timeout');
            setState(() {
               _waitingForFile = false;
               _isSenderOffline = false;
               _autoAcceptDownload = false;
               if (isSessionError) _sessionExpired = true;
            });
            if (!isSessionError) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Connection failed. Please try again.', style: TextStyle(color: Colors.white)),
                  backgroundColor: Colors.red,
                ),
              );
            }
          } else if (state is ConnectionServerError) {
            final msg = state.message.toLowerCase();
            final isSessionError = msg.contains('session') || msg.contains('not found') || msg.contains('timed out') || msg.contains('timeout');
            setState(() { 
              _waitingForFile = false; 
              _autoAcceptDownload = false; 
              if (isSessionError) _sessionExpired = true;
            });
            if (!isSessionError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message, style: const TextStyle(color: Colors.white)),
                  backgroundColor: Colors.red.shade700,
                ),
              );
            }
          }
        },
        builder: (context, state) {
          Widget content;

          if (_sessionExpired) {
            content = _buildSenderOfflineState(customMessage: 'Session expired or not found. Please ask the sender for a new link.');
          } else if (widget.preloadedFileName != null && !_waitingForFile) {
            content = _buildLinkPreviewState();

          } else if (state is ConnectionLoading || (_waitingForFile && _autoAcceptDownload && _fileMetadata == null)) {
            // Connecting spinner (auto-accept mode: skip file-ready screen)
            content = _buildConnectionProgressState(
              state,
              customMessage: 'Connecting to sender...',
            );
          } else if (_waitingForFile) {
            if (_isSenderOffline) {
              content = _buildSenderOfflineState();
            } else if (_fileMetadata != null) {
              content = _buildFileReadyState();
            } else {
              content = _buildConnectionProgressState(state);
            }
          } else {
            content = _buildEnterCodeState();
          }

          return ResponsiveLayout(
            mobileBody: _buildMobileLayout(content),
            desktopBody: _buildDesktopLayout(content),
          );
        },
      ),
    );
  }

  Widget _buildEnterCodeState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.qr_code_scanner_rounded,
          size: AppSizes.iconHuge,
          color: Colors.grey,
        ),
        AppSpacing.gapH24,
        Text(
          'Enter the 6-digit code or complete ID from the sender:',
          style: TextStyle(fontSize: AppSizes.textSubtitle),
          textAlign: TextAlign.center,
        ),
        AppSpacing.gapH32,
        TextField(
          controller: _codeController,
          decoration: InputDecoration(
            labelText: 'Enter Code',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: AppSizes.textHeadline,
            letterSpacing: 2,
            fontWeight: FontWeight.bold,
          ),
        ),
        AppSpacing.gapH32,
        CustomButton(text: 'Connect', onPressed: _joinSession),
      ],
    );
  }

  Widget _buildSenderOfflineState({String? customMessage}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.cloud_off, size: AppSizes.iconHuge, color: Colors.redAccent),
        AppSpacing.gapH16,
        Text(
          customMessage ?? 'Sender is offline',
          style: TextStyle(
            fontSize: AppSizes.textHeadline,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        if (customMessage == null) ...[
          AppSpacing.gapH16,
          const Text(
            'Please ask them to open the app\nand turn on internet.',
            textAlign: TextAlign.center,
          ),
        ],
        AppSpacing.gapH32,
        CustomButton(
          text: 'Go Back',
          onPressed: () {
            setState(() {
              _waitingForFile = false;
              _isSenderOffline = false;
            });
            context.read<ConnectionBloc>().add(ResetConnectionEvent());
          },
        ),
      ],
    );
  }

  Widget _buildFileReadyState() {
    final sizeMB = (_fileMetadata!['totalSize'] / (1024 * 1024))
        .toStringAsFixed(2);
    final count = _fileMetadata!['filesCount'];
    final firstName = _fileMetadata!['firstFileName'];

    String titleText = count > 1 ? '$count files' : firstName;
    String subtitleText = count > 1
        ? 'Including: $firstName\nTotal Size: $sizeMB MB'
        : '$sizeMB MB';

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.insert_drive_file,
          size: AppSizes.iconHuge,
          color: Colors.blueAccent,
        ),
        AppSpacing.gapH24,
        Text(
          titleText,
          style: TextStyle(
            fontSize: AppSizes.textTitle,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        AppSpacing.gapH8,
        Text(
          subtitleText,
          style: TextStyle(fontSize: AppSizes.textBody, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
        AppSpacing.gapH48,
        CustomButton(
          text: 'Download',
          icon: Icons.download,
          onPressed: _startDownload,
        ),
      ],
    );
  }

  Widget _buildConnectionProgressState(ConnectionStateBloc state, {String? customMessage}) {
    String statusText = customMessage ?? 'Waiting for file details from sender...';
    double? progressValue;

    if (state is ConnectionProgress) {
      statusText = state.message;
      progressValue = state.progress;
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(AppSizes.p24),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            children: [
              if (progressValue != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppSizes.radiusCircular),
                  child: LinearProgressIndicator(
                    value: progressValue,
                    minHeight: 8,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                  ),
                ),
              ] else ...[
                const CircularProgressIndicator(),
              ],
              AppSpacing.gapH24,
              Text(
                statusText,
                style: TextStyle(
                  fontSize: AppSizes.textBody,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              if (progressValue != null) ...[
                AppSpacing.gapH8,
                Text(
                  '${(progressValue * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: AppSizes.textSmall,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLinkPreviewState() {
    final sizeMB = widget.preloadedFileSize != null
        ? (widget.preloadedFileSize! / (1024 * 1024)).toStringAsFixed(2)
        : 'Unknown';
    final count = widget.preloadedFileCount ?? 1;
    final name = widget.preloadedFileName ?? 'Files';

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.insert_drive_file, size: AppSizes.iconHuge, color: Theme.of(context).colorScheme.primary),
        AppSpacing.gapH24,
        Text(
          'File(s) Shared With You',
          style: TextStyle(fontSize: AppSizes.textSubtitle, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
        AppSpacing.gapH8,
        Text(
          name,
          style: TextStyle(fontSize: AppSizes.textTitle, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        AppSpacing.gapH8,
        Text(
          '$count file(s) • $sizeMB MB',
          style: TextStyle(fontSize: AppSizes.textBody, color: Colors.grey),
        ),
        AppSpacing.gapH48,
        CustomButton(
          text: 'Download',
          icon: Icons.download,
          onPressed: _joinSessionFromLink,
        )
      ],
    );
  }

  Widget _buildMobileLayout(Widget content) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(padding: EdgeInsets.all(AppSizes.p24), child: content),
      ),
    );
  }

  Widget _buildDesktopLayout(Widget content) {
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: Container(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.1),
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(AppSizes.p64),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.download_rounded,
                      size: 150,
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.8),
                    ),
                    AppSpacing.gapH32,
                    const Text(
                      'Receive Files Fast',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    AppSpacing.gapH16,
                    Text(
                      'Click the share link sent by the sender, or enter a session code to receive files directly on your device.',
                      style: TextStyle(
                        fontSize: AppSizes.textSubtitle,
                        color: Colors.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Expanded(
          flex: 4,
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(AppSizes.p64),
              child: Container(
                padding: EdgeInsets.all(AppSizes.p48),
                constraints: const BoxConstraints(maxWidth: 500),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 40,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: content,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
