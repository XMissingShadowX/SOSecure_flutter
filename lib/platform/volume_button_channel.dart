import 'dart:io';

import 'package:flutter/services.dart';

class VolumeButtonEvent {
  final String button; // 'up' | 'down'
  final int timestamp;
  VolumeButtonEvent({required this.button, required this.timestamp});
}

// Wrapper Dart del MethodChannel/EventChannel de MainActivity.kt — puerto de
// VolumeButtonPlugin.java. Solo Android tiene esta capacidad (no hay API
// pública de botón de volumen en iOS, ver ios_secondary_gesture equivalente
// en before_tab/sos_button: el botón flotante).
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

  static Stream<VolumeButtonEvent> get onPress {
    if (!Platform.isAndroid) return const Stream.empty();
    return _events.receiveBroadcastStream().map((event) {
      final map = Map<String, dynamic>.from(event as Map);
      return VolumeButtonEvent(
        button: map['button'] as String,
        timestamp: map['timestamp'] as int,
      );
    });
  }
}
