import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'sos_provider.dart';

part 'security_timer_provider.g.dart';

class SecurityTimerState {
  final bool active;
  final DateTime? endTime;
  final Duration? remaining;

  const SecurityTimerState({this.active = false, this.endTime, this.remaining});
}

// Puerto del temporizador de seguridad de before-tab.tsx. NO persiste (igual que
// securityTimerActive/securityTimerEnd en lib/store.ts, que quedan fuera del
// partialize) — se pierde si se cierra la app, a propósito, igual que la web.
// El aviso de "5 minutos antes" y el sonido/vibración de expiración son
// responsabilidad de la UI que consume este provider (before_tab_screen.dart);
// la sirena/notificación real llega en la Fase 4 (flutter_local_notifications).
@Riverpod(keepAlive: true)
class SecurityTimer extends _$SecurityTimer {
  Timer? _ticker;
  bool _fiveMinWarningShown = false;
  void Function()? onFiveMinuteWarning;
  void Function()? onExpired;

  @override
  SecurityTimerState build() {
    ref.onDispose(() => _ticker?.cancel());
    return const SecurityTimerState();
  }

  void start(Duration duration) {
    final end = DateTime.now().add(duration);
    _fiveMinWarningShown = false;
    state = SecurityTimerState(active: true, endTime: end, remaining: duration);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void cancel() {
    _ticker?.cancel();
    _ticker = null;
    state = const SecurityTimerState();
  }

  void _tick() {
    final end = state.endTime;
    if (end == null) return;
    final remaining = end.difference(DateTime.now());

    if (remaining.isNegative) {
      _ticker?.cancel();
      _ticker = null;
      state = const SecurityTimerState();
      onExpired?.call();
      // Dispara la misma alerta SOS que el botón manual — la lógica de
      // grabación/notificación a contactos es idéntica, no se duplica aquí.
      ref.read(sosProvider.notifier).activate();
      return;
    }

    if (!_fiveMinWarningShown && remaining <= const Duration(minutes: 5)) {
      _fiveMinWarningShown = true;
      onFiveMinuteWarning?.call();
    }

    state = SecurityTimerState(active: true, endTime: end, remaining: remaining);
  }
}
