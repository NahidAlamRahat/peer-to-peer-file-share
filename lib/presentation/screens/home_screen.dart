import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../core/di/injection_container.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/spacing.dart';
import '../../domain/entities/peer_session.dart';
import '../blocs/connection/connection_bloc.dart';
import '../blocs/connection/connection_event.dart';
import '../blocs/connection/connection_state.dart';
import '../blocs/transfer/transfer_bloc.dart';
import '../blocs/transfer/transfer_event.dart';
import '../blocs/transfer/transfer_state.dart';
import '../widgets/custom_buttons.dart';
import '../widgets/responsive_layout.dart';
import 'receive_screen.dart';
import 'settings_screen.dart';
import 'share_link_screen.dart';
import 'transfer_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('P2P File Share'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SettingsScreen(settingsService: sl<SettingsService>()),
              ),
            ),
          ),
        ],
      ),
      body: BlocListener<ConnectionBloc, ConnectionStateBloc>(
        listener: (context, state) {
          if (state is ConnectionServerError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.orange.shade800,
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: 'Retry',
                  textColor: Colors.white,
                  onPressed: () {
                    context.read<ConnectionBloc>().add(ResetConnectionEvent());
                  },
                ),
              ),
            );
          }
        },
        child: ResponsiveLayout(
          mobileBody: _buildMobileLayout(context),
          desktopBody: _buildDesktopLayout(context),
        ),
      ),
    );
  }

  Widget _buildServerStatus() {
    return BlocBuilder<ConnectionBloc, ConnectionStateBloc>(
      builder: (context, state) {
         if (state is ConnectionServerError) {
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 16, color: Colors.red),
                  AppSpacing.gapW8,
                  Text(
                    'Signaling Server Offline',
                    style: TextStyle(color: Colors.red, fontSize: AppSizes.textSmall),
                  ),
                ],
              ),
            );
          }
          return const SizedBox.shrink();
      },
    );
  }

  Widget _buildHeroSection(BuildContext context, {bool isDesktop = false}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.cloud_upload_outlined,
          size: isDesktop ? 150 : 100,
          color: Theme.of(context).colorScheme.primary,
        ),
        AppSpacing.gapH32,
        Text(
          'Share files seamlessly',
          style: TextStyle(
            fontSize: isDesktop ? 48 : 28, 
            fontWeight: FontWeight.bold,
            height: 1.2,
          ),
          textAlign: TextAlign.center,
        ),
        AppSpacing.gapH16,
        Text(
          'No file size limit. Directly peer-to-peer. Fully encrypted.',
          style: TextStyle(
            fontSize: isDesktop ? AppSizes.textSubtitle : AppSizes.textBody, 
            color: Colors.grey,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildActionPanel(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CustomButton(
          text: 'Send Files',
          icon: Icons.send_rounded,
          isPrimary: true,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ShareLinkScreen()),
            );
          },
        ),
        AppSpacing.gapH16,
        CustomButton(
          text: 'Receive Files',
          icon: Icons.download_rounded,
          isPrimary: false,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReceiveScreen()),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return BlocBuilder<TransferBloc, TransferState>(
      builder: (context, transferState) {
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSizes.p24, vertical: AppSizes.p32),
          child: Column(
            children: [
              _buildServerStatus(),
              const Spacer(),
              _buildHeroSection(context, isDesktop: false),
              const Spacer(flex: 2),
              if (transferState is TransferInProgress || transferState is TransferSuccess) ...[
                _buildActiveTransferBanner(context, transferState),
                AppSpacing.gapH24,
              ],
              _buildActionPanel(context),
              AppSpacing.gapH32,
              if (kIsWeb) _buildAppDownloadBanner(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActiveTransferBanner(BuildContext context, TransferState state) {
    String title = 'Transfer in progress...';
    String fileName = '';
    double progress = 0;

    if (state is TransferInProgress) {
      fileName = state.fileName;
      progress = state.progress;
    } else if (state is TransferSuccess) {
      progress = 1.0;
      if (state.filePath == '__SENT__') {
        title = 'Files sent successfully!';
        fileName = 'Sharing complete';
      } else {
        title = 'Transfer complete!';
        fileName = 'File received';
      }
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () {
                  final connectionState = context.read<ConnectionBloc>().state;
                  SessionRole role = SessionRole.sender;
                  if (connectionState is ConnectionConnected) {
                    role = connectionState.role;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TransferScreen(role: role),
                    ),
                  );
                },
                child: Padding(
                  padding: EdgeInsets.all(AppSizes.p16),
                  child: Row(
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          if (state is TransferInProgress) ...[
                            SizedBox(
                              width: 32,
                              height: 32,
                              child: CircularProgressIndicator(
                                value: progress,
                                strokeWidth: 3,
                              ),
                            ),
                            Icon(Icons.play_arrow_rounded, size: 16, color: Theme.of(context).colorScheme.primary),
                          ] else ...[
                            Icon(Icons.check_circle_rounded, size: 32, color: Colors.green.shade600),
                          ],
                        ],
                      ),
                      AppSpacing.gapW16,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text(
                              fileName, 
                              style: TextStyle(fontSize: AppSizes.textSmall), 
                              maxLines: 1, 
                              overflow: TextOverflow.ellipsis
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            VerticalDivider(width: 1, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)),
            IconButton(
              onPressed: () {
                context.read<TransferBloc>().add(ResetTransferEvent());
              },
              icon: const Icon(Icons.close_rounded, size: 20),
              tooltip: 'Dismiss',
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(BuildContext context) {
    return Row(
      children: [
        // Left side: Hero Map/Illustration
        Expanded(
          flex: 5,
          child: Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.1),
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(AppSizes.p64),
                child: _buildHeroSection(context, isDesktop: true),
              ),
            ),
          ),
        ),
        // Right side: Action Panel Component
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
                 child: Column(
                   mainAxisSize: MainAxisSize.min,
                   children: [
                      _buildServerStatus(),
                      AppSpacing.gapH32,
                      const Text(
                        'Get Started',
                        style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                      ),
                      AppSpacing.gapH8,
                      const Text(
                        'Choose an action to proceed.',
                        style: TextStyle(color: Colors.grey),
                      ),
                      AppSpacing.gapH48,
                       _buildActionPanel(context),
                       if (kIsWeb) ...[
                         AppSpacing.gapH32,
                         _buildAppDownloadBanner(context),
                       ],
                   ],
                 ),
               ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAppDownloadBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppSizes.p20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primaryContainer,
            Theme.of(context).colorScheme.secondaryContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.download_for_offline_rounded,
                  color: Theme.of(context).colorScheme.primary, size: 28),
              AppSpacing.gapW12,
              Expanded(
                child: Text(
                  'Get the App — More Power! 🚀',
                  style: TextStyle(
                    fontSize: AppSizes.textSubtitle,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          AppSpacing.gapH12,
          _BannerFeatureRow(icon: Icons.wifi_off, text: 'Transfer continues when screen turns off'),
          AppSpacing.gapH8,
          _BannerFeatureRow(icon: Icons.play_circle_outline, text: 'Run in background — leave the app freely'),
          AppSpacing.gapH8,
          _BannerFeatureRow(icon: Icons.notifications_active_outlined, text: 'Live progress notification'),
          AppSpacing.gapH8,
          _BannerFeatureRow(icon: Icons.lock_outline, text: 'No browser tab restrictions'),
          AppSpacing.gapH16,
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                // Link to the APK hosted on the same server/Vercel
                launchUrlString(
                  '/apk/app-release.apk',
                  mode: LaunchMode.externalApplication,
                );
              },
              icon: const Icon(Icons.android, size: 20),
              label: const Text('Download for Android'),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                padding: EdgeInsets.symmetric(vertical: AppSizes.p12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Row widget for each feature bullet in the app download promotion banner.
class _BannerFeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _BannerFeatureRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        AppSpacing.gapW8,
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: AppSizes.textSmall,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
