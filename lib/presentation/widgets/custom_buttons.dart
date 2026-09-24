import 'package:flutter/material.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/spacing.dart';

class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool isPrimary;
  final double? height;
  final double? fontSize;
  final double? iconSize;

  const CustomButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.icon,
    this.isPrimary = true,
    this.height,
    this.fontSize,
    this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveHeight = height ?? 56.0;
    final effectiveFontSize = fontSize ?? AppSizes.textSubtitle;
    final effectiveIconSize = iconSize ?? AppSizes.iconMedium;

    if (isPrimary) {
      return ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          minimumSize: Size(double.infinity, effectiveHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
          ),
          elevation: 2,
        ),
        child: _buildContent(effectiveFontSize, effectiveIconSize),
      );
    } else {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.primary,
          minimumSize: Size(double.infinity, effectiveHeight),
          side: BorderSide(color: Theme.of(context).colorScheme.primary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
          ),
        ),
        child: _buildContent(effectiveFontSize, effectiveIconSize),
      );
    }
  }

  Widget _buildContent(double fontSize, double iconSize) {
    if (icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: iconSize),
          AppSpacing.gapW12,
          Text(text, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold)),
        ],
      );
    }
    return Text(text, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold));
  }
}
