import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'core/di/injection_container.dart' as di;
import 'core/theme/app_theme.dart';
import 'presentation/blocs/connection/connection_bloc.dart';
import 'presentation/blocs/transfer/transfer_bloc.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/receive_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await di.init();

  // ── Read initial session ID from deep link / share link ──────────────────
  String? initialSessionId;

  if (kIsWeb) {
    // Web: read ?session= from the URL directly
    try {
      initialSessionId = Uri.base.queryParameters['session'];
    } catch (_) {}
  } else {
    // Android / desktop: read the initial deep link via app_links
    try {
      final appLinks = AppLinks();
      final initialUri = await appLinks.getInitialLink();
      if (initialUri != null) {
        initialSessionId = initialUri.queryParameters['session'];
      }
    } catch (_) {}
  }

  runApp(P2PFileShareApp(initialSessionId: initialSessionId));
}

class P2PFileShareApp extends StatelessWidget {
  /// Session ID extracted from the launch URL/deep link (may be null).
  final String? initialSessionId;

  const P2PFileShareApp({super.key, this.initialSessionId});

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
        title: 'PeerTransfer Link',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        // If opened via a share link, go straight to ReceiveScreen & auto-join
        home: (initialSessionId != null && initialSessionId!.isNotEmpty)
            ? ReceiveScreen(autoJoinSessionId: initialSessionId)
            : const HomeScreen(),
      ),
    );
  }
}
