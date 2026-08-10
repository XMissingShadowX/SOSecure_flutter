import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/repositories/alerts_repository.dart';
import '../data/repositories/recordings_repository.dart';
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

// Cuánto se espera un fix de GPS antes de recurrir a la última posición
// conocida. La alarma y la grabación ya arrancaron para entonces — esto solo
// retrasa el registro de la alerta en Supabase, no el aviso a la usuaria.
const _locationWaitTimeout = Duration(seconds: 8);

// Cada cuánto se reintenta registrar la alerta mientras no haya ninguna
// ubicación disponible. No hay límite de reintentos: mientras el SOS siga
// activo se sigue intentando, porque rendirse equivale a dejar a la persona
// sin alerta.
const _pendingAlertRetryInterval = Duration(seconds: 2);

class SosState {
  final bool active;
  final SosAlert? alert;
  final List<String> contactsNotified;
  final bool saving;
  // SOS activo pero la alerta todavía no se pudo registrar por falta de
  // ubicación. Se sigue reintentando en segundo plano; en cuanto llegue
  // cualquier coordenada la alerta sale sola y esto vuelve a false.
  final bool locationPending;

  const SosState({
    this.active = false,
    this.alert,
    this.contactsNotified = const [],
    this.saving = false,
    this.locationPending = false,
  });

  SosState copyWith({
    bool? active,
    SosAlert? alert,
    List<String>? contactsNotified,
    bool? saving,
    bool? locationPending,
  }) {
    return SosState(
      active: active ?? this.active,
      alert: alert ?? this.alert,
      contactsNotified: contactsNotified ?? this.contactsNotified,
      saving: saving ?? this.saving,
      locationPending: locationPending ?? this.locationPending,
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
  Timer? _pendingAlertTimer;

  @override
  SosState build() {
    ref.onDispose(() {
      _locationTimer?.cancel();
      _pendingAlertTimer?.cancel();
    });
    return const SosState();
  }

  Future<void> activate() async {
    if (state.active) return;

    final contacts = ref.read(contactsProvider).valueOrNull ?? [];
    final names = contacts.map((c) => c.name).toList();

    // La alarma, el servicio y la grabación arrancan ANTES de resolver el GPS.
    // Antes esto vivía detrás de un `if (!hasCoordinates) return`, así que sin
    // fix de GPS el SOS se rendía en silencio absoluto — por voz era todavía
    // peor: la persona decía la palabra clave y el teléfono no hacía nada, y
    // ella creía que la alerta ya iba en camino.
    state = state.copyWith(
      active: true,
      contactsNotified: names,
      locationPending: false,
    );
    unawaited(SosForegroundService.start());
    // Estas dos claves ya estaban traducidas a los 5 idiomas desde hace
    // tiempo; el código simplemente nunca las usó y mandaba el texto en
    // español escrito a mano.
    unawaited(
      SosAlarm.triggerUrgent(
        'sos_alertActivated'.tr(),
        'sos_alertSent'.tr(),
      ),
    );

    // La grabación es evidencia suplementaria — si falla, la alerta procede igual.
    unawaited(ref.read(recorderProvider.notifier).start());

    final coords = await _resolveCoordinates();
    // Se canceló mientras esperábamos el fix: no hay nada que registrar.
    if (!state.active) return;

    if (coords == null) {
      // latitude/longitude son NOT NULL en sos_alerts, sos_locations e
      // incidents, así que sin coordenadas todavía no se puede registrar la
      // alerta — pero tampoco se abandona: se sigue reintentando en segundo
      // plano y sale sola en cuanto aparezca cualquier ubicación.
      state = state.copyWith(locationPending: true);
      _startPendingAlertRetry(names);
      return;
    }

    await _registerAlert(coords, names);
  }

  // Reintenta registrar la alerta mientras no haya ubicación. Sin límite de
  // intentos a propósito: el SOS sigue activo y la persona sigue en riesgo, así
  // que se insiste hasta que llegue una coordenada o hasta que ella cierre el
  // SOS. El intervalo es de segundos, no de milisegundos, para no castigar la
  // batería mientras tanto.
  void _startPendingAlertRetry(List<String> names) {
    _pendingAlertTimer?.cancel();
    _pendingAlertTimer = Timer.periodic(_pendingAlertRetryInterval, (
      timer,
    ) async {
      if (!state.active || state.alert != null) {
        timer.cancel();
        return;
      }

      final loc = ref.read(locationWatcherProvider);
      final coords = loc.hasCoordinates
          ? (latitude: loc.latitude!, longitude: loc.longitude!)
          : await ref.read(locationWatcherProvider.notifier).lastKnown();
      if (coords == null) return;

      timer.cancel();
      if (!state.active || state.alert != null) return;
      await _registerAlert(coords, names);
    });
  }

  Future<void> _registerAlert(
    ({double latitude, double longitude}) coords,
    List<String> names,
  ) async {
    try {
      final alert = await _alertsRepo.createAlert(
        latitude: coords.latitude,
        longitude: coords.longitude,
        contactNames: names,
      );
      state = state.copyWith(alert: alert, locationPending: false);

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
      state = state.copyWith(locationPending: false);
      final userId = ref.read(currentUserProvider)?.id;
      if (userId != null) {
        await ref
            .read(offlineQueueProvider.notifier)
            .enqueue(
              table: 'sos_alerts',
              payload: {
                'user_id': userId,
                'latitude': coords.latitude,
                'longitude': coords.longitude,
                'status': 'active',
                'contacts_notified': names,
              },
            );
      }
    }
  }

  // Resuelve coordenadas en tres escalones, de mejor a peor: fix actual del
  // stream -> esperar hasta _locationWaitTimeout a que llegue uno -> última
  // posición conocida del sistema. Devuelve null solo si no hay absolutamente
  // ninguna ubicación disponible (GPS denegado y sin caché); en ese caso el
  // reintento en segundo plano toma el relevo.
  Future<({double latitude, double longitude})?> _resolveCoordinates() async {
    final immediate = ref.read(locationWatcherProvider);
    if (immediate.hasCoordinates) {
      return (latitude: immediate.latitude!, longitude: immediate.longitude!);
    }

    final deadline = DateTime.now().add(_locationWaitTimeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 250));
      // La usuaria canceló el SOS mientras esperábamos el fix.
      if (!state.active) return null;
      final loc = ref.read(locationWatcherProvider);
      if (loc.hasCoordinates) {
        return (latitude: loc.latitude!, longitude: loc.longitude!);
      }
    }

    return ref.read(locationWatcherProvider.notifier).lastKnown();
  }

  // Falsa alarma: descarta grabación, borra alerta/incidente, limpia estado.
  Future<void> cancel() async {
    _locationTimer?.cancel();
    _locationTimer = null;
    _pendingAlertTimer?.cancel();
    _pendingAlertTimer = null;
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
    _pendingAlertTimer?.cancel();
    _pendingAlertTimer = null;
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
