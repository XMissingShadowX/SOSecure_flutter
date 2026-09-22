import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../data/repositories/live_stream_repository.dart';
import '../../data/supabase_client.dart';

// Puerto de LiveStreamViewer (components/emergency-chat.tsx) para el modelo
// de clips segmentados en vez de chunks WebM — ver live_stream_repository.dart.
//
// Doble buffer real: mientras BUFFER A (_playingController) se reproduce,
// BUFFER B (_preloadingController) ya está descargando/decodificando el
// siguiente segmento en segundo plano. Antes, el siguiente controller se
// creaba e inicializaba (fetch de red + decode) recién CUANDO el segmento
// actual terminaba — esa espera (initialize() sobre la red) era la pausa
// visible entre clips. Ahora, en cuanto un segmento empieza a reproducirse,
// ya se dispara la precarga del que sigue, así el intercambio al terminar es
// prácticamente instantáneo (el controller ya está listo).
class LiveStreamViewer extends StatefulWidget {
  final String alertId;
  const LiveStreamViewer({super.key, required this.alertId});

  @override
  State<LiveStreamViewer> createState() => _LiveStreamViewerState();
}

class _LiveStreamViewerState extends State<LiveStreamViewer> {
  final _repo = LiveStreamRepository();
  final List<VideoSegmentPayload> _queue = [];

  VideoPlayerController? _playingController;
  VideoPlayerController? _preloadingController;
  Future<bool>? _preloadReady;

  // Se pone en true cuando el segmento en reproducción terminó y no había
  // ningún otro ya precargado — es decir, un under-run real por red lenta,
  // no por arquitectura. Mientras esté en true, en cuanto un segmento nuevo
  // termine de precargarse debe promoverse de inmediato (no esperar un tick
  // de reproducción que ya no va a llegar, porque no hay nada reproduciéndose).
  bool _awaitingNext = false;
  bool _disposed = false;

  bool _live = false;
  bool _waiting = true;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    final channel = _repo.channel(widget.alertId);
    channel
        .onBroadcast(
          event: 'status',
          callback: (payload) {
            final live = payload['live'] as bool? ?? false;
            if (!mounted) return;
            setState(() {
              _live = live;
              if (live) _waiting = false;
            });
          },
        )
        .onBroadcast(
          event: 'video_segment',
          callback: (payload) {
            final segment = VideoSegmentPayload.fromJson(payload);
            _enqueue(segment);
            if (!mounted) return;
            setState(() {
              _live = true;
              _waiting = false;
            });
          },
        )
        .subscribe();
    _channel = channel;
  }

  void _enqueue(VideoSegmentPayload segment) {
    _queue.add(segment);
    // Si se acumularon varios segmentos (red lenta), descartar los viejos y
    // quedarse con los más recientes — igual que el recorte de cola en la web.
    // No toca al que ya está precargándose (ese ya salió de _queue).
    while (_queue.length > 3) {
      _queue.removeAt(0);
    }
    _fillPreloadSlot();
  }

  // Toma el siguiente segmento pendiente y arranca su inicialización en
  // background. Si no hay nada reproduciéndose (arranque inicial o un
  // under-run previo), lo promueve en cuanto esté listo.
  void _fillPreloadSlot() {
    if (_preloadingController != null) return; // ya hay uno preparándose
    if (_queue.isEmpty) return;
    final segment = _queue.removeAt(0);
    final controller = VideoPlayerController.networkUrl(Uri.parse(segment.url));
    _preloadingController = controller;
    _preloadReady = controller
        .initialize()
        .then((_) => true)
        .catchError((Object e, StackTrace st) {
          debugPrint(
            '[LiveStreamViewer] error precargando segmento ${segment.seq}: $e',
          );
          return false;
        });
    if (_playingController == null || _awaitingNext) {
      unawaited(_promotePreload());
    }
  }

  Future<void> _promotePreload() async {
    final controller = _preloadingController;
    final ready = _preloadReady;
    if (controller == null || ready == null) return;
    final ok = await ready;
    if (_disposed) {
      await controller.dispose();
      return;
    }
    // Puede haber sido reemplazado mientras esperábamos (no debería, dado el
    // candado de un solo slot, pero es una guarda barata contra callbacks
    // fuera de orden).
    if (_preloadingController != controller) return;
    _preloadingController = null;
    _preloadReady = null;
    if (!ok) {
      // Este clip en particular falló al decodificar (red cortada a mitad de
      // descarga, mp4 incompleto, etc.) — se descarta y se intenta con el
      // siguiente en cola en vez de dejar la transmisión colgada esperando
      // justo este segmento.
      _fillPreloadSlot();
      return;
    }
    _awaitingNext = false;
    final old = _playingController;
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() => _playingController = controller);
    await old?.dispose();
    await controller.play();
    controller.addListener(() => _onTick(controller));
    // Doble buffer: dispara la precarga del siguiente YA, mientras este
    // recién arranca — así, cuando termine, el reemplazo es inmediato.
    _fillPreloadSlot();
  }

  void _onTick(VideoPlayerController controller) {
    // Listener de un controller que ya dejó de ser el activo (reemplazado
    // antes de que se le pudiera remover el listener) — ignorar.
    if (controller != _playingController) return;
    final value = controller.value;
    if (value.position >= value.duration && !value.isPlaying) {
      _advance();
    }
  }

  void _advance() {
    if (_preloadingController != null) {
      unawaited(_promotePreload());
    } else if (_queue.isNotEmpty) {
      // Hay segmentos en cola pero ninguno se había empezado a precargar
      // (llegaron varios de golpe mientras el slot de precarga ya estaba
      // ocupado). _awaitingNext ANTES de _fillPreloadSlot() es lo que hace
      // que, apenas termine de inicializar, se promueva solo — si no,
      // quedaría preparado pero nadie lo reproduciría nunca.
      _awaitingNext = true;
      _fillPreloadSlot();
    } else {
      // Nada listo todavía: red más lenta que la duración del segmento. Se
      // mantiene el último frame en pantalla (sin pantalla negra) hasta que
      // llegue el próximo segmento — _enqueue -> _fillPreloadSlot lo promueve
      // apenas esté listo, gracias a _awaitingNext.
      _awaitingNext = true;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (_channel != null) supabase.removeChannel(_channel!);
    _playingController?.dispose();
    _preloadingController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_waiting) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.podcasts,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'chat_waiting'.tr(),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            Text(
              'chat_waitingDesc'.tr(),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            color: Colors.black,
            height: 220,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_playingController != null &&
                    _playingController!.value.isInitialized)
                  AspectRatio(
                    aspectRatio: _playingController!.value.aspectRatio,
                    child: VideoPlayer(_playingController!),
                  )
                else
                  const CircularProgressIndicator(color: Colors.white54),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _live
                          ? Theme.of(context).colorScheme.error
                          : Colors.black54,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _live ? 'chat_live'.tr() : 'FINALIZADO',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
