import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/spacing.dart';

class SettingsScreen extends StatefulWidget {
  final SettingsService settingsService;
  const SettingsScreen({super.key, required this.settingsService});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _keepScreenOn;
  late bool _runInBackground;

  @override
  void initState() {
    super.initState();
    _keepScreenOn = widget.settingsService.keepScreenOn;
    _runInBackground = widget.settingsService.runInBackground;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfer Settings'),
        elevation: 0,
      ),
      body: ListView(
        padding: EdgeInsets.all(AppSizes.p24),
        children: [
          Text(
            'During File Transfer',
            style: TextStyle(
              fontSize: AppSizes.textSubtitle,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          AppSpacing.gapH16,
          _SettingsTile(
            icon: Icons.light_mode,
            title: 'Keep Screen Awake',
            subtitle: 'Prevents the screen from auto-locking during a transfer.',
            value: _keepScreenOn,
            onChanged: (val) async {
              await widget.settingsService.setKeepScreenOn(val);
              setState(() => _keepScreenOn = val);
            },
          ),
          if (!kIsWeb) ...[
            AppSpacing.gapH8,
            _SettingsTile(
              icon: Icons.play_circle_outline,
              title: 'Run in Background',
              subtitle: 'Continues the transfer even if you leave the app. A notification will appear while active.',
              value: _runInBackground,
              onChanged: (val) async {
                await widget.settingsService.setRunInBackground(val);
                setState(() => _runInBackground = val);
              },
            ),
          ],
          AppSpacing.gapH32,
          Container(
            padding: EdgeInsets.all(AppSizes.p16),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 20, color: Colors.orange),
                AppSpacing.gapW12,
                Expanded(
                  child: Text(
                    kIsWeb
                        ? 'You are on the Web version. Keep the browser tab open for best results. Install the app for full background support.'
                        : 'Recommended: Enable both toggles for large files to prevent interruptions.',
                    style: TextStyle(fontSize: AppSizes.textSmall, color: Colors.orange.shade800),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: SwitchListTile(
        secondary: Icon(icon, color: theme.colorScheme.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: AppSizes.textSmall, color: Colors.grey)),
        value: value,
        onChanged: onChanged,
        contentPadding: EdgeInsets.symmetric(horizontal: AppSizes.p20, vertical: AppSizes.p8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.radiusLarge)),
      ),
    );
  }
}
