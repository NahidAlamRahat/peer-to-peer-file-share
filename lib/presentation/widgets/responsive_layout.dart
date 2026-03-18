import 'package:flutter/material.dart';

/// A wrapper widget that switches between a mobile view and a desktop split-screen view.
class ResponsiveLayout extends StatelessWidget {
  final Widget mobileBody;
  final Widget desktopBody;

  const ResponsiveLayout({
    super.key,
    required this.mobileBody,
    required this.desktopBody,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 800) {
          // Mobile / Tablet view
          return mobileBody;
        } else {
          // Desktop Wide view
          return desktopBody;
        }
      },
    );
  }
}
