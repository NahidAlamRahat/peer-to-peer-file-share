import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../core/di/injection_container.dart';
import '../../core/services/ad_service.dart';
import '../../core/services/interstitial_ad_service.dart';
import '../../core/services/notification_service.dart';
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
import 'home_screen.dart';

class TransferScreen extends StatefulWidget {
  final SessionRole role;
  final Map<String, dynamic>? preflightMetadata;

  const TransferScreen({super.key, required this.role, this.preflightMetadata});

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  final _settings = sl<SettingsService>();
  final _notifications = sl<NotificationService>();

  // True while WE are in the process of cancelling — prevents the
  // ConnectionBloc listener from showing "connection failed" on our screen.
  bool _isLocalCancelling = false;

  @override
  void initState() {
    super.initState();
    // Conditionally keep screen on based on user preference
    if (_settings.keepScreenOn) {
      WakelockPlus.enable();
    }
    // Start background execution on Android if user enabled it
    if (!kIsWeb && _settings.runInBackground) {
      _startBackgroundExecution();
    }
    // Request notification permission when starting a transfer
    _notifications.requestPermission();
  }

  DateTime _lastNotificationUpdate = DateTime.now();

  Future<void> _startBackgroundExecution() async {
    const androidConfig = FlutterBackgroundAndroidConfig(
      notificationTitle: 'P2P File Transfer',
      notificationText:
          'Running in the background to ensure transfer completes.',
      notificationIcon: AndroidResource(
        name: 'ic_notification',
        defType: 'drawable',
      ),
      notificationImportance: AndroidNotificationImportance.high,
      enableWifiLock: true,
    );
    final hasPermissions = await FlutterBackground.initialize(
      androidConfig: androidConfig,
    );
    if (hasPermissions) {
      await FlutterBackground.enableBackgroundExecution();
    }
  }

  Future<void> _stopBackgroundExecution() async {
    if (!kIsWeb && FlutterBackground.isBackgroundExecutionEnabled) {
      await FlutterBackground.disableBackgroundExecution();
    }
    _notifications.cancelProgressNotification();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _stopBackgroundExecution();
    super.dispose();
  }

  Future<void> _confirmAndCancelTransfer(BuildContext context) async {
    final primaryColor = Theme.of(context).colorScheme.primary;

    final shouldCancel =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.redAccent,
                    size: 24,
                  ),
                ),
                AppSpacing.gapW12,
                const Text(
                  'Cancel Transfer?',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                ),
              ],
            ),
            content: const Text(
              'Are you sure you want to stop the file transfer? This will disconnect the peer connection and cancel the current sharing session. Any unfinished files will need to be sent again.',
              style: TextStyle(fontSize: 15, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                child: Text(
                  'Keep Sharing',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
                  ),
                ),
                child: const Text(
                  'Yes, Cancel',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (shouldCancel && context.mounted) {
      final myRole = widget.role == SessionRole.sender ? 'sender' : 'receiver';
      final tBloc = context.read<TransferBloc>();
      final cBloc = context.read<ConnectionBloc>();

      // Mark that WE are cancelling — blocks the ConnectionBloc listener
      // from showing "connection failed" on our own screen.
      _isLocalCancelling = true;

      // Step 1: Send cancel message to peer IMMEDIATELY so they get it before connection drops
      tBloc.add(CancelTransferEvent(myRole: myRole));

      // Step 2: Wait a moment so the cancel signal has time to reach the peer
      await Future.delayed(const Duration(milliseconds: 600));
      if (!context.mounted) return;

      // Step 3: Navigate home silently — canceller sees nothing
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );

      // Step 4: Reset the connection after navigation
      // Give the WebRTC buffer enough time to flush the cancel message
      Future.delayed(const Duration(seconds: 3), () {
        cBloc.add(ResetConnectionEvent());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        final state = context.read<TransferBloc>().state;
        if (state is TransferInProgress || state is TransferInitial) {
          _confirmAndCancelTransfer(context);
        } else {
          if (context.mounted) {
            final tBloc = context.read<TransferBloc>();
            final cBloc = context.read<ConnectionBloc>();
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const HomeScreen()),
              (route) => false,
            );
            Future.delayed(const Duration(milliseconds: 400), () {
              tBloc.add(ResetTransferEvent());
              cBloc.add(ResetConnectionEvent());
            });
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Live Transfer'), elevation: 0),
        body: BlocListener<ConnectionBloc, ConnectionStateBloc>(
          listener: (context, connectionState) {
            final transferState = context.read<TransferBloc>().state;
            final peerAlreadyCancelled =
                transferState is TransferCancelledByPeer;
            // Only react to actual connection drops — NOT ConnectionInitial (fires on setup/reset)
            // Also skip if WE are the one who cancelled (_isLocalCancelling = true).
            if (!peerAlreadyCancelled &&
                !_isLocalCancelling &&
                (connectionState is ConnectionFailed ||
                    connectionState is ConnectionOffline)) {
              // Wait 1.5s first — give time for any incoming peer cancel message to arrive
              Future.delayed(const Duration(milliseconds: 1500), () {
                if (context.mounted) {
                  final currentState = context.read<TransferBloc>().state;
                  // Only show error if we are still in an active/loading state
                  if (currentState is! TransferCancelledByPeer &&
                      currentState is! TransferSuccess &&
                      currentState is! TransferFailure) {
                    context.read<TransferBloc>().add(
                      const TransferErrorEvent(
                        'Connection to peer was lost. Please check your network and try again.',
                      ),
                    );
                  }
                }
              });
            }
          },
          child: BlocConsumer<TransferBloc, TransferState>(
            listener: (context, state) {
              if (state is TransferInProgress) {
                final now = DateTime.now();
                if (now.difference(_lastNotificationUpdate).inMilliseconds >
                        500 ||
                    state.progress >= 1.0) {
                  _lastNotificationUpdate = now;
                  _notifications.showProgressNotification(
                    progress: (state.progress * 100).toInt(),
                    fileName: state.fileName,
                  );
                }
              } else if (state is TransferSuccess) {
                WakelockPlus.disable();
                _stopBackgroundExecution();
                _notifications.showTransferComplete(
                  isSender: widget.role == SessionRole.sender,
                  fileName: state.filePath.split('/').last.split('\\').last,
                );
                if (!kIsWeb && AdService.instance.adsEnabled) {
                  Future.delayed(const Duration(seconds: 1), () {
                    InterstitialAdService.instance.show();
                  });
                }
              } else if (state is TransferFailure) {
                // Connection lost or system error — show notification to both sides
                WakelockPlus.disable();
                _stopBackgroundExecution();
                _notifications.showTransferFailed(reason: state.error);
              } else if (state is TransferCancelledByPeer) {
                // Peer cancelled — show notification only to the one who did NOT cancel
                WakelockPlus.disable();
                _stopBackgroundExecution();
                _notifications.showTransferFailed(reason: state.message);
              } else if (state is TransferCancelledBySelf) {
                // Receiver cancelled from browser's native download bar — go home silently
                WakelockPlus.disable();
                _stopBackgroundExecution();
                if (context.mounted) {
                  final tBloc = context.read<TransferBloc>();
                  final cBloc = context.read<ConnectionBloc>();
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const HomeScreen()),
                    (route) => false,
                  );
                  Future.delayed(const Duration(milliseconds: 400), () {
                    tBloc.add(ResetTransferEvent());
                    cBloc.add(ResetConnectionEvent());
                  });
                }
              } else if (state is TransferIncognitoError) {
                // Incognito mode detected — show an unmissable dialog
                WakelockPlus.disable();
                _stopBackgroundExecution();
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => AlertDialog(
                    title: const Text('Incognito Mode Not Supported'),
                    content: const Text(
                      'Files cannot be downloaded securely in Incognito mode.\n\n'
                      'Please open this app in a normal tab to download files.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (_) => const HomeScreen(),
                            ),
                            (route) => false,
                          );
                        },
                        child: const Text('Go Home'),
                      ),
                    ],
                  ),
                );
              }
              // NOTE: CancelTransferEvent → canceller goes home silently (handled in _confirmAndCancelTransfer)
              // so we intentionally do NOT show any notification/UI for the canceller here.
            },
            builder: (context, state) {
              final content = _buildTransferBody(state);
              return ResponsiveLayout(
                mobileBody: _buildMobileLayout(content),
                desktopBody: _buildDesktopLayout(content),
              );
            },
          ),
        ), // Close BlocListener
      ),
    );
  }

  Widget _buildTransferBody(TransferState state) {
    if (state is TransferInitial) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.wifi_tethering,
            size: AppSizes.iconHuge,
            color: Colors.blueAccent,
          ),
          AppSpacing.gapH16,
          Text(
            widget.role == SessionRole.sender
                ? 'Verifying Connection...'
                : 'Connecting to peer...',
            style: TextStyle(
              fontSize: AppSizes.textHeadline,
              fontWeight: FontWeight.bold,
            ),
          ),
          AppSpacing.gapH8,
          Text(
            widget.role == SessionRole.sender
                ? 'Checking peer status before transfer...'
                : 'Waiting for sender to start...',
            style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
          ),
        ],
      );
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
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              children: [
                Icon(
                  widget.role == SessionRole.sender
                      ? Icons.upload_outlined
                      : Icons.download_outlined,
                  size: AppSizes.iconLarge,
                  color: Theme.of(context).colorScheme.primary,
                ),
                AppSpacing.gapH12,
                Text(
                  state.fileName,
                  style: TextStyle(
                    fontSize: AppSizes.textBody,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                AppSpacing.gapH8,
                if (state.totalFiles > 1)
                  Text(
                    'File ${state.fileIndex} of ${state.totalFiles}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                if (state.totalFiles > 1) AppSpacing.gapH4,
                Text(
                  '${(state.bytesTransferred / (1024 * 1024)).toStringAsFixed(2)} MB / ${(state.totalSize / (1024 * 1024)).toStringAsFixed(2)} MB',
                  style: TextStyle(
                    fontSize: AppSizes.textSmall,
                    color: Colors.grey,
                  ),
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
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  strokeCap: StrokeCap.round,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${(state.progress * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: AppSizes.textDisplay,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    speedText,
                    style: TextStyle(
                      fontSize: AppSizes.textSmall,
                      color: state.isStalled
                          ? Colors.orange
                          : Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  // ETA display
                  if (state.estimatedSecondsLeft != null && state.estimatedSecondsLeft! > 0) ...
                    [
                      const SizedBox(height: 2),
                      Text(
                        _formatEta(state.estimatedSecondsLeft!),
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                ],
              ),
            ],
          ),
          AppSpacing.gapH24,
          AppSpacing.gapH24,
          Builder(
            builder: (context) {
              final connType = context.read<ConnectionBloc>().currentConnectionType;
              if (connType != null) {
                final isRelay = connType == 'relay';
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isRelay 
                        ? Colors.orange.withValues(alpha: 0.1) 
                        : Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isRelay 
                          ? Colors.orange.withValues(alpha: 0.5) 
                          : Colors.green.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isRelay ? Icons.cloud_sync_rounded : Icons.flash_on_rounded,
                        color: isRelay ? Colors.orange : Colors.green,
                        size: 16,
                      ),
                      AppSpacing.gapW4,
                      Text(
                        isRelay ? 'Connection: TURN Relay (Slower)' : 'Connection: Direct P2P (Fast)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isRelay ? Colors.orange.shade700 : Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          AppSpacing.gapH24,
          // ── Stall warning banner ──────────────────────────────────────────
          // Shown when no progress for 10+ seconds. Reassures the user the
          // transfer is still active — just slow via TURN relay.
          if (state.isStalled) ...[  
            _StallWarningBanner(),
            AppSpacing.gapH8,
          ],
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: AppSizes.p16,
              vertical: AppSizes.p12,
            ),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange,
                  size: 20,
                ),
                AppSpacing.gapW8,
                Text(
                  'Keep app open for live P2P transfer',
                  style: TextStyle(
                    color: Colors.orange.shade800,
                    fontWeight: FontWeight.w600,
                    fontSize: AppSizes.textSmall,
                  ),
                ),
              ],
            ),
          ),
          // Web-only warning: Chrome's pause breaks the P2P stream
          if (kIsWeb && widget.role == SessionRole.receiver) ...[
            AppSpacing.gapH12,
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: AppSizes.p16,
                vertical: AppSizes.p12,
              ),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.block, color: Colors.red, size: 20),
                  AppSpacing.gapW8,
                  Flexible(
                    child: Text(
                      'Do NOT pause from the browser\'s download bar — it will break the transfer. Use the Cancel button below instead.',
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.w600,
                        fontSize: AppSizes.textSmall,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Tip: WiFi vs Mobile data ─────────────────────────────────────
          AppSpacing.gapH12,
          Container(
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
          ),

          // ── Tip: Install the app (web only) ──────────────────────────────
          if (kIsWeb) ...[
            AppSpacing.gapH8,
            Container(
              padding: EdgeInsets.all(AppSizes.p16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.purple.withValues(alpha: 0.08),
                    Colors.deepPurple.withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
                border: Border.all(color: Colors.purple.withValues(alpha: 0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.rocket_launch_rounded,
                      color: Colors.purple,
                      size: 16,
                    ),
                  ),
                  AppSpacing.gapW8,
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '🚀 Even Better with the App',
                          style: TextStyle(
                            color: Colors.purple.shade700,
                            fontWeight: FontWeight.bold,
                            fontSize: AppSizes.textSmall,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Install the PeerTransfer app for a smoother, faster experience — background transfers, no browser limits, and instant sharing at your fingertips.',
                          style: TextStyle(
                            color: Colors.purple.shade600,
                            fontSize: AppSizes.textSmall,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          AppSpacing.gapH32,

          if (state.progress < 1.0)
            TextButton.icon(
              onPressed: () => _confirmAndCancelTransfer(context),
              icon: const Icon(Icons.cancel, color: Colors.red),
              label: const Text(
                'Cancel Transfer',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (state.progress >= 1.0 && widget.role == SessionRole.sender)
            Padding(
              padding: EdgeInsets.only(top: AppSizes.p32),
              child: Text(
                '✅ Sent Successfully!',
                style: TextStyle(
                  color: Colors.green,
                  fontSize: AppSizes.textSubtitle,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      );
    } else if (state is TransferSuccess) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle,
            size: AppSizes.iconHuge,
            color: Colors.green,
          ),
          AppSpacing.gapH24,
          Text(
            'Transfer Complete!',
            style: TextStyle(
              fontSize: AppSizes.textHeadline,
              fontWeight: FontWeight.bold,
            ),
          ),
          AppSpacing.gapH16,
          Text(
            state.filePath.startsWith('blob:')
                ? 'File received successfully. If the download did not start automatically, please click the button below.'
                : 'Saved at: \n${state.filePath}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),

          if (kIsWeb && state.filePath.startsWith('blob:')) ...[
            AppSpacing.gapH24,
            CustomButton(
              text: 'Save/Download File',
              icon: Icons.download_rounded,
              onPressed: () {
                context.read<TransferBloc>().add(
                  SaveFileManuallyEvent(state.filePath),
                );
              },
            ),
          ],
          AppSpacing.gapH16,
          CustomButton(
            text: 'Finish',
            icon: Icons.check_circle_outline,
            isPrimary: false,
            onPressed: () {
              final tBloc = context.read<TransferBloc>();
              final cBloc = context.read<ConnectionBloc>();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
                (route) => false,
              );
              Future.delayed(const Duration(milliseconds: 400), () {
                tBloc.add(ResetTransferEvent());
                cBloc.add(ResetConnectionEvent());
              });
            },
          ),
        ],
      );
    } else if (state is TransferFailure) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: AppSizes.iconHuge, color: Colors.red),
          AppSpacing.gapH24,
          Text(
            'Transfer Failed',
            style: TextStyle(
              fontSize: AppSizes.textHeadline,
              fontWeight: FontWeight.bold,
            ),
          ),
          AppSpacing.gapH16,
          Text(
            state.error,
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
          AppSpacing.gapH32,
          CustomButton(
            text: 'Retry Connection',
            onPressed: () {
              final tBloc = context.read<TransferBloc>();
              final cBloc = context.read<ConnectionBloc>();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
                (route) => false,
              );
              Future.delayed(const Duration(milliseconds: 400), () {
                tBloc.add(ResetTransferEvent());
                cBloc.add(ResetConnectionEvent());
              });
            },
          ),
        ],
      );
    } else if (state is TransferCancelledByPeer) {
      // Peer cancelled — show message. No notification button needed (notification already shown).
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cancel_outlined,
            size: AppSizes.iconHuge,
            color: Colors.orange,
          ),
          AppSpacing.gapH24,
          Text(
            'Transfer Cancelled',
            style: TextStyle(
              fontSize: AppSizes.textHeadline,
              fontWeight: FontWeight.bold,
            ),
          ),
          AppSpacing.gapH16,
          Text(
            state.message,
            style: const TextStyle(color: Colors.orange, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          AppSpacing.gapH32,
          CustomButton(
            text: 'Go Home',
            icon: Icons.home_outlined,
            isPrimary: false,
            onPressed: () {
              final tBloc = context.read<TransferBloc>();
              final cBloc = context.read<ConnectionBloc>();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
                (route) => false,
              );
              Future.delayed(const Duration(milliseconds: 400), () {
                tBloc.add(ResetTransferEvent());
                cBloc.add(ResetConnectionEvent());
              });
            },
          ),
        ],
      );
    }
    return const SizedBox();
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
                      Icons.import_export_rounded,
                      size: 150,
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.8),
                    ),
                    AppSpacing.gapH32,
                    const Text(
                      'Live Peer-to-Peer\nTransfer',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    AppSpacing.gapH16,
                    Text(
                      'Your files are traveling securely directly between your devices. Our signaling servers do not store or see your data.',
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

  /// Formats seconds into a human-readable ETA string.
  /// e.g. 65 → "~1 min 5 s left", 3600 → "~1 hr left"
  String _formatEta(int seconds) {
    if (seconds >= 3600) {
      final h = seconds ~/ 3600;
      final m = (seconds % 3600) ~/ 60;
      return m > 0 ? '~$h hr $m min left' : '~$h hr left';
    } else if (seconds >= 60) {
      final m = seconds ~/ 60;
      final s = seconds % 60;
      return s > 0 ? '~$m min $s s left' : '~$m min left';
    } else {
      return '~$seconds s left';
    }
  }
}

// ────────────────────────────────────────────────────────────────────────────
/// Animated banner shown when transfer progress hasn't changed for 10 seconds.
/// A gentle pulse animation tells the user the app is alive and waiting for
/// the TURN relay to deliver more data — so they don't think it crashed.
// ────────────────────────────────────────────────────────────────────────────
class _StallWarningBanner extends StatefulWidget {
  const _StallWarningBanner();

  @override
  State<_StallWarningBanner> createState() => _StallWarningBannerState();
}

class _StallWarningBannerState extends State<_StallWarningBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.deepOrange.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.deepOrange.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.deepOrange,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Relay is slow — transfer is still active, please wait…',
                style: TextStyle(
                  color: Colors.deepOrange.shade700,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

