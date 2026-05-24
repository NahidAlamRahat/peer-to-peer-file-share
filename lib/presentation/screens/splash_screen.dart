import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'receive_screen.dart';

class SplashScreen extends StatefulWidget {
  final String? initialSessionId;
  final String? initialFileName;
  final int? initialFileSize;
  final int? initialFileCount;

  const SplashScreen({
    super.key,
    this.initialSessionId,
    this.initialFileName,
    this.initialFileSize,
    this.initialFileCount,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeIn),
    );

    _scaleAnim = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );

    _animController.forward();

    // Navigate after 2 seconds
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (!mounted) return;
      Widget nextScreen;
      if (widget.initialSessionId != null &&
          widget.initialSessionId!.isNotEmpty) {
        nextScreen = ReceiveScreen(
          autoJoinSessionId: widget.initialSessionId,
          preloadedFileName: widget.initialFileName,
          preloadedFileSize: widget.initialFileSize,
          preloadedFileCount: widget.initialFileCount,
        );
      } else {
        nextScreen = const HomeScreen();
      }

      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => nextScreen,
          transitionDuration: const Duration(milliseconds: 500),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF09090b) : const Color(0xFFFFFFFF);
    final iconColor = isDark ? const Color(0xFF818cf8) : const Color(0xFF6366f1);

    return Scaffold(
      backgroundColor: bgColor,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: ScaleTransition(
            scale: _scaleAnim,
            child: Icon(
              Icons.cloud_upload_outlined,
              size: 100,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }
}
