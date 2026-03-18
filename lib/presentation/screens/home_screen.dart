import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/di/injection_container.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/spacing.dart';
import '../blocs/connection/connection_bloc.dart';
import '../blocs/connection/connection_event.dart';
import '../blocs/connection/connection_state.dart';
import '../widgets/custom_buttons.dart';
import '../widgets/responsive_layout.dart';
import 'settings_screen.dart';
import 'share_link_screen.dart';
import 'receive_screen.dart';

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
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSizes.p24, vertical: AppSizes.p32),
      child: Column(
        children: [
          _buildServerStatus(),
          const Spacer(),
          _buildHeroSection(context, isDesktop: false),
          const Spacer(flex: 2),
          _buildActionPanel(context),
          AppSpacing.gapH32,
        ],
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
                   ],
                 ),
               ),
            ),
          ),
        ),
      ],
    );
  }
}
