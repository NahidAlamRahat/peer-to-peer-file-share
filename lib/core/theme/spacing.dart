import 'package:flutter/material.dart';

class AppSpacing {
  // Vertical spacing
  static Widget gapH(double height) => SizedBox(height: height);

  // Horizontal spacing
  static Widget gapW(double width) => SizedBox(width: width);

  // Common specific vertical gaps
  static Widget get gapH4 => const SizedBox(height: 4);
  static Widget get gapH8 => const SizedBox(height: 8);
  static Widget get gapH12 => const SizedBox(height: 12);
  static Widget get gapH16 => const SizedBox(height: 16);
  static Widget get gapH24 => const SizedBox(height: 24);
  static Widget get gapH32 => const SizedBox(height: 32);
  static Widget get gapH48 => const SizedBox(height: 48);
  static Widget get gapH64 => const SizedBox(height: 64);

  // Common specific horizontal gaps
  static Widget get gapW4 => const SizedBox(width: 4);
  static Widget get gapW8 => const SizedBox(width: 8);
  static Widget get gapW12 => const SizedBox(width: 12);
  static Widget get gapW16 => const SizedBox(width: 16);
  static Widget get gapW24 => const SizedBox(width: 24);
  static Widget get gapW32 => const SizedBox(width: 32);
}
