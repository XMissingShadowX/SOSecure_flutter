import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';

// Puerto de sendAlarmNotification()/playAlarmSound() (lib/notifications.ts).
// La web sintetiza un tono con Web Audio (oscillator sawtooth 880->440->880Hz)
// más un patrón de vibración y una Notification del navegador — aquí se
// resuelve con el sonido/vibración por defecto del canal de notificación de
// Android (no hay forma simple de sintetizar un oscilador sin un paquete de
// audio adicional) y el patrón de vibración explícito vía `vibration`, que sí
// replica la intensidad "urgente" de la web.
class SosAlarm {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        'sosecure_sos',
        'Alertas SOS',
        description: 'Notificaciones de alerta SOS activada',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    }
  }

  // Equivalente a sendAlarmNotification(title, body, urgent=true) + playAlarmSound()
  // llamados juntos en activateSOS() de sos-button.tsx.
  static Future<void> triggerUrgent(String title, String body) async {
    await init();
    unawaited(_notify(title, body, urgent: true));
    unawaited(_vibrateUrgent());
  }

  // Equivalente al aviso no urgente (5 minutos antes de que expire el
  // temporizador de seguridad, before-tab.tsx).
  static Future<void> triggerWarning(String title, String body) async {
    await init();
    unawaited(_notify(title, body, urgent: false));
    unawaited(_vibrateWarning());
  }

  static Future<void> _notify(
    String title,
    String body, {
    required bool urgent,
  }) async {
    await _plugin.show(
      id: urgent ? 1 : 2,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'sosecure_sos',
          'Alertas SOS',
          channelDescription: 'Notificaciones de alerta SOS activada',
          importance: urgent ? Importance.max : Importance.high,
          priority: urgent ? Priority.max : Priority.high,
          ongoing: urgent,
          playSound: true,
        ),
        iOS: const DarwinNotificationDetails(presentSound: true),
      ),
    );
  }

  static Future<void> _vibrateUrgent() async {
    if (!await Vibration.hasVibrator()) return;
    // Patrón urgente de la web: [400,100,400,100,400,100,400].
    await Vibration.vibrate(pattern: [0, 400, 100, 400, 100, 400, 100, 400]);
  }

  static Future<void> _vibrateWarning() async {
    if (!await Vibration.hasVibrator()) return;
    // Patrón normal de la web: [200,100,200].
    await Vibration.vibrate(pattern: [0, 200, 100, 200]);
  }
}
