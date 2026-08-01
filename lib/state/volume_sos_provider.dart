import 'dart:async';
import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/volume_button_channel.dart';
import 'sos_provider.dart';

part 'volume_sos_provider.g.dart';

const _defaultPresses = 5;
const _defaultWindowMs = 3000;
const _pressesKey = 'sosecure.volumePresses';
const _windowKey = 'sosecure.volumeWindowMs';

// Espeja volumePresses/volumeWindow en lib/store.ts (persistidos en localStorage
// vía Zustand) — aquí en shared_preferences, con los mismos valores por defecto.
class VolumeSosState {
  final int pressesRequired;
  final int windowMs;

  const VolumeSosState({
    this.pressesRequired = _defaultPresses,
    this.windowMs = _defaultWindowMs,
  });

  VolumeSosState copyWith({int? pressesRequired, int? windowMs}) {
    return VolumeSosState(
      pressesRequired: pressesRequired ?? this.pressesRequired,
      windowMs: windowMs ?? this.windowMs,
    );
  }
}

// Puerto de useVolumeSOS (hooks/use-volume-sos.ts), solo la rama nativa —
// la web también escucha 'keydown'/'volumechange' como fallback de PWA, que
// no aplica aquí. Escucha VolumeButtonChannel.onPress todo el tiempo que la
// app esté viva y pausa (deja de escuchar el canal nativo) mientras el SOS ya
// está activo, igual que `disabled` en el hook web.
@Riverpod(keepAlive: true)
class VolumeSos extends _$VolumeSos {
  StreamSubscription<VolumeButtonEvent>? _sub;
  final List<DateTime> _pressTimes = [];
  bool _started = false;

  @override
  VolumeSosState build() {
    _load();
    ref.listen(sosProvider, (prev, next) {
      if (next.active) {
        _stop();
      } else {
        _start();
      }
    });
    ref.onDispose(_stop);
    if (!ref.read(sosProvider).active) _start();
    return const VolumeSosState();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = state.copyWith(
      pressesRequired: prefs.getInt(_pressesKey) ?? _defaultPresses,
      windowMs: prefs.getInt(_windowKey) ?? _defaultWindowMs,
    );
  }

  Future<void> setPressesRequired(int presses) async {
    state = state.copyWith(pressesRequired: presses);
    _pressTimes.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_pressesKey, presses);
  }

  Future<void> setWindowMs(int ms) async {
    state = state.copyWith(windowMs: ms);
    _pressTimes.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_windowKey, ms);
  }

  Future<void> _start() async {
    if (_started || !Platform.isAndroid) return;
    _started = true;
    await VolumeButtonChannel.startListening();
    _sub = VolumeButtonChannel.onPress.listen(_onPress);
  }

  void _stop() {
    _started = false;
    _sub?.cancel();
    _sub = null;
    _pressTimes.clear();
    VolumeButtonChannel.stopListening();
  }

  void _onPress(VolumeButtonEvent event) {
    final now = DateTime.now();
    final window = Duration(milliseconds: state.windowMs);
    _pressTimes.removeWhere((t) => now.difference(t) >= window);
    _pressTimes.add(now);
    if (_pressTimes.length >= state.pressesRequired) {
      _pressTimes.clear();
      ref.read(sosProvider.notifier).activate();
    }
  }
}
