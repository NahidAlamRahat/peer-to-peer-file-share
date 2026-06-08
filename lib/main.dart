import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'core/utils/web_helpers/web_helpers.dart' as web_helpers;

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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── DI only — fast (SharedPreferences + service registration) ─────────────
  await di.init();

  // ── Parse deep-link before showing UI ──────────────────────────────────────
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
  }
  // Mobile deep link parsing is moved to initState to avoid blocking main()

  // ── Launch UI immediately ─────────────────────────────────────────────────
  runApp(P2PFileShareApp(
    initialSessionId: initialSessionId,
    initialFileName:  initialFileName,
    initialFileSize:  initialFileSize,
    initialFileCount: initialFileCount,
  ));

  // ── Firebase + MobileAds in background (non-blocking) ────────────────────
  _initHeavyServices();
}

Future<void> _initHeavyServices() async {
  try {
    await Future.wait([
      Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
      initializeMobileAds(),
    ]);
    AdService.instance.init(); // Remote Config — fire-and-forget
    if (!kIsWeb) {
      InterstitialAdService.instance.preload();
    }
  } catch (_) {}
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
    _checkIncognito();
    
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

  void _checkIncognito() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (kIsWeb) {
        web_helpers.checkIncognitoStatus((bool isIncognito) {
          if (isIncognito) {
            showDialog(
              context: navigatorKey.currentContext!,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                title: const Text('Incognito Mode Not Supported'),
                content: const Text(
                  'Files cannot be downloaded securely in Incognito mode.\n\n'
                  'Please open this app in a normal tab to download files.',
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: web_helpers.getWebUrl()));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Link copied! Open a normal tab and paste it.')),
                      );
                    },
                    child: const Text('Copy Link'),
                  ),
                ],
              ),
            );
          }
        });
      }
    });
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
        home: (widget.initialSessionId != null && widget.initialSessionId!.isNotEmpty)
            ? ReceiveScreen(
                autoJoinSessionId: widget.initialSessionId,
                preloadedFileName:  widget.initialFileName,
                preloadedFileSize:  widget.initialFileSize,
                preloadedFileCount: widget.initialFileCount,
              )
            : const HomeScreen(),
      ),
    );
  }
}
