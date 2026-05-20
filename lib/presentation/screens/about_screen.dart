import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/spacing.dart';
import 'privacy_policy_screen.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const String _whatsappNumber = '8801642743187'; // BD country code
  static const String _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.nahidrahat.p2pfileshare';
  static const String _developerName = 'Nahid Alam Rahat';
  static const String _appName = 'PeerTransfer';
  static const String _appVersion = '1.0.0';
  static const String _appTagline =
      'Secure, fast, peer-to-peer file sharing — no limits, no middleman.';

  Future<void> _launchWhatsApp(BuildContext context) async {
    final message = Uri.encodeComponent(
      'Hello! I need support for the PeerTransfer app.',
    );
    final uri = Uri.parse('https://wa.me/$_whatsappNumber?text=$message');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open WhatsApp.')),
        );
      }
    }
  }

  Future<void> _launchPlayStore(BuildContext context) async {
    final uri = Uri.parse(_playStoreUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Play Store.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
        elevation: 0,
      ),
      body: ListView(
        padding: EdgeInsets.symmetric(
          horizontal: AppSizes.p24,
          vertical: AppSizes.p32,
        ),
        children: [
          // ── App Hero Card ──────────────────────────────────────────────
          _buildAppHeroCard(context, colorScheme),
          AppSpacing.gapH32,

          // ── Developer Section ──────────────────────────────────────────
          _sectionHeader(context, '👨‍💻 Developer'),
          AppSpacing.gapH12,
          _InfoCard(
            icon: Icons.person_outline_rounded,
            title: _developerName,
            subtitle: 'App Developer & Designer',
            iconColor: colorScheme.primary,
          ),
          AppSpacing.gapH32,

          // ── Contact / Support Section ──────────────────────────────────
          _sectionHeader(context, '💬 Support & Contact'),
          AppSpacing.gapH12,
          _buildWhatsAppButton(context, colorScheme),
          AppSpacing.gapH8,
          Text(
            'Tap above to open WhatsApp and message me directly for help.',
            style: TextStyle(
              fontSize: AppSizes.textSmall,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
          AppSpacing.gapH32,

          // ── Play Store Section ─────────────────────────────────────────
          _sectionHeader(context, '📦 Download'),
          AppSpacing.gapH12,
          _buildPlayStoreButton(context, colorScheme),
          AppSpacing.gapH8,
          Text(
            'Get the latest version on Google Play Store.',
            style: TextStyle(
              fontSize: AppSizes.textSmall,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
          AppSpacing.gapH32,

          // ── Legal Section ──────────────────────────────────────────────
          _sectionHeader(context, '⚖️ Legal'),
          AppSpacing.gapH12,
          _buildLegalTile(
            context,
            icon: Icons.privacy_tip_outlined,
            label: 'Privacy Policy',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
            ),
          ),
          AppSpacing.gapH32,

          // ── App Info Footer ────────────────────────────────────────────
          Center(
            child: Column(
              children: [
                Text(
                  '$_appName v$_appVersion',
                  style: TextStyle(
                    fontSize: AppSizes.textSmall,
                    color: Colors.grey.shade500,
                  ),
                ),
                AppSpacing.gapH4,
                Text(
                  '© 2026 $_developerName. All rights reserved.',
                  style: TextStyle(
                    fontSize: AppSizes.textSmall,
                    color: Colors.grey.shade500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          AppSpacing.gapH24,
        ],
      ),
    );
  }

  Widget _buildAppHeroCard(BuildContext context, ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppSizes.p32),
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
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.asset(
                'assets/logo.png',
                width: 96,
                height: 96,
                fit: BoxFit.cover,
              ),
            ),
          ),
          AppSpacing.gapH16,
          Text(
            _appName,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          AppSpacing.gapH8,
          Text(
            _appTagline,
            style: TextStyle(
              fontSize: AppSizes.textBody,
              color: colorScheme.onPrimaryContainer.withValues(alpha: 0.75),
            ),
            textAlign: TextAlign.center,
          ),
          AppSpacing.gapH16,
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Version $_appVersion',
              style: TextStyle(
                fontSize: AppSizes.textSmall,
                fontWeight: FontWeight.w600,
                color: colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWhatsAppButton(BuildContext context, ColorScheme colorScheme) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _launchWhatsApp(context),
        borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
        child: Container(
          padding: EdgeInsets.all(AppSizes.p16),
          decoration: BoxDecoration(
            color: const Color(0xFF25D366).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
            border: Border.all(
              color: const Color(0xFF25D366).withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: Color(0xFF25D366),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.chat_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              AppSpacing.gapW16,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Chat on WhatsApp',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '+880 1642-743187',
                      style: TextStyle(
                        fontSize: AppSizes.textSmall,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.open_in_new_rounded, color: Color(0xFF25D366)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayStoreButton(BuildContext context, ColorScheme colorScheme) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _launchPlayStore(context),
        borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
        child: Container(
          padding: EdgeInsets.all(AppSizes.p16),
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.android_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              AppSpacing.gapW16,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Google Play Store',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'Rate & review the app',
                      style: TextStyle(
                        fontSize: AppSizes.textSmall,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.open_in_new_rounded, color: colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegalTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
        child: Container(
          padding: EdgeInsets.all(AppSizes.p16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              AppSpacing.gapW16,
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: AppSizes.textSubtitle,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconColor;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.all(AppSizes.p16),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          AppSpacing.gapW16,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: AppSizes.textSmall,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
