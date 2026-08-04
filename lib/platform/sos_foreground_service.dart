import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

// Foreground service de Android para que la grabación/ubicación del SOS activo
// sobrevivan con la pantalla apagada o la app en segundo plano (ver plan de Fase 2,
// "Foreground service Android / background modes iOS"). No corre lógica propia en
// background — el propósito único es la notificación persistente que exime a la app
// de las restricciones de Android sobre servicios en segundo plano mientras el
// RecorderController (cámara) y el watcher de ubicación siguen operando en el proceso
// principal de Flutter. En iOS, el equivalente son los background modes declarados en
// Info.plist (audio + location), sin contraparte de "foreground service".
class SosForegroundService {
  static void init() {
    if (!Platform.isAndroid) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'sosecure_sos_active',
        channelName: 'Alerta SOS activa',
        channelDescription:
            'Se muestra mientras una alerta SOS está activa, para que la grabación y ubicación sigan funcionando en segundo plano.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
      ),
    );
  }

  static Future<void> requestPermissions() async {
    if (!Platform.isAndroid) return;
    final notificationPermission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
  }

  static Future<void> start() async {
    if (!Platform.isAndroid) return;
    if (await FlutterForegroundTask.isRunningService) return;
    await requestPermissions();
    await FlutterForegroundTask.startService(
      serviceId: 501,
      notificationTitle: 'SOSecure — Alerta activa',
      notificationText:
          'Grabando y compartiendo tu ubicación en segundo plano.',
    );
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}
