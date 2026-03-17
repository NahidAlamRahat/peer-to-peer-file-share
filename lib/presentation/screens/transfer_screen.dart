import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/spacing.dart';
import '../../domain/entities/peer_session.dart';
import '../../domain/entities/share_file.dart';
import '../blocs/connection/connection_bloc.dart';
import '../blocs/connection/connection_event.dart';
import '../blocs/transfer/transfer_bloc.dart';
import '../blocs/transfer/transfer_event.dart';
import '../blocs/transfer/transfer_state.dart';
import '../widgets/custom_buttons.dart';

class TransferScreen extends StatefulWidget {
  final SessionRole role;
  final Map<String, dynamic>? preflightMetadata;

  const TransferScreen({super.key, required this.role, this.preflightMetadata});

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        // Disconnect when moving back
        context.read<ConnectionBloc>().add(ResetConnectionEvent());
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Transfer'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              context.read<ConnectionBloc>().add(ResetConnectionEvent());
              Navigator.of(context).pop();
            },
          ),
        ),
        body: DefaultTabController(
          length: 1,
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSizes.p24),
                    child: BlocBuilder<TransferBloc, TransferState>(
                      builder: (context, state) {
                        return _buildTransferBody(state);
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTransferBody(TransferState state) {
    if (state is TransferInitial) {
      if (widget.role == SessionRole.sender) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: AppSizes.iconHuge, color: Colors.green),
            AppSpacing.gapH16,
            Text('Peer connected!', style: TextStyle(fontSize: AppSizes.textHeadline, fontWeight: FontWeight.bold)),
            AppSpacing.gapH32,
            CustomButton(
              text: 'Select File to Send',
              icon: Icons.upload_file,
              onPressed: () async {
                FilePickerResult? result = await FilePicker.platform.pickFiles(
                  withData: true,
                );
                if (result != null && result.files.single.bytes != null) {
                  final pf = result.files.single;
                  final shareFile = ShareFile(
                    name: pf.name,
                    size: pf.bytes!.length,
                    bytes: pf.bytes!,
                  );
                  // ignore: use_build_context_synchronously
                  context.read<TransferBloc>().add(SendFileEvent(shareFile));
                }
              },
            ),
          ],
        );
      } else {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_tethering, size: AppSizes.iconHuge, color: Colors.blueAccent),
            AppSpacing.gapH16,
            Text('Connecting to peer...', style: TextStyle(fontSize: AppSizes.textHeadline, fontWeight: FontWeight.bold)),
            AppSpacing.gapH16,
            const Text('Starting your download now.'),
            AppSpacing.gapH32,
            const Text(
              '⚠️ Please keep this app open during the transfer',
              style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
            )
          ],
        );
      }
    } else if (state is TransferInProgress) {
      final speedKB = state.transferSpeed / 1024;
      final speedText = speedKB > 1024 
          ? '${(speedKB / 1024).toStringAsFixed(2)} MB/s' 
          : '${speedKB.toStringAsFixed(1)} KB/s';

      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(AppSizes.p20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                Icon(
                  widget.role == SessionRole.sender ? Icons.upload_outlined : Icons.download_outlined,
                  size: AppSizes.iconLarge,
                  color: Theme.of(context).colorScheme.primary,
                ),
                AppSpacing.gapH12,
                Text(
                  state.fileName,
                  style: TextStyle(fontSize: AppSizes.textBody, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                AppSpacing.gapH8,
                Text(
                  '${(state.bytesTransferred / (1024 * 1024)).toStringAsFixed(2)} MB / ${(state.totalSize / (1024 * 1024)).toStringAsFixed(2)} MB',
                  style: TextStyle(fontSize: AppSizes.textSmall, color: Colors.grey),
                ),
              ],
            ),
          ),
          AppSpacing.gapH48,
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 180,
                height: 180,
                child: CircularProgressIndicator(
                  value: state.progress,
                  strokeWidth: 10,
                  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  strokeCap: StrokeCap.round,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${(state.progress * 100).toInt()}%',
                    style: TextStyle(fontSize: AppSizes.textDisplay, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    speedText,
                    style: TextStyle(
                      fontSize: AppSizes.textSmall,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          AppSpacing.gapH48,
          Container(
            padding: EdgeInsets.symmetric(horizontal: AppSizes.p16, vertical: AppSizes.p12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                AppSpacing.gapW8,
                Text(
                  'Keep app open for live P2P transfer',
                  style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.w600, fontSize: AppSizes.textSmall),
                ),
              ],
            ),
          ),
          if (state.progress >= 1.0 && widget.role == SessionRole.sender)
             Padding(
              padding: EdgeInsets.only(top: AppSizes.p32),
              child: Text('✅ Sent Successfully!', style: TextStyle(color: Colors.green, fontSize: AppSizes.textSubtitle, fontWeight: FontWeight.bold)),
            ),
        ],
      );
    } else if (state is TransferSuccess) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, size: AppSizes.iconHuge, color: Colors.green),
          AppSpacing.gapH24,
          Text('Transfer Complete!', style: TextStyle(fontSize: AppSizes.textHeadline, fontWeight: FontWeight.bold)),
          AppSpacing.gapH16,
          Text('Saved at: \n${state.filePath}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
        ],
      );
    } else if (state is TransferFailure) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: AppSizes.iconHuge, color: Colors.red),
          AppSpacing.gapH24,
          Text('Transfer Failed', style: TextStyle(fontSize: AppSizes.textHeadline, fontWeight: FontWeight.bold)),
          AppSpacing.gapH16,
          Text(state.error, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
          AppSpacing.gapH32,
          CustomButton(
            text: 'Retry Connection',
            onPressed: () {
               // Soft reset the transfer screen, keeping them here.
               // It's tricky to restart just WebRTC fully from here without going back,
               // so we will advise the user to go back and retry code.
               context.read<ConnectionBloc>().add(ResetConnectionEvent());
               Navigator.of(context).pop();
            },
          )
        ],
      );
    }
    return const SizedBox();
  }
}
