import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/volume_button_channel.dart';
import 'sos_provider.dart';

part 'volume_sos_provider.g.dart';

const _defaultPresses = 5;
const _defaultWindowMs = 3000;
const _pressesKey = 'sosecure.volumePresses';
const _windowKey = 'sosecure.volumeWindowMs';
const _backgroundKey = 'sosecure.volumeBackground';

// Un disparo guardado por el servicio se descarta si es demasiado viejo: abrir
// la app horas después no debe lanzar una alerta por un gesto de ayer. Mismo
// criterio que PENDING_TTL_MS en VolumeSosDetector.kt.
const _pendingTriggerMaxAge = Duration(minutes: 2);

// Espeja volumePresses/volumeWindow en lib/store.ts (persistidos en localStorage
// vía Zustand) — aquí en shared_preferences, con los mismos valores por defecto.
class VolumeSosState {
  final int pressesRequired;
  final int windowMs;

  /// Detección con la pantalla apagada / la app cerrada (foreground service
  /// nativo). Solo Android.
  final bool backgroundEnabled;

  const VolumeSosState({
    this.pressesRequired = _defaultPresses,
    this.windowMs = _defaultWindowMs,
    this.backgroundEnabled = true,
  });

  VolumeSosState copyWith({
    int? pressesRequired,
    int? windowMs,
    bool? backgroundEnabled,
  }) {
    return VolumeSosState(
      pressesRequired: pressesRequired ?? this.pressesRequired,
      windowMs: windowMs ?? this.windowMs,
      backgroundEnabled: backgroundEnabled ?? this.backgroundEnabled,
    );
  }
}

// Puerto de useVolumeSOS (hooks/use-volume-sos.ts), solo la rama nativa.
//
// El conteo de pulsaciones ya no vive acá: lo hace VolumeSosDetector.kt, que se
// alimenta tanto de la Activity (app en primer plano) como del foreground
// service (pantalla apagada, teléfono bloqueado o app cerrada). Este provider
// se limita a tres cosas:
//
//   · empujar los umbrales al lado nativo, que los persiste por su cuenta;
//   · activar el SOS cuando llega el evento 'trigger' con la app viva;
//   · consumir el disparo que quedó pendiente si la app estaba cerrada y el
//     servicio la acaba de levantar (al arrancar y en cada vuelta a primer
//     plano).
@Riverpod(keepAlive: true)
class VolumeSos extends _$VolumeSos {
  StreamSubscription<VolumeButtonEvent>? _sub;
  AppLifecycleListener? _lifecycle;
  bool _started = false;

  @override
  VolumeSosState build() {
    _load();
    ref.onDispose(_stop);
    _start();
    return const VolumeSosState();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = state.copyWith(
      pressesRequired: prefs.getInt(_pressesKey) ?? _defaultPresses,
      windowMs: prefs.getInt(_windowKey) ?? _defaultWindowMs,
      backgroundEnabled: prefs.getBool(_backgroundKey) ?? true,
    );
    await _pushConfig();
  }

  Future<void> setPressesRequired(int presses) async {
    state = state.copyWith(pressesRequired: presses);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_pressesKey, presses);
    await _pushConfig();
  }

  Future<void> setWindowMs(int ms) async {
    state = state.copyWith(windowMs: ms);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_windowKey, ms);
    await _pushConfig();
  }

  Future<void> setBackgroundEnabled(bool enabled) async {
    state = state.copyWith(backgroundEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_backgroundKey, enabled);
    await _pushConfig();
  }

  /// Arranca o detiene el servicio nativo según `backgroundEnabled`, además de
  /// persistir los umbrales del lado nativo.
  Future<void> _pushConfig() async {
    if (!Platform.isAndroid) return;
    await VolumeButtonChannel.configure(
      presses: state.pressesRequired,
      windowMs: state.windowMs,
      backgroundEnabled: state.backgroundEnabled,
    );
  }

  Future<void> _start() async {
    if (_started || !Platform.isAndroid) return;
    _started = true;
    await VolumeButtonChannel.startListening();
    _sub = VolumeButtonChannel.onEvent.listen((event) {
      if (event.isTrigger) _activateSos();
    });
    // Cada vez que la app vuelve a primer plano puede haber un disparo que el
    // servicio guardó mientras el motor de Flutter no existía.
    _lifecycle = AppLifecycleListener(onResume: _consumePendingTrigger);
    await _consumePendingTrigger();
  }

  void _stop() {
    _started = false;
    _sub?.cancel();
    _sub = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    VolumeButtonChannel.stopListening();
  }

  Future<void> _consumePendingTrigger() async {
    final at = await VolumeButtonChannel.consumePendingTrigger();
    if (at == null) return;
    if (DateTime.now().difference(at) > _pendingTriggerMaxAge) return;
    _activateSos();
  }

  void _activateSos() {
    // Se imprime con la misma etiqueta que usa el lado nativo (Log.d) para
    // poder seguir el gesto completo en un solo `adb logcat -s SOSecureVolume:D
    // flutter:I`: pulsaciones -> disparo -> activación del SOS.
    debugPrint('SOSecureVolume: disparo recibido en Dart, activando SOS');
    // activate() ya es idempotente (sale de inmediato si el SOS está activo),
    // así que no importa si el disparo llega por el canal y por el pendiente.
    ref.read(sosProvider.notifier).activate();
  }
}
