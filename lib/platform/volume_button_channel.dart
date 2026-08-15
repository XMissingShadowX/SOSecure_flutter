import 'dart:io';

import 'package:flutter/services.dart';

// Evento del canal nativo. `press` es informativo (una pulsación suelta que ya
// quedó contada del lado nativo); `trigger` es el gesto completo: el SOS debe
// activarse.
class VolumeButtonEvent {
  final String type; // 'press' | 'trigger'
  final String? source; // 'up' | 'down' (solo en 'press')
  final int timestamp;

  const VolumeButtonEvent({
    required this.type,
    required this.timestamp,
    this.source,
  });

  bool get isTrigger => type == 'trigger';
}

// Wrapper Dart del MethodChannel/EventChannel de MainActivity.kt. Solo Android
// tiene esta capacidad (no hay API pública de botón de volumen en iOS; ahí el
// equivalente es el botón flotante de sos_button.dart).
//
// El conteo de pulsaciones dejó de vivir en Dart: ahora lo hace
// VolumeSosDetector.kt, porque con la pantalla apagada las teclas llegan a un
// foreground service y no a la Activity. Dart solo empuja la configuración y
// escucha el disparo.
class VolumeButtonChannel {
  static const _method = MethodChannel(
    'com.sosecure.sosecure_flutter/volume_button',
  );
  static const _events = EventChannel(
    'com.sosecure.sosecure_flutter/volume_button_events',
  );

  static Future<void> startListening() async {
    if (!Platform.isAndroid) return;
    await _method.invokeMethod('startListening');
  }

  static Future<void> stopListening() async {
    if (!Platform.isAndroid) return;
    await _method.invokeMethod('stopListening');
  }

  /// Persiste los umbrales del lado nativo y arranca o detiene el servicio en
  /// segundo plano. Hay que llamarlo cada vez que cambia la configuración: el
  /// servicio y el receptor de arranque leen esos valores sin que exista un
  /// motor de Flutter vivo.
  static Future<void> configure({
    required int presses,
    required int windowMs,
    required bool backgroundEnabled,
  }) async {
    if (!Platform.isAndroid) return;
    await _method.invokeMethod('configure', {
      'presses': presses,
      'windowMs': windowMs,
      'backgroundEnabled': backgroundEnabled,
    });
  }

  static Future<bool> isBackgroundServiceRunning() async {
    if (!Platform.isAndroid) return false;
    final running = await _method.invokeMethod<bool>(
      'isBackgroundServiceRunning',
    );
    return running ?? false;
  }

  /// Android 14+ (API 34) dejó de conceder `USE_FULL_SCREEN_INTENT` por
  /// defecto: sin él, el disparo con la app cerrada y el teléfono bloqueado
  /// degrada a una notificación normal en vez de abrir la app sobre la
  /// pantalla de bloqueo. En versiones previas el permiso ya viene concedido.
  static Future<bool> canUseFullScreenIntent() async {
    if (!Platform.isAndroid) return true;
    final granted = await _method.invokeMethod<bool>(
      'canUseFullScreenIntent',
    );
    return granted ?? true;
  }

  /// Abre la pantalla de ajustes del sistema donde se concede el permiso
  /// anterior. No hay API para pedirlo con un diálogo in-app.
  static Future<void> requestFullScreenIntentPermission() async {
    if (!Platform.isAndroid) return;
    await _method.invokeMethod('requestFullScreenIntentPermission');
  }

  /// Disparo que ocurrió sin la app viva (el servicio la acaba de levantar).
  /// Devuelve el instante del gesto, o null si no hay ninguno pendiente.
  static Future<DateTime?> consumePendingTrigger() async {
    if (!Platform.isAndroid) return null;
    final at = await _method.invokeMethod<int>('consumePendingTrigger');
    return at == null ? null : DateTime.fromMillisecondsSinceEpoch(at);
  }

  static Stream<VolumeButtonEvent> get onEvent {
    if (!Platform.isAndroid) return const Stream.empty();
    return _events.receiveBroadcastStream().map((event) {
      final map = Map<String, dynamic>.from(event as Map);
      return VolumeButtonEvent(
        type: map['type'] as String? ?? 'press',
        source: map['source'] as String?,
        timestamp: map['timestamp'] as int,
      );
    });
  }
}
