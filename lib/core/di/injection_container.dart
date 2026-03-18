import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/settings_service.dart';
import '../../data/datasources/signaling_service.dart';
import '../../data/datasources/webrtc_client.dart';
import '../../data/repositories/file_transfer_repository_impl.dart';
import '../../data/repositories/peer_repository_impl.dart';
import '../../domain/repositories/file_transfer_repository.dart';
import '../../domain/repositories/peer_repository.dart';
import '../../presentation/blocs/connection/connection_bloc.dart';
import '../../presentation/blocs/transfer/transfer_bloc.dart';

final sl = GetIt.instance; // sl = service locator

Future<void> init() async {
  // ── 0. External services ────────────────────────────────────────────────────
  final prefs = await SharedPreferences.getInstance();
  sl.registerSingleton<SettingsService>(SettingsService(prefs));

  // ── 1. Data sources (no dependencies) ──────────────────────────────────────
  sl.registerLazySingleton(() => SignalingService());
  sl.registerLazySingleton(() => WebRTCClient());

  // ── 2. Repositories (depend on data sources) ────────────────────────────────
  sl.registerLazySingleton<PeerRepository>(
    () => PeerRepositoryImpl(sl(), sl()),
  );
  sl.registerLazySingleton<FileTransferRepository>(
    () => FileTransferRepositoryImpl(sl()),
  );

  // ── 3. BLoCs (depend on repositories) ──────────────────────────────────────
  // ConnectionBloc is a singleton — instantiated immediately here so the
  // WebSocket connects as soon as the app starts.
  sl.registerSingleton<ConnectionBloc>(
    ConnectionBloc(peerRepository: sl()),
  );
  sl.registerFactory(() => TransferBloc(fileTransferRepository: sl()));
}


