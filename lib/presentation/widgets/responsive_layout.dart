import 'package:flutter/material.dart';

/// A wrapper widget that constraints the maximum width of the application
/// making it look great on both mobile and ultra-wide desktop monitors.
class ResponsiveLayout extends StatelessWidget {
  final Widget child;
  const ResponsiveLayout({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 600, // Look like a mobile/tablet app centered on desktop
          ),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: const [],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
