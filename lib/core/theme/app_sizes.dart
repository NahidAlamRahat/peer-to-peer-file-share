import 'package:flutter_screenutil/flutter_screenutil.dart';

class AppSizes {
  // Padding & Margins
  static double get p4 => 4.w;
  static double get p8 => 8.w;
  static double get p12 => 12.w;
  static double get p16 => 16.w;
  static double get p20 => 20.w;
  static double get p24 => 24.w;
  static double get p32 => 32.w;
  static double get p48 => 48.w;

  // Border Radius
  static double get radiusSmall => 8.r;
  static double get radiusMedium => 12.r;
  static double get radiusLarge => 16.r;
  static double get radiusCircular => 500.r;

  // Font Sizes
  static double get textSmall => 12.sp;
  static double get textBody => 16.sp;
  static double get textSubtitle => 18.sp;
  static double get textTitle => 20.sp;
  static double get textHeadline => 24.sp;
  static double get textDisplay => 32.sp;

  // Icon Sizes
  static double get iconSmall => 16.sp;
  static double get iconMedium => 24.sp;
  static double get iconLarge => 32.sp;
  static double get iconHuge => 80.sp;
  static double get iconQr => 200.w;
}
