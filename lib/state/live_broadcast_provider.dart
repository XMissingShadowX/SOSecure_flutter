import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/repositories/live_stream_repository.dart';
import '../data/supabase_client.dart';
import 'recorder_controller.dart';

part 'live_broadcast_provider.g.dart';

const segmentDuration = Duration(milliseconds: 1500);

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
      if (status == RealtimeSubscribeStatus.subscribed && !joined.isCompleted) {
        joined.complete();
      }
    });
    await joined.future.timeout(const Duration(seconds: 10), onTimeout: () {});

    await _repo.sendStatus(_channel!, live: true);
    state = const LiveBroadcastState(live: true);

    _timer = Timer.periodic(segmentDuration, (_) => _captureAndSend(alertId));
  }

  Future<void> _captureAndSend(String alertId) async {
    final file = await ref.read(recorderProvider.notifier).rotateSegment();
    if (file == null || _channel == null) return;
    try {
      final url = await _repo.uploadSegment(
        file: file,
        alertId: alertId,
        seq: _seq,
      );
      await _repo.sendSegment(
        _channel!,
        VideoSegmentPayload(
          url: url,
          seq: _seq,
          ts: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      _seq++;
      state = state.copyWith(segmentsSent: _seq);
    } catch (e) {
      state = state.copyWith(error: 'Error al transmitir: $e');
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
