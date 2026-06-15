import 'package:flutter/material.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/spacing.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const String _developerName = 'Nahid Alam Rahat';
  static const String _appName = 'PeerTransfer';
  static const String _contactEmail = 'nahidrahat007@gmail.com';
  static const String _contactNumber = '+880 1642-743187';
  static const String _lastUpdated = 'June 16, 2026';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        elevation: 0,
      ),
      body: ListView(
        padding: EdgeInsets.symmetric(
          horizontal: AppSizes.p24,
          vertical: AppSizes.p24,
        ),
        children: [
          // Header Card
          Container(
            padding: EdgeInsets.all(AppSizes.p24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colorScheme.primaryContainer,
                  colorScheme.secondaryContainer,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.privacy_tip_outlined,
                      color: colorScheme.primary,
                      size: 32,
                    ),
                    AppSpacing.gapW12,
                    Expanded(
                      child: Text(
                        'Privacy Policy',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                AppSpacing.gapH12,
                Text(
                  'Last updated: $_lastUpdated',
                  style: TextStyle(
                    fontSize: AppSizes.textSmall,
                    color: colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          AppSpacing.gapH24,

          // Introduction
          _PolicySection(
            icon: Icons.info_outline_rounded,
            title: '1. Introduction',
            content:
                'Welcome to $_appName, developed by $_developerName. This Privacy Policy explains how we handle your information when you use our application. We are committed to protecting your privacy and being transparent about our data practices.\n\n'
                '$_appName is a peer-to-peer file sharing application that allows you to send and receive files directly between devices over WebRTC — without uploading your files to any central server.',
          ),

          _PolicySection(
            icon: Icons.folder_open_outlined,
            title: '2. What Data We Collect & Access',
            content:
                '• **Camera:** We use the camera solely for scanning QR codes locally to connect devices. No images are saved or transmitted to any server.\n\n'
                '• **Storage and Media:** We require read/write access to your device storage (including granular media permissions on Android 13+) to let you select and save files.\n\n'
                '• **All Files Access:** On Android 11+, we require "All Files Access" to let you browse and transfer files of any format across your entire storage. This is necessary for the core functionality of a file-sharing app.\n\n'
                '• **No file uploading:** Files are transferred directly between devices via WebRTC. We do not store or access your files on our servers.\n\n'
                '• **Signaling server:** A minimal signaling server is used only to help establish the WebRTC connection between peers. It does not receive or store your actual file data.',
          ),

          _PolicySection(
            icon: Icons.ad_units_outlined,
            title: '3. Third-Party Services (Ads)',
            content:
                'Our app uses third-party services, primarily **Google AdMob**, to serve advertisements.\n\n'
                'AdMob may collect and use data such as your device\'s Advertising ID, IP address, and interaction data to serve personalized or non-personalized ads. We do not control the data collected by Google AdMob.\n\n'
                'For more information, please review the Google Privacy Policy online.',
          ),

          _PolicySection(
            icon: Icons.share_outlined,
            title: '4. How We Use Data',
            content:
                'Data is used solely to provide the file-sharing functionality:\n\n'
                '• Establish a secure peer-to-peer WebRTC connection between sender and receiver.\n'
                '• Transfer files directly between the two devices you choose.\n'
                '• Show transfer progress notifications on your device.\n\n'
                'We do not sell, trade, rent, or otherwise share your data with third parties.',
          ),

          _PolicySection(
            icon: Icons.lock_outline_rounded,
            title: '5. Security',
            content:
                '$_appName uses WebRTC, which encrypts all data-channel traffic using DTLS-SRTP by default. Your files are encrypted in transit. No file content is stored on any server. The signaling server only handles short-lived session negotiation messages and does not retain logs of connections.',
          ),

          _PolicySection(
            icon: Icons.storage_outlined,
            title: '6. Local Storage',
            content:
                'The app stores minimal data locally on your device:\n\n'
                '• **App settings** (e.g., Keep Screen Awake, Run in Background) — saved in device preferences.\n'
                '• **Received files** — saved to a location you select on your device storage.\n\n'
                'No data is backed up to external servers by this app.',
          ),

          _PolicySection(
            icon: Icons.child_care_outlined,
            title: "7. Children's Privacy",
            content:
                '$_appName is not directed at children under the age of 13. We do not knowingly collect any personal information from children. If you believe a child has provided personal information through our app, please contact us so we can take appropriate action.',
          ),

          _PolicySection(
            icon: Icons.update_outlined,
            title: '8. Changes to This Policy',
            content:
                'We may update this Privacy Policy from time to time. Any changes will be reflected in the "Last updated" date at the top of this page. We encourage you to review this policy periodically. Continued use of the app after changes constitutes acceptance of the updated policy.',
          ),

          _PolicySection(
            icon: Icons.contact_support_outlined,
            title: '9. Contact Us',
            content:
                'If you have any questions, concerns, or requests regarding this Privacy Policy or your data, please contact us:\n\n'
                '👤 Developer: $_developerName\n'
                '📧 Email: $_contactEmail\n'
                '📱 WhatsApp: $_contactNumber\n\n'
                'We aim to respond within 48 hours.',
          ),

          AppSpacing.gapH24,

          // Footer
          Center(
            child: Text(
              '© 2026 $_developerName · $_appName',
              style: TextStyle(
                fontSize: AppSizes.textSmall,
                color: Colors.grey.shade500,
              ),
            ),
          ),
          AppSpacing.gapH24,
        ],
      ),
    );
  }
}

class _PolicySection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String content;

  const _PolicySection({
    required this.icon,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Container(
        padding: EdgeInsets.all(AppSizes.p20),
        decoration: BoxDecoration(
          color:
              colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
                  ),
                  child: Icon(icon, color: colorScheme.primary, size: 18),
                ),
                AppSpacing.gapW12,
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: AppSizes.textSubtitle,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            AppSpacing.gapH12,
            _buildRichContent(context, content),
          ],
        ),
      ),
    );
  }

  Widget _buildRichContent(BuildContext context, String text) {
    // Parse **bold** markers for simple inline bold rendering
    final parts = <TextSpan>[];
    final regex = RegExp(r'\*\*(.*?)\*\*');
    int lastEnd = 0;
    for (final match in regex.allMatches(text)) {
      if (match.start > lastEnd) {
        parts.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      parts.add(TextSpan(
        text: match.group(1),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ));
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      parts.add(TextSpan(text: text.substring(lastEnd)));
    }

    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: AppSizes.textBody,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          height: 1.6,
        ),
        children: parts,
      ),
    );
  }
}
