import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/repositories/live_stream_repository.dart';
import '../data/supabase_client.dart';
import 'recorder_controller.dart';

part 'live_broadcast_provider.g.dart';

// Subido a 4s (desde 2s, que ya venía de 1.5s): cada rotateSegment() implica
// stopVideoRecording() + startVideoRecording() en el MISMO CameraController
// (un solo encoder de hardware — no hay forma de grabar sin ese corte real
// con este plugin, ver la nota extensa en recorder_controller.dart). Esa
// transición es la única fuente real de discontinuidad de la grabación en
// sí; duplicar la duración del segmento la reduce a la mitad de frecuencia
// sin tocar su costo individual, y como el encoder de CameraX necesitaba
// MÁS margen tras startVideoRecording() antes de aceptar el próximo stop
// (motivo del bump anterior de 1.5s a 2s), alargar el intervalo es
// estrictamente más seguro en esa misma dirección, nunca menos. El buffer
// doble del visor (ver live_stream_viewer.dart) ya elimina la pausa de
// carga entre clips recibidos — este cambio ataca la otra mitad del
// problema: cuántas veces por minuto ocurre el corte real de cámara.
const segmentDuration = Duration(milliseconds: 4000);

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
  // Con red lenta, la grabación sigue cortando segmentos cada segmentDuration
  // aunque la subida de los anteriores no haya terminado — sin este límite,
  // los archivos .mp4 temporales de cada segmento (y la cola de Futures
  // encadenados) crecerían sin techo durante todo el SOS. Al tope, se
  // descarta el segmento más nuevo (se borra su archivo) en vez de acumular:
  // la grabación de evidencia (RecorderController) no se ve afectada, solo
  // se pierde ese clip puntual de la transmisión en vivo.
  int _pendingUploads = 0;
  static const _maxPendingUploads = 3;
  static const _uploadTimeout = Duration(seconds: 15);

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
    // A partir de acá cualquier salida temprana debe borrar el archivo del
    // segmento — de lo contrario queda huérfano en el almacenamiento
    // temporal para siempre (nunca se sube ni se libera).
    if (_channel == null) {
      unawaited(_discardSegmentFile(file));
      return;
    }
    if (_pendingUploads >= _maxPendingUploads) {
      // Red más lenta que la cadencia de segmentos: en vez de acumular
      // subidas pendientes (y sus archivos temporales) indefinidamente, se
      // descarta este segmento — la grabación de evidencia sigue intacta,
      // solo se salta un clip de la transmisión en vivo.
      debugPrint(
        '[LiveBroadcast] cola de subida saturada ($_pendingUploads) — se descarta segmento seq=$_seq',
      );
      unawaited(_discardSegmentFile(file));
      return;
    }
    final seq = _seq++;
    final capturedFile = file;
    _pendingUploads++;
    // Encadenado (no unawaited) para preservar el orden de seq al mandar el
    // broadcast, aunque una subida sea más lenta que la siguiente.
    _uploadChain = _uploadChain.then((_) async {
      try {
        final url = await _repo
            .uploadSegment(file: capturedFile, alertId: alertId, seq: seq)
            .timeout(_uploadTimeout);
        debugPrint('[LiveBroadcast] segmento $seq subido: $url');
        if (_channel == null) return;
        await _repo
            .sendSegment(
              _channel!,
              VideoSegmentPayload(
                url: url,
                seq: seq,
                ts: DateTime.now().millisecondsSinceEpoch,
              ),
            )
            .timeout(_uploadTimeout);
        debugPrint('[LiveBroadcast] segmento $seq transmitido por broadcast');
        state = state.copyWith(segmentsSent: seq + 1);
      } catch (e, st) {
        // Red lenta/caída a mitad de subida: se registra el error y se
        // continúa con el siguiente segmento — nunca se bloquea ni se
        // reintenta este mismo clip indefinidamente.
        debugPrint('[LiveBroadcast] ERROR en segmento $seq: $e\n$st');
        state = state.copyWith(
          error: 'live_broadcastFailed'.tr(namedArgs: {'e': '$e'}),
        );
      } finally {
        _pendingUploads--;
        await _discardSegmentFile(capturedFile);
      }
    });
  }

  // Borra el archivo temporal de un segmento ya procesado (subido, fallido o
  // descartado por saturación) — sin esto, cada segmento cortado por
  // rotateSegment() (uno cada segmentDuration mientras dura la transmisión)
  // quedaría en el almacenamiento temporal del dispositivo para siempre.
  Future<void> _discardSegmentFile(File file) async {
    try {
      await file.delete();
    } catch (_) {
      /* ya no existía o el filesystem no lo permitió — no es crítico */
    }
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
