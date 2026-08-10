import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
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
      settings: const InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      ),
    );

    if (Platform.isAndroid) {
      // init() se llama de forma perezosa desde trigger*/notifyMessage, ya con
      // la app corriendo, así que aquí .tr() sí resuelve. Aun así Android
      // congela el nombre del canal al crearlo: si la usuaria cambia de idioma
      // después, estos dos nombres se quedan en el idioma del primer uso hasta
      // que se reinstale la app. Es una limitación de la plataforma.
      final sosChannel = AndroidNotificationChannel(
        'sosecure_sos',
        'notif_channelSosName'.tr(),
        description: 'notif_channelSosDesc'.tr(),
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );
      final chatChannel = AndroidNotificationChannel(
        'sosecure_chat',
        'notif_channelChatName'.tr(),
        description: 'notif_channelChatDesc'.tr(),
        importance: Importance.high,
        playSound: true,
      );
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidImpl?.createNotificationChannel(sosChannel);
      await androidImpl?.createNotificationChannel(chatChannel);
    }
  }

  // No existe en la web (emergency-chat.tsx no dispara ninguna notificación al
  // recibir un mensaje) — se agrega a pedido, reutilizando la infraestructura
  // de notificaciones locales ya montada para el SOS. Un id fijo por
  // remitente para que Android reemplace la notificación anterior de esa
  // misma conversación en vez de acumular una por mensaje.
  static Future<void> notifyMessage({
    required String senderId,
    required String title,
    required String body,
  }) async {
    await init();
    await _plugin.show(
      id: senderId.hashCode,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'sosecure_chat',
          'notif_channelChatName'.tr(),
          channelDescription: 'notif_channelChatDesc'.tr(),
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
        ),
        iOS: const DarwinNotificationDetails(presentSound: true),
      ),
    );
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
          'notif_channelSosName'.tr(),
          channelDescription: 'notif_channelSosDesc'.tr(),
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
