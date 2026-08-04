import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/repositories/live_stream_repository.dart';
import '../data/supabase_client.dart';
import 'recorder_controller.dart';

part 'live_broadcast_provider.g.dart';

// Subido a 2s (desde 1.5s): el encoder de video de CameraX necesita un
// margen real tras startVideoRecording() antes de poder recibir un nuevo
// stopVideoRecording() sin crashear — ver la nota en _captureAndSend.
const segmentDuration = Duration(milliseconds: 2000);

class LiveBroadcastState {
  final bool live;
  final int segmentsSent;
  final String? error;

  const LiveBroadcastState({
    this.live = false,
    this.segmentsSent = 0,
    this.error,
  });

  LiveBroadcastState copyWith({bool? live, int? segmentsSent, String? error}) {
    return LiveBroadcastState(
      live: live ?? this.live,
      segmentsSent: segmentsSent ?? this.segmentsSent,
      error: error,
    );
  }
}

// Puerto del lado emisor de lib/live-stream.ts (createLiveBroadcaster), pero
// con clips segmentados en vez de chunks WebM crudos — ver la nota en
// live_stream_repository.dart sobre por qué. Reutiliza el mismo
// CameraController que ya está grabando la evidencia del SOS (rotateSegment
// en recorder_controller.dart) en vez de abrir una segunda cámara.
@Riverpod(keepAlive: true)
class LiveBroadcast extends _$LiveBroadcast {
  final _repo = LiveStreamRepository();
  RealtimeChannel? _channel;
  Timer? _timer;
  int _seq = 0;
  bool _capturing = false;
  // Encadena las subidas para mandarlas en orden (seq creciente) sin que una
  // subida lenta bloquee el siguiente corte de cámara — ver la nota en
  // _captureAndSend sobre por qué esto se separó del guard de captura.
  Future<void> _uploadChain = Future.value();

  @override
  LiveBroadcastState build() {
    ref.onDispose(() => _cleanup());
    return const LiveBroadcastState();
  }

  Future<void> start(String alertId) async {
    if (state.live) return;
    _seq = 0;
    _channel = _repo.channel(alertId);

    // Bug real encontrado en pruebas: mandar el status/los segmentos justo
    // después de llamar subscribe() (sin esperar la confirmación) los perdía
    // en silencio — el canal todavía no había terminado de unirse del lado
    // del servidor de Realtime. La web sí espera el callback 'SUBSCRIBED'
    // antes de mandar nada (ver lib/live-stream.ts); acá faltaba ese mismo
    // paso.
    final joined = Completer<void>();
    _channel!.subscribe((status, error) {
      debugPrint('[LiveBroadcast] subscribe status=$status error=$error');
      if (status == RealtimeSubscribeStatus.subscribed && !joined.isCompleted) {
        joined.complete();
      }
    });
    await joined.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () =>
          debugPrint('[LiveBroadcast] timeout esperando SUBSCRIBED'),
    );

    debugPrint(
      '[LiveBroadcast] canal unido, mandando status live=true para $alertId',
    );
    await _repo.sendStatus(_channel!, live: true);
    state = const LiveBroadcastState(live: true);

    _timer = Timer.periodic(segmentDuration, (_) => _captureAndSend(alertId));
  }

  Future<void> _captureAndSend(String alertId) async {
    // Bug real encontrado en pruebas: Timer.periodic dispara cada
    // segmentDuration SIN esperar a que el ciclo anterior (detener +
    // reiniciar grabación) termine. Si ese ciclo tardaba más que el
    // intervalo, el siguiente tick llamaba rotateSegment() ->
    // stopVideoRecording() mientras el encoder de video de CameraX del
    // startVideoRecording() anterior todavía no terminaba de inicializarse,
    // crasheando con NullPointerException nativo ("Encoder.stop on a null
    // object reference") y dejando rotateSegment() devolviendo null para
    // siempre. Este candado evita ticks superpuestos.
    if (_capturing) {
      debugPrint('[LiveBroadcast] tick ignorado — el anterior sigue en curso');
      return;
    }
    _capturing = true;
    File? file;
    try {
      file = await ref.read(recorderProvider.notifier).rotateSegment();
    } catch (e, st) {
      debugPrint('[LiveBroadcast] ERROR en rotateSegment (seq=$_seq): $e\n$st');
      _capturing = false;
      return;
    }
    // El guard de captura se libera ANTES de subir el archivo — la subida es
    // lenta (red) y NO debe demorar el corte del siguiente segmento de
    // cámara, que es instantáneo. Antes esto estaba en el mismo try/finally
    // y cada segmento real terminaba durando "2s + lo que tardara subir el
    // anterior", generando las pausas visibles en el receptor entre clips.
    _capturing = false;
    if (file == null) {
      debugPrint(
        '[LiveBroadcast] rotateSegment() devolvió null (seq=$_seq) — no se manda nada',
      );
      return;
    }
    if (_channel == null) return;
    final seq = _seq++;
    final capturedFile = file;
    // Encadenado (no unawaited) para preservar el orden de seq al mandar el
    // broadcast, aunque una subida sea más lenta que la siguiente.
    _uploadChain = _uploadChain.then((_) async {
      try {
        final url = await _repo.uploadSegment(
          file: capturedFile,
          alertId: alertId,
          seq: seq,
        );
        debugPrint('[LiveBroadcast] segmento $seq subido: $url');
        if (_channel == null) return;
        await _repo.sendSegment(
          _channel!,
          VideoSegmentPayload(
            url: url,
            seq: seq,
            ts: DateTime.now().millisecondsSinceEpoch,
          ),
        );
        debugPrint('[LiveBroadcast] segmento $seq transmitido por broadcast');
        state = state.copyWith(segmentsSent: seq + 1);
      } catch (e, st) {
        debugPrint('[LiveBroadcast] ERROR en segmento $seq: $e\n$st');
        state = state.copyWith(error: 'Error al transmitir: $e');
      }
    });
  }

  Future<void> stop() async {
    if (!state.live) return;
    _timer?.cancel();
    _timer = null;
    if (_channel != null) {
      try {
        await _repo.sendStatus(_channel!, live: false);
      } catch (_) {
        /* noop */
      }
      await supabase.removeChannel(_channel!);
      _channel = null;
    }
    state = const LiveBroadcastState();
  }

  void _cleanup() {
    _timer?.cancel();
    if (_channel != null) supabase.removeChannel(_channel!);
  }
}
