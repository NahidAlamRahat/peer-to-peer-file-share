import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/spacing.dart';
import '../blocs/connection/connection_bloc.dart';
import '../blocs/connection/connection_event.dart';
import '../blocs/connection/connection_state.dart';
import '../blocs/transfer/transfer_bloc.dart';
import '../blocs/transfer/transfer_event.dart';
import '../widgets/custom_buttons.dart';
import 'transfer_screen.dart';

class ShareLinkScreen extends StatefulWidget {
  const ShareLinkScreen({super.key});

  @override
  State<ShareLinkScreen> createState() => _ShareLinkScreenState();
}

class _ShareLinkScreenState extends State<ShareLinkScreen> {
  File? _selectedFile;
  bool _isPicking = false;

  void _pickFile() async {
    if (_isPicking) return;
    setState(() => _isPicking = true);

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles();
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final file = File(path);
        final sizeMB = (await file.length() / (1024 * 1024)).toStringAsFixed(2);
        debugPrint('📂 [UI] Selected File: ${file.uri.pathSegments.last} ($sizeMB MB)');
        
        setState(() {
          _selectedFile = file;
        });
        if (mounted) {
          context.read<ConnectionBloc>().add(CreateSessionEvent());
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
    // Capture the ConnectionBloc instance and the messenger to avoid async gap usage.
    final connectionBloc = context.read<ConnectionBloc>();
    final messenger = ScaffoldMessenger.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Share File')),
      body: BlocConsumer<ConnectionBloc, ConnectionStateBloc>(
        listener: (context, state) async {
          if (state is ConnectionCreated && _selectedFile != null) {
            // Send metadata so receiver knows what to download.
            final size = await _selectedFile!.length();
            final name = _selectedFile!.uri.pathSegments.last;
            
            // Safe to use connectionBloc as it was captured synchronously before
            connectionBloc.add(SendMessageEvent({
                   'action': 'file_metadata',
                   'fileName': name,
                   'fileSize': size,
            }));
            debugPrint('✅ [UI] Link generated! Session ID: ${state.sessionId}');
            debugPrint('📤 [UI] Sent file metadata: $name ($size bytes)');
          } else if (state is ConnectionConnected && _selectedFile != null) {
            // Once connected, dispatch the actual file to TransferBloc
            context.read<TransferBloc>().add(SendFileEvent(_selectedFile!));
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => TransferScreen(role: state.role, preflightMetadata: null)),
            );
          } else if (state is ConnectionFailed) {
            messenger.showSnackBar(
              SnackBar(content: Text('Connection failed: ${state.message}')),
            );
            // Don't pop immediately if it was a background connection issue
            if (_selectedFile == null) Navigator.pop(context); 
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
          if (_selectedFile == null) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(AppSizes.p24),
                child: Column(
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
                ),
              ),
            );
          }

          if (state is ConnectionLoading || state is ConnectionInitial || state is ConnectionProgress) {
            String statusText = 'Generating secure session...';
            double? progressValue;

            if (state is ConnectionProgress) {
              statusText = state.message;
              progressValue = state.progress;
            }

            return Center(
              child: Padding(
                padding: EdgeInsets.all(AppSizes.p32),
                child: Column(
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
                ),
              ),
            );
          } else if (state is ConnectionCreated) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(AppSizes.p24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Ask the receiver to enter this code\nto download:',
                      style: TextStyle(fontSize: AppSizes.textSubtitle, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                    AppSpacing.gapH8,
                    Text(_selectedFile!.uri.pathSegments.last, style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppSizes.textBody)),
                    AppSpacing.gapH32,
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: state.sessionId));
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Code copied to clipboard')),
                        );
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: AppSizes.p32, vertical: AppSizes.p16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
                        ),
                        child: Text(
                          state.sessionId,
                          style: TextStyle(
                            fontSize: AppSizes.textDisplay,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ),
                    AppSpacing.gapH48,
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
                        data: state.sessionId,
                        version: QrVersions.auto,
                        size: AppSizes.iconQr,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    AppSpacing.gapH48,
                    const CircularProgressIndicator(),
                    AppSpacing.gapH16,
                    const Text('Waiting for receiver to join...', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            );
          } else if (state is ConnectionServerError) {
             return Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSizes.p24),
                  child: Column(
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
                  ),
                ),
             );
          }
          return const SizedBox();
        },
      ),
    );
  }
}
