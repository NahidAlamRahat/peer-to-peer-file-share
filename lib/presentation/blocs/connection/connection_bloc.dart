import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../domain/entities/peer_session.dart';
import '../../../../domain/repositories/peer_repository.dart';
import '../../../../data/repositories/peer_repository_impl.dart';
import 'connection_event.dart';
import 'connection_state.dart';

class ConnectionBloc extends Bloc<ConnectionEvent, ConnectionStateBloc> {
  final PeerRepository peerRepository;
  StreamSubscription? _sessionStateSubscription;
  StreamSubscription? _messageSubscription;
  StreamSubscription? _serverErrorSubscription;
  StreamSubscription? _statusSubscription;

  SessionRole? currentRole;

  ConnectionBloc({required this.peerRepository}) : super(ConnectionInitial()) {
    on<CreateSessionEvent>(_onCreateSession);
    on<JoinSessionEvent>(_onJoinSession);
    on<SessionStateChangedEvent>(_onSessionStateChanged);
    on<ResetConnectionEvent>(_onResetConnection);
    on<SendMessageEvent>(_onSendMessage);
    on<MessageReceivedEvent>(_onMessageReceived);
    on<ServerErrorEvent>(_onServerError);
    on<StatusUpdateEvent>(_onStatusUpdate);

    // Provide the initialize call to get things ready
    peerRepository.initialize();

    _sessionStateSubscription = peerRepository.sessionStateStream.listen((state) {
      add(SessionStateChangedEvent(state));
    });

    if (peerRepository is PeerRepositoryImpl) {
      final repo = peerRepository as PeerRepositoryImpl;
      _messageSubscription = repo.messageStream.listen((payload) {
        add(MessageReceivedEvent(payload));
      });
      _serverErrorSubscription = repo.serverErrorStream.listen(
        (error) => add(ServerErrorEvent(error)),
      );
      _statusSubscription = repo.statusMessageStream.listen(
        (message) => add(StatusUpdateEvent(message)),
      );
    }
  }

  @override
  void onChange(Change<ConnectionStateBloc> change) {
    super.onChange(change);
    debugPrint('🔄 [BLOC] State transition: ${change.currentState.runtimeType} -> ${change.nextState.runtimeType}');
  }

  Future<void> _onCreateSession(
    CreateSessionEvent event,
    Emitter<ConnectionStateBloc> emit,
  ) async {
    debugPrint('📊 [BLOC] Starting session creation flow...');
    emit(const ConnectionProgress(0.1, 'Connecting to signaling server...'));

    // Fake progress timer to make it feel fast (psychological speed boost)
    double progress = 0.1;
    final progressTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) {
      if (state is ConnectionProgress && progress < 0.95) {
        progress += (0.95 - progress) * 0.2; // Asymptotic approach to 95%
        final percent = (progress * 100).toInt();
        debugPrint('📊 [BLOC] Progress: $percent% - Securing connection...');
        add(StatusUpdateEvent('Securing connection... $percent%'));
      } else {
        timer.cancel();
      }
    });

    try {
      currentRole = SessionRole.sender;
      final sessionId = await peerRepository.createSession();
      progressTimer.cancel();
      debugPrint('✅ [BLOC] Session created! ID: $sessionId');
      emit(ConnectionCreated(sessionId));
    } catch (e) {
      debugPrint('❌ [BLOC] Session creation failed: $e');
      progressTimer.cancel();
      emit(ConnectionFailed(e.toString()));
    }
  }

  Future<void> _onJoinSession(
    JoinSessionEvent event,
    Emitter<ConnectionStateBloc> emit,
  ) async {
    emit(ConnectionLoading());
    try {
      currentRole = SessionRole.receiver;
      await peerRepository.joinSession(event.sessionId);
    } catch (e) {
      emit(ConnectionFailed(e.toString()));
    }
  }

  void _onSessionStateChanged(
    SessionStateChangedEvent event,
    Emitter<ConnectionStateBloc> emit,
  ) {
    if (event.state == SessionState.connected) {
      emit(ConnectionConnected(currentRole!));
    } else if (event.state == SessionState.failed) {
      emit(const ConnectionFailed('Connection failed or disconnected'));
    } else if (event.state == SessionState.offline) {
      emit(ConnectionOffline());
    }
    // we ignore 'connecting' as it's handled by Loading/Created in UI if needed
  }

  void _onSendMessage(SendMessageEvent event, Emitter<ConnectionStateBloc> emit) {
    if (peerRepository is PeerRepositoryImpl) {
      (peerRepository as PeerRepositoryImpl).sendSignalingMessage(event.payload);
    }
  }

  void _onMessageReceived(MessageReceivedEvent event, Emitter<ConnectionStateBloc> emit) {
    emit(ConnectionMessageReceived(event.payload));
  }

  void _onServerError(ServerErrorEvent event, Emitter<ConnectionStateBloc> emit) {
    emit(ConnectionServerError(event.message));
  }

  void _onStatusUpdate(StatusUpdateEvent event, Emitter<ConnectionStateBloc> emit) {
    if (state is ConnectionProgress) {
      final currentProgress = (state as ConnectionProgress).progress;
      emit(ConnectionProgress(currentProgress, event.message));
    } else {
      emit(ConnectionStatusUpdate(event.message));
    }
  }

  Future<void> _onResetConnection(
    ResetConnectionEvent event,
    Emitter<ConnectionStateBloc> emit,
  ) async {
    await peerRepository.dispose();
    currentRole = null;
    emit(ConnectionInitial());
    // Reinitialize for next usage
    await peerRepository.initialize();
  }

  @override
  Future<void> close() {
    _sessionStateSubscription?.cancel();
    _messageSubscription?.cancel();
    _serverErrorSubscription?.cancel();
    _statusSubscription?.cancel();
    peerRepository.dispose();
    return super.close();
  }
}
