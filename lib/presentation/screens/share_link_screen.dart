import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/di/injection_container.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/spacing.dart';
import '../../domain/entities/peer_session.dart';
import '../../domain/entities/share_file.dart';
import '../blocs/connection/connection_bloc.dart';
import '../blocs/connection/connection_event.dart';
import '../blocs/connection/connection_state.dart';
import '../blocs/transfer/transfer_bloc.dart';
import '../blocs/transfer/transfer_event.dart';
import '../blocs/transfer/transfer_state.dart';
import '../widgets/custom_buttons.dart';
import '../widgets/responsive_layout.dart';
import 'transfer_screen.dart';

class ShareLinkScreen extends StatefulWidget {
  const ShareLinkScreen({super.key});

  @override
  State<ShareLinkScreen> createState() => _ShareLinkScreenState();
}

class _ShareLinkScreenState extends State<ShareLinkScreen> {
  List<ShareFile> _selectedFiles = [];
  bool _isPicking = false;

  @override
  void initState() {
    super.initState();
    // Auto-redirect if transfer is already active
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final transferBloc = sl<TransferBloc>();
      // ONLY redirect if transfer is actively InProgress. 
      // Do NOT redirect if it's already Success (finished).
      if (transferBloc.state is TransferInProgress) {
        final connectionBloc = context.read<ConnectionBloc>();
        SessionRole role = SessionRole.sender;
        if (connectionBloc.state is ConnectionConnected) {
          role = (connectionBloc.state as ConnectionConnected).role;
        }
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => TransferScreen(role: role)),
        );
      }
    });
  }

  void _pickFile() async {
    if (_isPicking) return;
    setState(() => _isPicking = true);

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withReadStream: true, // Crucial for 1GB+ files to prevent RAM crashes
      );
      if (result != null && result.files.isNotEmpty) {
        final validFiles = result.files.where((f) => f.readStream != null || f.bytes != null).toList();
        if (validFiles.isNotEmpty) {
          final shareFiles = validFiles.map((pf) => ShareFile(
            name: pf.name,
            size: pf.size,
            readStream: pf.readStream,
            bytes: pf.bytes,
          )).toList();

          final totalSize = shareFiles.fold<int>(0, (sum, f) => sum + f.size);
          final sizeMB = (totalSize / (1024 * 1024)).toStringAsFixed(2);
          debugPrint('📂 [UI] Selected ${shareFiles.length} files ($sizeMB MB total)');

          setState(() {
            _selectedFiles = shareFiles;
          });
          if (mounted) {
            context.read<ConnectionBloc>().add(CreateSessionEvent());
          }
        }
      }
    } catch (e) {
      debugPrint("File picker error: $e");
    } finally {
      if (mounted) {
        setState(() => _isPicking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final connectionBloc = context.read<ConnectionBloc>();
    final messenger = ScaffoldMessenger.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        // Only warn if a session is active (files selected + session created/connected)
        final state = context.read<ConnectionBloc>().state;
        final isSessionActive = _selectedFiles.isNotEmpty &&
            (state is ConnectionCreated ||
                state is ConnectionConnected ||
                state is ConnectionMessageReceived);

        if (isSessionActive) {
          final shouldPop = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Cancel Session?'),
              content: const Text(
                  'If you go back now, the session will end and the receiver will not be able to connect. Are you sure?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('No, Stay',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Yes, Cancel',
                      style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ) ?? false;

          if (shouldPop && context.mounted) {
            context.read<ConnectionBloc>().add(ResetConnectionEvent());
            Navigator.of(context).pop();
          }
        } else {
          if (context.mounted) {
            context.read<ConnectionBloc>().add(ResetConnectionEvent());
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Share File'),
          elevation: 0,
        ),
        body: BlocConsumer<ConnectionBloc, ConnectionStateBloc>(
        listener: (context, state) async {
          if (state is ConnectionCreated && _selectedFiles.isNotEmpty) {
            debugPrint('✅ [UI] Link generated! Session ID: ${state.sessionId}');
          } else if (state is ConnectionConnected && _selectedFiles.isNotEmpty) {
            // Send metadata NOW (receiver is connected)
            final totalSize = _selectedFiles.fold<int>(0, (sum, f) => sum + f.size);
            connectionBloc.add(SendMessageEvent({
                   'action': 'files_metadata',
                   'filesCount': _selectedFiles.length,
                   'totalSize': totalSize,
                   'firstFileName': _selectedFiles.first.name,
            }));
            debugPrint('📤 [UI] Sent file metadata: ${_selectedFiles.length} files ($totalSize bytes)');
            // DO NOT automatically stream file and navigate to TransferScreen anymore.
            // We stay on ShareLinkScreen and show a "Receiver connected, waiting for them to accept" UI.
          } else if (state is ConnectionMessageReceived) {
             if (state.payload['action'] == 'accept_download' && _selectedFiles.isNotEmpty) {
                if (mounted) {
                   context.read<TransferBloc>().add(SendFilesEvent(_selectedFiles));
                   Navigator.pushReplacement(
                     context,
                     MaterialPageRoute(builder: (_) => TransferScreen(role: SessionRole.sender, preflightMetadata: null)),
                   );
                }
             }
          } else if (state is ConnectionFailed) {
            messenger.showSnackBar(
              SnackBar(content: Text('Connection failed: ${state.message}')),
            );
            if (_selectedFiles.isEmpty) Navigator.pop(context);
          } else if (state is ConnectionServerError) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.red.shade700,
              ),
            );
          }
        },
        builder: (context, state) {
          // Determine the main dynamic content based on state
          Widget content;

          if (_selectedFiles.isEmpty) {
             content = _buildFileSelectionState();
          } else if (state is ConnectionLoading || state is ConnectionInitial || state is ConnectionProgress) {
             content = _buildGeneratingSessionState(state);
          } else if (state is ConnectionCreated) {
             content = _buildSessionCreatedState(state, messenger);
          } else if (state is ConnectionConnected || (state is ConnectionMessageReceived && state.payload['action'] != 'accept_download')) {
             content = _buildReceiverConnectedState();
          } else if (state is ConnectionServerError) {
             content = _buildErrorState(state);
          } else {
             content = const SizedBox();
          }

          return ResponsiveLayout(
             mobileBody: _buildMobileLayout(content),
             desktopBody: _buildDesktopLayout(content),
          );
        },
      ),
    ));
  }

  Widget _buildFileSelectionState() {
     return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.upload_file, size: AppSizes.iconHuge, color: Colors.grey),
          AppSpacing.gapH16,
          Text('Select a file to share', style: TextStyle(fontSize: AppSizes.textTitle)),
          AppSpacing.gapH32,
          CustomButton(
            text: 'Pick File',
            onPressed: _pickFile,
          )
        ],
     );
  }

  Widget _buildGeneratingSessionState(ConnectionStateBloc state) {
     String statusText = 'Generating secure session...';
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
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
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
                       backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
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

  /// Builds the full shareable link from the session ID + file info.
  /// File info is encoded in URL so receiver can preview before connecting.
  String _buildShareLink(String sessionId) {
    final totalSize = _selectedFiles.fold<int>(0, (sum, f) => sum + f.size);
    final firstName = _selectedFiles.isNotEmpty
        ? Uri.encodeComponent(_selectedFiles.first.name)
        : '';
    final count = _selectedFiles.length;

    final params = 'session=$sessionId&name=$firstName&size=$totalSize&count=$count';

    if (kIsWeb) {
      try {
        final origin = Uri.base.origin;
        return '$origin/?$params';
      } catch (_) {}
    }
    return 'https://peertransfer.app/?$params';
  }

  Widget _buildSessionCreatedState(ConnectionCreated state, ScaffoldMessengerState messenger) {
      final shareLink = _buildShareLink(state.sessionId);

      return Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Share this link with the receiver:',
            style: TextStyle(fontSize: AppSizes.textSubtitle, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          AppSpacing.gapH8,
          Text('${_selectedFiles.length} file(s) selected', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppSizes.textBody)),
          AppSpacing.gapH24,

          // ── Link display box ──────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: AppSizes.p16, vertical: AppSizes.p12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
            ),
            child: Text(
              shareLink,
              style: TextStyle(
                fontSize: AppSizes.textSmall,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          AppSpacing.gapH16,

          // ── Copy Link button ──────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: shareLink));
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('✅ Link copied! Share it with the receiver.'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy Link'),
              style: FilledButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: AppSizes.p16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
                ),
              ),
            ),
          ),
          AppSpacing.gapH32,

          // ── QR Code (encodes the full link so camera opens web/app) ───────
          Text(
            'Or scan QR code to open directly:',
            style: TextStyle(fontSize: AppSizes.textSmall, color: Colors.grey),
          ),
          AppSpacing.gapH12,
          Container(
            padding: EdgeInsets.all(AppSizes.p16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
              boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      spreadRadius: 1,
                  )
              ]
            ),
            child: QrImageView(
              data: shareLink,  // Full link so scan = click
              version: QrVersions.auto,
              size: AppSizes.iconQr,
              backgroundColor: Colors.white,
            ),
          ),
          AppSpacing.gapH32,
          const CircularProgressIndicator(),
          AppSpacing.gapH16,
          const Text('Waiting for receiver to join...', style: TextStyle(color: Colors.grey)),
          AppSpacing.gapH24,
          // ── Keep screen open warning ──────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Keep this screen open until the receiver joins. Closing the app will end the session.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.orange,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
  }

  Widget _buildReceiverConnectedState() {
     return Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline, size: AppSizes.iconHuge, color: Colors.green),
          AppSpacing.gapH24,
          Text(
            'Receiver Connected!',
            style: TextStyle(fontSize: AppSizes.textHeadline, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          AppSpacing.gapH16,
          const Text('Waiting for the receiver to confirm the download...', style: TextStyle(color: Colors.grey), textAlign: TextAlign.center),
          AppSpacing.gapH48,
          const CircularProgressIndicator(),
        ],
     );
  }

  Widget _buildErrorState(ConnectionServerError state) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
           Icon(Icons.cloud_off, size: AppSizes.iconHuge, color: Colors.redAccent),
           AppSpacing.gapH24,
           const Text('Server Unreachable', style: TextStyle(fontWeight: FontWeight.bold)),
           AppSpacing.gapH16,
           Text(state.message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
           AppSpacing.gapH32,
           CustomButton(
             text: 'Retry Connection',
             onPressed: () {
               context.read<ConnectionBloc>().add(ResetConnectionEvent());
             },
           )
        ],
      );
  }

  Widget _buildMobileLayout(Widget content) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(AppSizes.p24),
          child: content,
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(Widget content) {
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: Container(
             color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.1),
             child: Center(
               child: SingleChildScrollView(
                 padding: EdgeInsets.all(AppSizes.p64),
                 child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                       Icon(
                         Icons.upload_file_rounded,
                         size: 150,
                         color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                       ),
                       AppSpacing.gapH32,
                       const Text(
                         'Securely Send Files',
                         style: TextStyle(
                           fontSize: 48, 
                           fontWeight: FontWeight.bold,
                           height: 1.2,
                         ),
                         textAlign: TextAlign.center,
                       ),
                       AppSpacing.gapH16,
                       Text(
                          'Generate a shareable link or scan the QR code to transfer files instantly — no code needed.',
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
        )
      ],
    );
  }
}
