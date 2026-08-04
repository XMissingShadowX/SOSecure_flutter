import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'recorder_controller.g.dart';

enum RecorderStatus { idle, initializing, recording, stopping, error }

class RecorderState {
  final RecorderStatus status;
  final DateTime? startedAt;
  final String? errorMessage;
  final CameraController?
  controller; // expuesto solo para el preview, no para start/stop

  const RecorderState({
    this.status = RecorderStatus.idle,
    this.startedAt,
    this.errorMessage,
    this.controller,
  });

  RecorderState copyWith({
    RecorderStatus? status,
    DateTime? startedAt,
    String? errorMessage,
    CameraController? controller,
  }) {
    return RecorderState(
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      errorMessage: errorMessage,
      controller: controller ?? this.controller,
    );
  }
}

// Singleton de nivel superior (Notifier con keepAlive), reemplaza el `sosStream` de la web
// (un MediaStream compartido por referencia entre sos-button.tsx y during-tab.tsx). Aquí el
// equivalente es "compartido por referencia vía provider" — sos_button y during_tab hacen
// ref.watch(recorderControllerProvider) para leer el estado, pero solo el flujo de SOS
// (start) y una acción explícita del usuario (stop) mutan el ciclo de vida. Ver sección 4
// del plan de migración para el diseño completo.
@Riverpod(keepAlive: true)
class Recorder extends _$Recorder {
  @override
  RecorderState build() => const RecorderState();

  // Protección contra doble-disparo concurrente (ver plan: "if (state != idle) return").
  Future<void> start() async {
    if (state.status != RecorderStatus.idle &&
        state.status != RecorderStatus.error)
      return;
    state = state.copyWith(
      status: RecorderStatus.initializing,
      errorMessage: null,
    );

    try {
      final statuses = await [
        Permission.camera,
        Permission.microphone,
      ].request();
      if (statuses[Permission.camera] != PermissionStatus.granted) {
        state = state.copyWith(
          status: RecorderStatus.error,
          errorMessage: 'Permiso de cámara denegado.',
        );
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        state = state.copyWith(
          status: RecorderStatus.error,
          errorMessage: 'No hay cámara disponible.',
        );
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: true,
      );
      await controller.initialize();
      await controller.prepareForVideoRecording();
      await controller.startVideoRecording();

      state = state.copyWith(
        status: RecorderStatus.recording,
        startedAt: DateTime.now(),
        controller: controller,
      );
    } catch (e) {
      state = state.copyWith(
        status: RecorderStatus.error,
        errorMessage: 'No se pudo iniciar la grabación: $e',
      );
    }
  }

  // Detiene y libera la cámara, devuelve el archivo grabado (o null si nunca llegó a grabar
  // — el llamador debe dejar que la alerta SOS proceda de todos modos, la grabación es
  // evidencia suplementaria, no una condición para el disparo de la alerta).
  Future<File?> stop() async {
    final controller = state.controller;
    if (controller == null || state.status != RecorderStatus.recording) {
      await _disposeController();
      return null;
    }
    state = state.copyWith(status: RecorderStatus.stopping);
    try {
      final xfile = await controller.stopVideoRecording();
      await _disposeController();
      state = const RecorderState();
      return File(xfile.path);
    } catch (e) {
      await _disposeController();
      state = state.copyWith(
        status: RecorderStatus.error,
        errorMessage: 'Error al detener la grabación: $e',
      );
      return null;
    }
  }

  // Cancelar sin conservar el archivo (falsa alarma) — libera la cámara igual.
  Future<void> discard() async {
    final controller = state.controller;
    try {
      if (controller != null && controller.value.isRecordingVideo) {
        await controller.stopVideoRecording();
      }
    } catch (_) {
      /* noop */
    }
    await _disposeController();
    state = const RecorderState();
  }

  Future<void> _disposeController() async {
    final controller = state.controller;
    if (controller != null) {
      try {
        await controller.dispose();
      } catch (_) {
        /* noop */
      }
    }
  }

  // Puerto de Fase 6b (transmisión en vivo): a diferencia de la web, que puede
  // tener dos MediaRecorder simultáneos sobre el mismo MediaStream (uno para
  // el archivo de evidencia, otro para los chunks en vivo), el paquete
  // `camera` solo permite una grabación a la vez por CameraController. En vez
  // de abrir un segundo CameraController (el hardware de la cámara no lo
  // permite de forma confiable), "ir en vivo" corta el archivo de evidencia
  // en segmentos: cada llamada cierra el segmento actual y arranca el
  // siguiente de inmediato, sin pasar por idle ni soltar la cámara — el
  // estado sigue siendo `recording` todo el tiempo. LiveBroadcastController
  // es quien decide cuándo llamar esto y qué hacer con cada archivo
  // (subirlo y transmitirlo); start()/stop()/discard() no cambian.
  Future<File?> rotateSegment() async {
    final controller = state.controller;
    if (controller == null || state.status != RecorderStatus.recording)
      return null;
    try {
      // stopVideoRecording()/startVideoRecording() de CameraX pueden colgarse
      // sin lanzar excepción ni resolver el Future (visto en pruebas reales:
      // el primer segmento nunca llegaba y "_capturing" quedaba trabado para
      // siempre). El timeout convierte ese colgado silencioso en una
      // TimeoutException capturable, para que el guard de _captureAndSend se
      // libere y el próximo tick pueda reintentar en vez de morir para
      // siempre.
      debugPrint('[Recorder] rotateSegment: llamando stopVideoRecording()');
      final xfile = await controller.stopVideoRecording().timeout(
        const Duration(seconds: 6),
      );
      debugPrint('[Recorder] rotateSegment: stop OK, llamando startVideoRecording()');
      await controller.startVideoRecording().timeout(
        const Duration(seconds: 6),
      );
      debugPrint('[Recorder] rotateSegment: start OK');
      return File(xfile.path);
    } catch (e) {
      debugPrint('[Recorder] rotateSegment: ERROR/timeout — $e');
      return null;
    }
  }
}
