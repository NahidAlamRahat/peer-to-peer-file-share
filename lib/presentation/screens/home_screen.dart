import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../core/di/injection_container.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/spacing.dart';
import '../../domain/entities/peer_session.dart';
import '../../domain/repositories/file_transfer_repository.dart';
import '../blocs/connection/connection_bloc.dart';
import '../blocs/connection/connection_state.dart';
import '../blocs/transfer/transfer_bloc.dart';
import '../blocs/transfer/transfer_event.dart';
import '../blocs/transfer/transfer_state.dart';
import '../widgets/custom_buttons.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/ad_banner_widget.dart';
import 'about_screen.dart';
import 'offline_receive_screen.dart';
import 'offline_send_screen.dart';
import 'settings_screen.dart';
import 'transfer_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PeerTransfer'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            tooltip: 'About',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    SettingsScreen(settingsService: sl<SettingsService>()),
              ),
            ),
          ),
        ],
      ),
      body: ResponsiveLayout(
        mobileBody: _buildMobileLayout(context),
        desktopBody: _buildDesktopLayout(context),
      ),
    );
  }

  Widget _buildServerStatus() {
    // Offline mode — no server status needed
    return const SizedBox.shrink();
  }


  Widget _buildHeroSection(
    BuildContext context, {
    double? totalHeight,
    bool isDesktop = false,
  }) {
    final effectiveHeight = totalHeight ?? 700.0;
    final iconSize =
        isDesktop ? 150.0 : (effectiveHeight * 0.11).clamp(44.0, 96.0);
    final titleSize =
        isDesktop ? 48.0 : (effectiveHeight * 0.035).clamp(18.0, 28.0);
    final subtitleSize = isDesktop
        ? AppSizes.textSubtitle
        : (effectiveHeight * 0.018).clamp(11.0, 14.5);
    final gapLarge =
        isDesktop ? 32.0 : (effectiveHeight * 0.024).clamp(8.0, 22.0);
    final gapSmall =
        isDesktop ? 16.0 : (effectiveHeight * 0.014).clamp(6.0, 14.0);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.wifi_rounded,
          size: iconSize,
          color: Theme.of(context).colorScheme.primary,
        ),
        SizedBox(height: gapLarge),
        Text(
          'Share files seamlessly\nwith PeerTransfer',
          style: TextStyle(
            fontSize: titleSize,
            fontWeight: FontWeight.bold,
            height: 1.2,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: gapSmall),
        Text(
          'No file size limit. No internet needed. Fully encrypted.',
          style: TextStyle(
            fontSize: subtitleSize,
            color: Colors.grey,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildActionPanel(BuildContext context, {double? totalHeight}) {
    final effectiveHeight = totalHeight ?? 700.0;
    final btnHeight = (effectiveHeight * 0.065).clamp(44.0, 56.0);
    final btnFontSize = (effectiveHeight * 0.021).clamp(14.0, 17.0);
    final btnIconSize = (effectiveHeight * 0.028).clamp(18.0, 24.0);
    final btnGap = (effectiveHeight * 0.016).clamp(8.0, 16.0);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomButton(
          text: 'Send Files',
          icon: Icons.send_rounded,
          isPrimary: true,
          height: btnHeight,
          fontSize: btnFontSize,
          iconSize: btnIconSize,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OfflineSendScreen()),
            );
          },
        ),
        SizedBox(height: btnGap),
        CustomButton(
          text: 'Receive Files',
          icon: Icons.download_rounded,
          isPrimary: false,
          height: btnHeight,
          fontSize: btnFontSize,
          iconSize: btnIconSize,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OfflineReceiveScreen()),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return BlocBuilder<TransferBloc, TransferState>(
      builder: (context, transferState) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final h = constraints.maxHeight;
            final w = constraints.maxWidth;
            final isSmall = h < 620;
            final isVerySmall = h < 520;

            final padH = (w * 0.06).clamp(16.0, 28.0);
            final padV = (h * 0.015).clamp(8.0, 16.0);

            return Padding(
              padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
              child: Column(
                children: [
                  _buildServerStatus(),

                  // ── Hero Section (Proportional via Expanded & FittedBox) ───
                  Expanded(
                    flex: 6,
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _buildHeroSection(
                          context,
                          totalHeight: h,
                          isDesktop: false,
                        ),
                      ),
                    ),
                  ),

                  // ── Active Transfer Banner (if active) ─────────────────────
                  if ((transferState is TransferInProgress ||
                          transferState is TransferSuccess) &&
                      !sl<FileTransferRepository>().isCancelled) ...[
                    _buildActiveTransferBanner(context, transferState),
                    SizedBox(height: (h * 0.015).clamp(8.0, 16.0)),
                  ],

                  // ── Action Buttons (Send / Receive) ────────────────────────
                  _buildActionPanel(context, totalHeight: h),

                  // ── Flexible Spacer ────────────────────────────────────────
                  const Spacer(flex: 1),

                  // ── Bottom Section: Tip, Download (Web), Ad ────────────────
                  if (kIsWeb) ...[
                    if (!isVerySmall) ...[
                      _buildSpeedTip(context, isCompact: true),
                      SizedBox(height: (h * 0.01).clamp(6.0, 10.0)),
                    ],
                    _buildAppDownloadBanner(context, isCompact: true),
                  ] else ...[
                    _buildSpeedTip(context, isCompact: isSmall),
                  ],
                  SizedBox(height: (h * 0.01).clamp(6.0, 10.0)),

                  // ── Banner Ad ─────────────────────────────────────────────
                  const AdBannerWidget(),
                ],
              ),
            );
          },
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
        color: Theme.of(
          context,
        ).colorScheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
        ),
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
                            Icon(
                              Icons.play_arrow_rounded,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ] else ...[
                            Icon(
                              Icons.check_circle_rounded,
                              size: 32,
                              color: Colors.green.shade600,
                            ),
                          ],
                        ],
                      ),
                      AppSpacing.gapW16,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              fileName,
                              style: TextStyle(fontSize: AppSizes.textSmall),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            VerticalDivider(
              width: 1,
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.1),
            ),
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
    return BlocBuilder<TransferBloc, TransferState>(
      builder: (context, transferState) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final h = constraints.maxHeight;
            final padOuter = (h * 0.04).clamp(16.0, 48.0);
            final padCard = (h * 0.035).clamp(16.0, 36.0);
            final gapLarge = (h * 0.025).clamp(10.0, 24.0);
            final gapSmall = (h * 0.012).clamp(4.0, 12.0);

            return Row(
              children: [
                // Left side: Hero Section
                Expanded(
                  flex: 5,
                  child: Container(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.1),
                    padding: EdgeInsets.all(padOuter),
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _buildHeroSection(
                          context,
                          totalHeight: h,
                          isDesktop: true,
                        ),
                      ),
                    ),
                  ),
                ),
                // Right side: Action Panel
                Expanded(
                  flex: 4,
                  child: Container(
                    padding: EdgeInsets.all(padOuter),
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Container(
                          width: 460,
                          padding: EdgeInsets.all(padCard),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius:
                                BorderRadius.circular(AppSizes.radiusLarge),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 32,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildServerStatus(),
                              const Text(
                                'Get Started',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: gapSmall),
                              const Text(
                                'Choose an action to proceed.',
                                style: TextStyle(color: Colors.grey),
                              ),
                              SizedBox(height: gapLarge),
                              if ((transferState is TransferInProgress ||
                                      transferState is TransferSuccess) &&
                                  !sl<FileTransferRepository>().isCancelled) ...[
                                _buildActiveTransferBanner(
                                  context,
                                  transferState,
                                ),
                                SizedBox(height: gapSmall),
                              ],
                              _buildActionPanel(context, totalHeight: h),
                              SizedBox(height: gapLarge),
                              if (kIsWeb) ...[
                                _buildSpeedTip(context, isCompact: true),
                                SizedBox(height: gapSmall),
                                _buildAppDownloadBanner(
                                  context,
                                  isCompact: true,
                                ),
                              ] else ...[
                                _buildSpeedTip(context, isCompact: h < 750),
                              ],
                              SizedBox(height: gapSmall),
                              // ── Banner Ad ─────────────────────────────────────────
                              const AdBannerWidget(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSpeedTip(BuildContext context, {bool isCompact = false}) {
    if (isCompact) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
          border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.tips_and_updates_rounded,
              color: Colors.blue,
              size: 15,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '💡 Tip: Connect both to same Wi-Fi for maximum speed',
                style: TextStyle(
                  color: Colors.blue.shade700,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppSizes.p16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.blue.withValues(alpha: 0.08),
            Colors.indigo.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.tips_and_updates_rounded,
              color: Colors.blue,
              size: 16,
            ),
          ),
          AppSpacing.gapW8,
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '💡 Pro Tip — Best Speed',
                  style: TextStyle(
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.bold,
                    fontSize: AppSizes.textSmall,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'For the fastest transfer, connect both devices to the same Wi-Fi network. Mobile data works great too — speeds may vary based on your signal strength.',
                  style: TextStyle(
                    color: Colors.blue.shade600,
                    fontSize: AppSizes.textSmall,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppDownloadBanner(
    BuildContext context, {
    bool isCompact = false,
  }) {
    if (isCompact) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.6),
              Theme.of(context)
                  .colorScheme
                  .secondaryContainer
                  .withValues(alpha: 0.4),
            ],
          ),
          borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
          border: Border.all(
            color: Theme.of(context)
                .colorScheme
                .primary
                .withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.android_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Get Android App',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  Text(
                    'Background transfer & screen-off support',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                launchUrlString(
                  '/apk/PeerTransfer.apk',
                  mode: LaunchMode.externalApplication,
                );
              },
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                minimumSize: const Size(0, 32),
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusSmall),
                ),
              ),
              child: const Text('Download', style: TextStyle(fontSize: 11.5)),
            ),
          ],
        ),
      );
    }

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
              Icon(
                Icons.download_for_offline_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 28,
              ),
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
          _BannerFeatureRow(
            icon: Icons.wifi_off,
            text: 'Transfer continues when screen turns off',
          ),
          AppSpacing.gapH8,
          _BannerFeatureRow(
            icon: Icons.play_circle_outline,
            text: 'Run in background — leave the app freely',
          ),
          AppSpacing.gapH8,
          _BannerFeatureRow(
            icon: Icons.notifications_active_outlined,
            text: 'Live progress notification',
          ),
          AppSpacing.gapH8,
          _BannerFeatureRow(
            icon: Icons.lock_outline,
            text: 'No browser tab restrictions',
          ),
          AppSpacing.gapH16,
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                launchUrlString(
                  '/apk/PeerTransfer.apk',
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
