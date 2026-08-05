import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../data/repositories/live_stream_repository.dart';
import '../../data/supabase_client.dart';

// Puerto de LiveStreamViewer (components/emergency-chat.tsx) para el modelo
// de clips segmentados en vez de chunks WebM — ver live_stream_repository.dart.
// Encola las URLs de cada segmento recibido y las reproduce en secuencia con
// video_player (sin MediaSource/appendBuffer: cada clip ya es un mp4 completo).
class LiveStreamViewer extends StatefulWidget {
  final String alertId;
  const LiveStreamViewer({super.key, required this.alertId});

  @override
  State<LiveStreamViewer> createState() => _LiveStreamViewerState();
}

class _LiveStreamViewerState extends State<LiveStreamViewer> {
  final _repo = LiveStreamRepository();
  final List<VideoSegmentPayload> _queue = [];
  VideoPlayerController? _controller;
  bool _live = false;
  bool _waiting = true;
  bool _playing = false;

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
            _queue.add(segment);
            if (!mounted) return;
            setState(() {
              _live = true;
              _waiting = false;
            });
            _playNextIfIdle();
          },
        )
        .subscribe();
    _channel = channel;
  }

  RealtimeChannel? _channel;

  Future<void> _playNextIfIdle() async {
    if (_playing || _queue.isEmpty) return;
    _playing = true;
    // Si se acumularon varios segmentos (red lenta), descartar los viejos y
    // quedarse con el más reciente — igual que el recorte de cola en la web.
    while (_queue.length > 3) {
      _queue.removeAt(0);
    }
    final next = _queue.removeAt(0);
    final oldController = _controller;
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(next.url));
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      await oldController?.dispose();
      await controller.play();
      controller.addListener(() {
        if (controller.value.position >= controller.value.duration &&
            !controller.value.isPlaying) {
          _playing = false;
          _playNextIfIdle();
        }
      });
    } catch (_) {
      _playing = false;
      if (_queue.isNotEmpty) _playNextIfIdle();
    }
  }

  @override
  void dispose() {
    if (_channel != null) supabase.removeChannel(_channel!);
    _controller?.dispose();
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
                if (_controller != null && _controller!.value.isInitialized)
                  AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: VideoPlayer(_controller!),
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
