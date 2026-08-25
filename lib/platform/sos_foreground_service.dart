import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
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
  // Quién pidió que el servicio siga corriendo. Un SOS activo (sos_provider.dart)
  // y una grabación manual (standalone_recorder_provider.dart) pueden pedirlo
  // por separado y hasta solaparse (la persona empieza a grabar a mano y
  // durante eso dispara un SOS real); sin este conteo, quien terminara
  // primero apagaría el servicio para el otro y la cámara/ubicación del que
  // seguía activo se quedarían sin cobertura en segundo plano.
  static final Set<String> _owners = {};
  // OJO: init() corre desde main() ANTES de runApp, es decir antes de que
  // easy_localization tenga las traducciones cargadas — un .tr() aquí
  // devolvería la clave cruda. Por eso el nombre del canal se queda fijo.
  // Tampoco ganaría mucho traducirlo: Android congela el nombre del canal
  // cuando se crea y no lo renombra al cambiar el idioma de la app. Lo que sí
  // lee la usuaria (título y texto de la notificación) se traduce en start().
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

  static Future<void> start({
    required String owner,
    String? notificationTitle,
    String? notificationText,
  }) async {
    if (!Platform.isAndroid) return;
    _owners.add(owner);
    // Ya hay otro dueño manteniéndolo vivo: no se toca la notificación que ya
    // se está mostrando (podría ser la de un SOS real) por la de este dueño.
    if (await FlutterForegroundTask.isRunningService) return;
    await requestPermissions();
    await FlutterForegroundTask.startService(
      serviceId: 501,
      notificationTitle: notificationTitle ?? 'service_sosActiveTitle'.tr(),
      notificationText: notificationText ?? 'service_sosActiveBody'.tr(),
    );
  }

  static Future<void> stop({required String owner}) async {
    if (!Platform.isAndroid) return;
    _owners.remove(owner);
    // Sigue habiendo alguien más que lo necesita (ver _owners arriba).
    if (_owners.isNotEmpty) return;
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}
