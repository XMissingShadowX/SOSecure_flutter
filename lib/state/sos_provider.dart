import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/repositories/alerts_repository.dart';
import '../data/repositories/recordings_repository.dart';
import '../data/supabase_client.dart';
import '../domain/models/sos_alert.dart';
import '../platform/sos_alarm.dart';
import '../platform/sos_foreground_service.dart';
import 'auth_provider.dart';
import 'contacts_provider.dart';
import 'live_broadcast_provider.dart';
import 'location_provider.dart';
import 'offline_queue_provider.dart';
import 'recorder_controller.dart';

part 'sos_provider.g.dart';

class SosState {
  final bool active;

  /// Entre que se dispara el gesto (botón, volumen, voz, temporizador...) y
  /// que `active` pasa a true hay una espera de hasta 20s por el primer fix
  /// de GPS (ver _awaitCoordinates) durante la cual antes no había señal
  /// alguna en la UI — el botón volvía a verse idle y una emergencia real
  /// podía parecer que no hizo nada. Los call sites deben mostrar feedback
  /// mientras esto es true.
  final bool activating;
  final SosAlert? alert;
  final List<String> contactsNotified;
  final bool saving;

  const SosState({
    this.active = false,
    this.activating = false,
    this.alert,
    this.contactsNotified = const [],
    this.saving = false,
  });

  SosState copyWith({
    bool? active,
    bool? activating,
    SosAlert? alert,
    List<String>? contactsNotified,
    bool? saving,
  }) {
    return SosState(
      active: active ?? this.active,
      activating: activating ?? this.activating,
      alert: alert ?? this.alert,
      contactsNotified: contactsNotified ?? this.contactsNotified,
      saving: saving ?? this.saving,
    );
  }
}

// Puerto de la orquestación de sos-button.tsx (activateSOS/cancelSOS/handleSaveAndClose),
// sin la porción de streaming en vivo (excluida del MVP, ver addendum de Fase 2). Reutiliza
// el RecorderController singleton (recorder_controller.dart) y el watcher único de
// ubicación (location_provider.dart) — no adquiere cámara ni GPS por cuenta propia.
@Riverpod(keepAlive: true)
class Sos extends _$Sos {
  final _alertsRepo = AlertsRepository();
  final _recordingsRepo = RecordingsRepository();
  Timer? _locationTimer;
  bool _activating = false;

  @override
  SosState build() {
    ref.onDispose(() => _locationTimer?.cancel());
    return const SosState();
  }

  Future<void> activate() async {
    if (state.active || _activating) return;
    // Sin sesión no hay a quién asociarle la alerta ni contactos que
    // notificar (createAlert() exige user_id, y el encolado offline también
    // requiere currentUserProvider) — activar igual dejaba vibrar/grabar/
    // notificar como si el SOS hubiera salido, cuando en realidad la alerta
    // se perdía en silencio. Puede pasar con el gesto de volumen: queda
    // armado desde la raíz de la app (app.dart), antes del login.
    if (supabase.auth.currentUser == null) return;
    _activating = true;
    state = state.copyWith(activating: true);
    try {
      await _activate();
    } finally {
      _activating = false;
      state = state.copyWith(activating: false);
    }
  }

  Future<void> _activate() async {
    // Con la app recién abierta (por ejemplo cuando el gesto del botón de
    // volumen la levanta desde cero) el watcher de ubicación todavía no tiene
    // el primer fix: salir de inmediato dejaba la alerta sin enviar y sin que
    // el usuario se enterara. Se le da margen al GPS antes de rendirse. El
    // flag `activating` (puesto por activate()) es lo único que le avisa a la
    // UI que esta espera está en curso.
    final location = await _awaitCoordinates();
    if (location == null) return;

    final contacts = ref.read(contactsProvider).valueOrNull ?? [];
    final names = contacts.map((c) => c.name).toList();

    state = state.copyWith(active: true, contactsNotified: names);
    unawaited(SosForegroundService.start());
    unawaited(
      SosAlarm.triggerUrgent(
        '🚨 SOSecure SOS Activado',
        'Alerta de emergencia enviada a tus contactos',
      ),
    );

    // La grabación es evidencia suplementaria — si falla, la alerta procede igual.
    unawaited(ref.read(recorderProvider.notifier).start());

    try {
      final alert = await _alertsRepo.createAlert(
        latitude: location.latitude!,
        longitude: location.longitude!,
        contactNames: names,
      );
      state = state.copyWith(alert: alert);

      _locationTimer?.cancel();
      _locationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        final loc = ref.read(locationWatcherProvider);
        if (loc.hasCoordinates) {
          _alertsRepo.updateLocation(
            alertId: alert.id,
            latitude: loc.latitude!,
            longitude: loc.longitude!,
          );
        }
      });
    } catch (_) {
      // La alerta en Supabase falló (sin conexión, etc.) — la grabación local sigue
      // en curso. Se encola para reintentar en cuanto vuelva la conexión (ver
      // offline_queue_provider.dart), en vez de perder la alerta silenciosamente.
      final userId = ref.read(currentUserProvider)?.id;
      if (userId != null) {
        await ref
            .read(offlineQueueProvider.notifier)
            .enqueue(
              table: 'sos_alerts',
              payload: {
                'user_id': userId,
                'latitude': location.latitude,
                'longitude': location.longitude,
                'status': 'active',
                'contacts_notified': names,
              },
            );
      }
    }
  }

  // Espera hasta [timeout] a que el watcher único de ubicación entregue un fix.
  // Devuelve null si no llegó ninguno — sin coordenadas no hay alerta que crear
  // (la tabla sos_alerts las exige).
  Future<LocationState?> _awaitCoordinates({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final current = ref.read(locationWatcherProvider);
    if (current.hasCoordinates) return current;

    final completer = Completer<LocationState?>();
    final subscription = ref.listen<LocationState>(locationWatcherProvider, (
      _,
      next,
    ) {
      if (next.hasCoordinates && !completer.isCompleted) completer.complete(next);
    });
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(null);
    });

    try {
      return await completer.future;
    } finally {
      timer.cancel();
      subscription.close();
    }
  }

  // Falsa alarma: descarta grabación, borra alerta/incidente, limpia estado.
  Future<void> cancel() async {
    // Hoy el único llamador (el diálogo de falsa alarma en sos_button.dart)
    // solo se muestra con `active == true`, pero sin esta guarda un futuro
    // call site accidental tiraría abajo el servicio en primer plano y
    // llamaría a cancelAlert() sin que hubiera nada que cancelar.
    if (!state.active) return;
    _locationTimer?.cancel();
    _locationTimer = null;
    await ref.read(liveBroadcastProvider.notifier).stop();
    await ref.read(recorderProvider.notifier).discard();
    await _alertsRepo.cancelAlert();
    await SosForegroundService.stop();
    state = const SosState();
  }

  // Guardar y cerrar: detiene grabación, sube a Storage vinculada a la alerta, cierra el SOS.
  Future<void> saveAndClose() async {
    _locationTimer?.cancel();
    _locationTimer = null;
    await ref.read(liveBroadcastProvider.notifier).stop();
    state = state.copyWith(saving: true);

    final startedAt = ref.read(recorderProvider).startedAt;
    final file = await ref.read(recorderProvider.notifier).stop();
    final alert = state.alert;
    if (file != null && alert != null) {
      try {
        final location = ref.read(locationWatcherProvider);
        final durationMs = startedAt == null
            ? 0
            : DateTime.now().difference(startedAt).inMilliseconds;
        await _recordingsRepo.uploadSosRecording(
          file: file,
          // Confirmado en el spike de Fase 2: CameraController produce mp4 en Android.
          mimeType: 'video/mp4',
          durationMs: durationMs,
          latitude: location.latitude,
          longitude: location.longitude,
          sosAlertId: alert.id,
        );
      } catch (_) {
        // Sin conexión / falla de subida — la grabación local ya se detuvo; se pierde
        // la evidencia de este intento (paridad con el comportamiento actual de la web,
        // que tampoco reintenta la subida fallida). Cola offline llega en Fase 3.
      }
    }

    await SosForegroundService.stop();
    state = const SosState();
  }
}
