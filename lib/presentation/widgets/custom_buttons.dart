import 'package:flutter/material.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/spacing.dart';

class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool isPrimary;

  const CustomButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.icon,
    this.isPrimary = true,
  });

  @override
  Widget build(BuildContext context) {
    if (isPrimary) {
      return ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
          ),
          elevation: 2,
        ),
        child: _buildContent(),
      );
    } else {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.primary,
          minimumSize: const Size(double.infinity, 56),
          side: BorderSide(color: Theme.of(context).colorScheme.primary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
          ),
        ),
        child: _buildContent(),
      );
    }
  }

  Widget _buildContent() {
    if (icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: AppSizes.iconMedium),
          AppSpacing.gapW12,
          Text(text, style: TextStyle(fontSize: AppSizes.textSubtitle, fontWeight: FontWeight.bold)),
        ],
      );
    }
    return Text(text, style: TextStyle(fontSize: AppSizes.textSubtitle, fontWeight: FontWeight.bold));
  }
}
