import 'package:flutter/material.dart';

/// A wrapper widget that constraints the maximum width of the application
/// making it look great on both mobile and ultra-wide desktop monitors.
class ResponsiveLayout extends StatelessWidget {
  final Widget child;
  const ResponsiveLayout({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 600, // Look like a mobile/tablet app centered on desktop
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            boxShadow: [
               if (MediaQuery.of(context).size.width > 600)
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 30,
                    spreadRadius: 5,
                  )
            ]
          ),
          child: child,
        ),
      ),
    );
  }
}
