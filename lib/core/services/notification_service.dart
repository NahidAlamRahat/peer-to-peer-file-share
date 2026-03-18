import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Shows system notifications for transfer events (completion, failure).
/// On Web, flutter_local_notifications is not supported – no-op.
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'p2p_transfer';
  static const _channelName = 'File Transfer';
  static const _channelDesc = 'P2P file transfer status notifications';

  Future<void> init() async {
    if (kIsWeb) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
      macOS: darwinInit,
    );

    // v21 uses named parameter `settings:`
    await _plugin.initialize(settings: initSettings);

    // Request Android 13+ POST_NOTIFICATIONS permission
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
  }

  NotificationDetails get _details => const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
        ),
      );

  Future<void> showTransferComplete({
    required bool isSender,
    required String fileName,
  }) async {
    if (kIsWeb) return;
    final title = isSender ? '✅ File Sent!' : '✅ File Received!';
    final body = isSender
        ? '"$fileName" sent successfully.'
        : '"$fileName" saved to your device.';
    // v21 uses named parameters id:, title:, body:, notificationDetails:
    await _plugin.show(
      id: 1001,
      title: title,
      body: body,
      notificationDetails: _details,
    );
  }

  Future<void> showTransferFailed({required String reason}) async {
    if (kIsWeb) return;
    await _plugin.show(
      id: 1002,
      title: '❌ Transfer Failed',
      body: reason,
      notificationDetails: _details,
    );
  }
}
