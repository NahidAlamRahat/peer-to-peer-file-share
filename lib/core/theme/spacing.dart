import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class AppSpacing {
  // Vertical spacing
  static Widget gapH(double height) => SizedBox(height: height.h);

  // Horizontal spacing
  static Widget gapW(double width) => SizedBox(width: width.w);

  // Common specific vertical gaps
  static Widget get gapH4 => SizedBox(height: 4.h);
  static Widget get gapH8 => SizedBox(height: 8.h);
  static Widget get gapH12 => SizedBox(height: 12.h);
  static Widget get gapH16 => SizedBox(height: 16.h);
  static Widget get gapH24 => SizedBox(height: 24.h);
  static Widget get gapH32 => SizedBox(height: 32.h);
  static Widget get gapH48 => SizedBox(height: 48.h);
  static Widget get gapH64 => SizedBox(height: 64.h);

  // Common specific horizontal gaps
  static Widget get gapW4 => SizedBox(width: 4.w);
  static Widget get gapW8 => SizedBox(width: 8.w);
  static Widget get gapW12 => SizedBox(width: 12.w);
  static Widget get gapW16 => SizedBox(width: 16.w);
  static Widget get gapW24 => SizedBox(width: 24.w);
  static Widget get gapW32 => SizedBox(width: 32.w);
}
