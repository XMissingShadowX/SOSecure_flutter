import 'dart:io';

import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'standalone_recorder_provider.g.dart';

const _uuid = Uuid();

enum StandaloneRecMode { idle, audio, video }

class StandaloneRecorderState {
  final StandaloneRecMode mode;
  final CameraController? videoController;
  final DateTime? startedAt;
  final String? errorMessage;

  const StandaloneRecorderState({
    this.mode = StandaloneRecMode.idle,
    this.videoController,
    this.startedAt,
    this.errorMessage,
  });

  StandaloneRecorderState copyWith({
    StandaloneRecMode? mode,
    CameraController? videoController,
    DateTime? startedAt,
    String? errorMessage,
  }) {
    return StandaloneRecorderState(
      mode: mode ?? this.mode,
      videoController: videoController ?? this.videoController,
      startedAt: startedAt ?? this.startedAt,
      errorMessage: errorMessage,
    );
  }
}

// Puerto de toggleAudio()/toggleVideo() de during-tab.tsx — grabación libre,
// no ligada a una alerta SOS (a diferencia de recorder_controller.dart de la
// Fase 2, que sí lo está). Instancia completamente separada: no comparte
// CameraController con el RecorderController del SOS, para no interferir con
// una alerta que pudiera estar en curso.
@Riverpod(keepAlive: true)
class StandaloneRecorder extends _$StandaloneRecorder {
  final _audioRecorder = AudioRecorder();
  String? _pendingPath;

  @override
  StandaloneRecorderState build() {
    ref.onDispose(() {
      _audioRecorder.dispose();
      state.videoController?.dispose();
    });
    return const StandaloneRecorderState();
  }

  Future<void> startAudio() async {
    if (state.mode != StandaloneRecMode.idle) return;
    if (!await _audioRecorder.hasPermission()) {
      state = state.copyWith(errorMessage: 'Permiso de micrófono denegado.');
      return;
    }
    final dir = await getTemporaryDirectory();
    _pendingPath = '${dir.path}/audio-${_uuid.v4()}.m4a';
    await _audioRecorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: _pendingPath!,
    );
    state = StandaloneRecorderState(
      mode: StandaloneRecMode.audio,
      startedAt: DateTime.now(),
    );
  }

  Future<File?> stopAudio() async {
    if (state.mode != StandaloneRecMode.audio) return null;
    final path = await _audioRecorder.stop();
    state = const StandaloneRecorderState();
    return path != null ? File(path) : null;
  }

  Future<void> startVideo() async {
    if (state.mode != StandaloneRecMode.idle) return;
    final micStatus = await Permission.microphone.request();
    final camStatus = await Permission.camera.request();
    if (!camStatus.isGranted) {
      state = state.copyWith(errorMessage: 'Permiso de cámara denegado.');
      return;
    }
    if (!micStatus.isGranted) {
      state = state.copyWith(errorMessage: 'Permiso de micrófono denegado.');
    }
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        state = state.copyWith(errorMessage: 'No hay cámara disponible.');
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: true,
      );
      await controller.initialize();
      await controller.prepareForVideoRecording();
      await controller.startVideoRecording();
      state = StandaloneRecorderState(
        mode: StandaloneRecMode.video,
        videoController: controller,
        startedAt: DateTime.now(),
      );
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'No se pudo iniciar la grabación: $e',
      );
    }
  }

  Future<File?> stopVideo() async {
    if (state.mode != StandaloneRecMode.video || state.videoController == null)
      return null;
    try {
      final xfile = await state.videoController!.stopVideoRecording();
      await state.videoController!.dispose();
      state = const StandaloneRecorderState();
      return File(xfile.path);
    } catch (e) {
      await state.videoController?.dispose();
      state = StandaloneRecorderState(errorMessage: 'Error al detener: $e');
      return null;
    }
  }

  Future<void> discard() async {
    if (state.mode == StandaloneRecMode.audio) {
      await _audioRecorder.stop();
    } else if (state.mode == StandaloneRecMode.video) {
      try {
        await state.videoController?.stopVideoRecording();
      } catch (_) {
        /* noop */
      }
      await state.videoController?.dispose();
    }
    state = const StandaloneRecorderState();
  }
}
