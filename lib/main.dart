import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/di/injection_container.dart' as di;
import 'core/services/ad_service.dart';
import 'core/services/interstitial_ad_service.dart';
import 'core/services/mobile_ads_init.dart'; // conditional: no-op on web
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'presentation/blocs/connection/connection_bloc.dart';
import 'presentation/blocs/transfer/transfer_bloc.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/receive_screen.dart';
import 'presentation/screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Firebase (runs on ALL platforms: web + mobile) ────────────────────────
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ── MobileAds SDK (no-op on web via conditional import) ───────────────────
  await initializeMobileAds();

  // ── AdService: fetch Remote Config ads_enabled ────────────────────────────
  await AdService.instance.init();

  // ── Preload interstitial on mobile only ───────────────────────────────────
  if (!kIsWeb) {
    InterstitialAdService.instance.preload();
  }

  await di.init();

  String? initialSessionId;
  String? initialFileName;
  int?    initialFileSize;
  int?    initialFileCount;

  if (kIsWeb) {
    try {
      final uri = Uri.base;
      initialSessionId = uri.queryParameters['session'];
      initialFileName  = uri.queryParameters['name'] != null
          ? Uri.decodeComponent(uri.queryParameters['name']!)
          : null;
      initialFileSize  = int.tryParse(uri.queryParameters['size'] ?? '');
      initialFileCount = int.tryParse(uri.queryParameters['count'] ?? '');
    } catch (_) {}
  } else {
    try {
      final appLinks = AppLinks();
      final initialUri = await appLinks.getInitialLink();
      if (initialUri != null) {
        initialSessionId = initialUri.queryParameters['session'];
        initialFileName  = initialUri.queryParameters['name'] != null
            ? Uri.decodeComponent(initialUri.queryParameters['name']!)
            : null;
        initialFileSize  = int.tryParse(initialUri.queryParameters['size'] ?? '');
        initialFileCount = int.tryParse(initialUri.queryParameters['count'] ?? '');
      }
    } catch (_) {}
  }

  runApp(P2PFileShareApp(
    initialSessionId: initialSessionId,
    initialFileName:  initialFileName,
    initialFileSize:  initialFileSize,
    initialFileCount: initialFileCount,
  ));
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class P2PFileShareApp extends StatefulWidget {
  final String? initialSessionId;
  final String? initialFileName;
  final int?    initialFileSize;
  final int?    initialFileCount;

  const P2PFileShareApp({
    super.key,
    this.initialSessionId,
    this.initialFileName,
    this.initialFileSize,
    this.initialFileCount,
  });

  @override
  State<P2PFileShareApp> createState() => _P2PFileShareAppState();
}

class _P2PFileShareAppState extends State<P2PFileShareApp> {
  late final AppLinks _appLinks;
  
  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _appLinks = AppLinks();
      _appLinks.uriLinkStream.listen((uri) {
        final sessionId = uri.queryParameters['session'];
        if (sessionId != null && sessionId.isNotEmpty) {
          final fileName = uri.queryParameters['name'] != null ? Uri.decodeComponent(uri.queryParameters['name']!) : null;
          final fileSize = int.tryParse(uri.queryParameters['size'] ?? '');
          final fileCount = int.tryParse(uri.queryParameters['count'] ?? '');

          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) => ReceiveScreen(
                autoJoinSessionId: sessionId,
                preloadedFileName: fileName,
                preloadedFileSize: fileSize,
                preloadedFileCount: fileCount,
              ),
            ),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<ConnectionBloc>(
          lazy: false,
          create: (_) => di.sl<ConnectionBloc>(),
        ),
        BlocProvider(
          create: (_) => di.sl<TransferBloc>(),
        ),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'PeerTransfer',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: SplashScreen(
          initialSessionId:  widget.initialSessionId,
          initialFileName:   widget.initialFileName,
          initialFileSize:   widget.initialFileSize,
          initialFileCount:  widget.initialFileCount,
        ),
      ),
    );
  }
}
