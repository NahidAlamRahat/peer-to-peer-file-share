import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'core/di/injection_container.dart' as di;
import 'core/theme/app_theme.dart';
import 'presentation/blocs/connection/connection_bloc.dart';
import 'presentation/blocs/transfer/transfer_bloc.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/widgets/responsive_layout.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await di.init();
  runApp(const P2PFileShareApp());
}

class P2PFileShareApp extends StatelessWidget {
  const P2PFileShareApp({super.key});

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
        title: 'P2P File Share',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        // Wrap the root screen with ResponsiveLayout
        home: const ResponsiveLayout(child: HomeScreen()),
      ),
    );
  }
}
