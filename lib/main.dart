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

class P2PFileShareApp extends StatelessWidget {
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
        home: (initialSessionId != null && initialSessionId!.isNotEmpty)
            ? ReceiveScreen(
                autoJoinSessionId:  initialSessionId,
                preloadedFileName:  initialFileName,
                preloadedFileSize:  initialFileSize,
                preloadedFileCount: initialFileCount,
              )
            : const HomeScreen(),
      ),
    );
  }
}
