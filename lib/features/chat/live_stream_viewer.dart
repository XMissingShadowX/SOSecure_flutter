From bbc48da4a9261f05bec244fee926872bd2a2d594 Mon Sep 17 00:00:00 2001
From: adan58166-ops <adan58166-ops@users.noreply.github.com>
Date: Wed, 9 Sep 2026 02:02:42 +0000
Subject: [PATCH] fix: improve SOS video segment playback

The live-broadcast viewer created and initialized the next segment's
VideoPlayerController only after the current one finished playing,
so every ~2s transition showed a real network+decode pause. Replace
that with a true double buffer: the next segment starts preloading as
soon as the current one begins, so the swap on completion is instant.

Also bound the sender-side upload backlog (max pending uploads +
per-request timeout) and delete each segment's local temp file after
it's processed, since neither was cleaned up before and both could
grow unbounded during a slow-network SOS session. Increase
segmentDuration from 2s to 4s to halve how often the unavoidable
stop/start camera-encoder transition happens, in the same direction
already found safe by the prior 1.5s->2s bump.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_016PXw7DFsUcyVcTXkidQTkG
---
 lib/features/chat/live_stream_viewer.dart | 166 +++++++++++++++++-----
 lib/state/live_broadcast_provider.dart    |  92 +++++++++---
 2 files changed, 202 insertions(+), 56 deletions(-)

diff --git a/lib/features/chat/live_stream_viewer.dart b/lib/features/chat/live_stream_viewer.dart
index b71d6a2..e6d2643 100644
--- a/lib/features/chat/live_stream_viewer.dart
+++ b/lib/features/chat/live_stream_viewer.dart
@@ -1,3 +1,5 @@
+import 'dart:async';
+
 import 'package:easy_localization/easy_localization.dart';
 import 'package:flutter/material.dart';
 import 'package:supabase_flutter/supabase_flutter.dart';
@@ -8,8 +10,15 @@ import '../../data/supabase_client.dart';
 
 // Puerto de LiveStreamViewer (components/emergency-chat.tsx) para el modelo
 // de clips segmentados en vez de chunks WebM — ver live_stream_repository.dart.
-// Encola las URLs de cada segmento recibido y las reproduce en secuencia con
-// video_player (sin MediaSource/appendBuffer: cada clip ya es un mp4 completo).
+//
+// Doble buffer real: mientras BUFFER A (_playingController) se reproduce,
+// BUFFER B (_preloadingController) ya está descargando/decodificando el
+// siguiente segmento en segundo plano. Antes, el siguiente controller se
+// creaba e inicializaba (fetch de red + decode) recién CUANDO el segmento
+// actual terminaba — esa espera (initialize() sobre la red) era la pausa
+// visible entre clips. Ahora, en cuanto un segmento empieza a reproducirse,
+// ya se dispara la precarga del que sigue, así el intercambio al terminar es
+// prácticamente instantáneo (el controller ya está listo).
 class LiveStreamViewer extends StatefulWidget {
   final String alertId;
   const LiveStreamViewer({super.key, required this.alertId});
@@ -21,10 +30,22 @@ class LiveStreamViewer extends StatefulWidget {
 class _LiveStreamViewerState extends State<LiveStreamViewer> {
   final _repo = LiveStreamRepository();
   final List<VideoSegmentPayload> _queue = [];
-  VideoPlayerController? _controller;
+
+  VideoPlayerController? _playingController;
+  VideoPlayerController? _preloadingController;
+  Future<bool>? _preloadReady;
+
+  // Se pone en true cuando el segmento en reproducción terminó y no había
+  // ningún otro ya precargado — es decir, un under-run real por red lenta,
+  // no por arquitectura. Mientras esté en true, en cuanto un segmento nuevo
+  // termine de precargarse debe promoverse de inmediato (no esperar un tick
+  // de reproducción que ya no va a llegar, porque no hay nada reproduciéndose).
+  bool _awaitingNext = false;
+  bool _disposed = false;
+
   bool _live = false;
   bool _waiting = true;
-  bool _playing = false;
+  RealtimeChannel? _channel;
 
   @override
   void initState() {
@@ -46,58 +67,126 @@ class _LiveStreamViewerState extends State<LiveStreamViewer> {
           event: 'video_segment',
           callback: (payload) {
             final segment = VideoSegmentPayload.fromJson(payload);
-            _queue.add(segment);
+            _enqueue(segment);
             if (!mounted) return;
             setState(() {
               _live = true;
               _waiting = false;
             });
-            _playNextIfIdle();
           },
         )
         .subscribe();
     _channel = channel;
   }
 
-  RealtimeChannel? _channel;
-
-  Future<void> _playNextIfIdle() async {
-    if (_playing || _queue.isEmpty) return;
-    _playing = true;
+  void _enqueue(VideoSegmentPayload segment) {
+    _queue.add(segment);
     // Si se acumularon varios segmentos (red lenta), descartar los viejos y
-    // quedarse con el más reciente — igual que el recorte de cola en la web.
+    // quedarse con los más recientes — igual que el recorte de cola en la web.
+    // No toca al que ya está precargándose (ese ya salió de _queue).
     while (_queue.length > 3) {
       _queue.removeAt(0);
     }
-    final next = _queue.removeAt(0);
-    final oldController = _controller;
-    try {
-      final controller = VideoPlayerController.networkUrl(Uri.parse(next.url));
-      await controller.initialize();
-      if (!mounted) {
-        await controller.dispose();
-        return;
-      }
-      setState(() => _controller = controller);
-      await oldController?.dispose();
-      await controller.play();
-      controller.addListener(() {
-        if (controller.value.position >= controller.value.duration &&
-            !controller.value.isPlaying) {
-          _playing = false;
-          _playNextIfIdle();
-        }
-      });
-    } catch (_) {
-      _playing = false;
-      if (_queue.isNotEmpty) _playNextIfIdle();
+    _fillPreloadSlot();
+  }
+
+  // Toma el siguiente segmento pendiente y arranca su inicialización en
+  // background. Si no hay nada reproduciéndose (arranque inicial o un
+  // under-run previo), lo promueve en cuanto esté listo.
+  void _fillPreloadSlot() {
+    if (_preloadingController != null) return; // ya hay uno preparándose
+    if (_queue.isEmpty) return;
+    final segment = _queue.removeAt(0);
+    final controller = VideoPlayerController.networkUrl(Uri.parse(segment.url));
+    _preloadingController = controller;
+    _preloadReady = controller
+        .initialize()
+        .then((_) => true)
+        .catchError((Object e, StackTrace st) {
+          debugPrint(
+            '[LiveStreamViewer] error precargando segmento ${segment.seq}: $e',
+          );
+          return false;
+        });
+    if (_playingController == null || _awaitingNext) {
+      unawaited(_promotePreload());
+    }
+  }
+
+  Future<void> _promotePreload() async {
+    final controller = _preloadingController;
+    final ready = _preloadReady;
+    if (controller == null || ready == null) return;
+    final ok = await ready;
+    if (_disposed) {
+      await controller.dispose();
+      return;
+    }
+    // Puede haber sido reemplazado mientras esperábamos (no debería, dado el
+    // candado de un solo slot, pero es una guarda barata contra callbacks
+    // fuera de orden).
+    if (_preloadingController != controller) return;
+    _preloadingController = null;
+    _preloadReady = null;
+    if (!ok) {
+      // Este clip en particular falló al decodificar (red cortada a mitad de
+      // descarga, mp4 incompleto, etc.) — se descarta y se intenta con el
+      // siguiente en cola en vez de dejar la transmisión colgada esperando
+      // justo este segmento.
+      _fillPreloadSlot();
+      return;
+    }
+    _awaitingNext = false;
+    final old = _playingController;
+    if (!mounted) {
+      await controller.dispose();
+      return;
+    }
+    setState(() => _playingController = controller);
+    await old?.dispose();
+    await controller.play();
+    controller.addListener(() => _onTick(controller));
+    // Doble buffer: dispara la precarga del siguiente YA, mientras este
+    // recién arranca — así, cuando termine, el reemplazo es inmediato.
+    _fillPreloadSlot();
+  }
+
+  void _onTick(VideoPlayerController controller) {
+    // Listener de un controller que ya dejó de ser el activo (reemplazado
+    // antes de que se le pudiera remover el listener) — ignorar.
+    if (controller != _playingController) return;
+    final value = controller.value;
+    if (value.position >= value.duration && !value.isPlaying) {
+      _advance();
+    }
+  }
+
+  void _advance() {
+    if (_preloadingController != null) {
+      unawaited(_promotePreload());
+    } else if (_queue.isNotEmpty) {
+      // Hay segmentos en cola pero ninguno se había empezado a precargar
+      // (llegaron varios de golpe mientras el slot de precarga ya estaba
+      // ocupado). _awaitingNext ANTES de _fillPreloadSlot() es lo que hace
+      // que, apenas termine de inicializar, se promueva solo — si no,
+      // quedaría preparado pero nadie lo reproduciría nunca.
+      _awaitingNext = true;
+      _fillPreloadSlot();
+    } else {
+      // Nada listo todavía: red más lenta que la duración del segmento. Se
+      // mantiene el último frame en pantalla (sin pantalla negra) hasta que
+      // llegue el próximo segmento — _enqueue -> _fillPreloadSlot lo promueve
+      // apenas esté listo, gracias a _awaitingNext.
+      _awaitingNext = true;
     }
   }
 
   @override
   void dispose() {
+    _disposed = true;
     if (_channel != null) supabase.removeChannel(_channel!);
-    _controller?.dispose();
+    _playingController?.dispose();
+    _preloadingController?.dispose();
     super.dispose();
   }
 
@@ -148,10 +237,11 @@ class _LiveStreamViewerState extends State<LiveStreamViewer> {
             child: Stack(
               alignment: Alignment.center,
               children: [
-                if (_controller != null && _controller!.value.isInitialized)
+                if (_playingController != null &&
+                    _playingController!.value.isInitialized)
                   AspectRatio(
-                    aspectRatio: _controller!.value.aspectRatio,
-                    child: VideoPlayer(_controller!),
+                    aspectRatio: _playingController!.value.aspectRatio,
+                    child: VideoPlayer(_playingController!),
                   )
                 else
                   const CircularProgressIndicator(color: Colors.white54),
diff --git a/lib/state/live_broadcast_provider.dart b/lib/state/live_broadcast_provider.dart
index c186c1d..a5fba0f 100644
--- a/lib/state/live_broadcast_provider.dart
+++ b/lib/state/live_broadcast_provider.dart
@@ -12,10 +12,20 @@ import 'recorder_controller.dart';
 
 part 'live_broadcast_provider.g.dart';
 
-// Subido a 2s (desde 1.5s): el encoder de video de CameraX necesita un
-// margen real tras startVideoRecording() antes de poder recibir un nuevo
-// stopVideoRecording() sin crashear — ver la nota en _captureAndSend.
-const segmentDuration = Duration(milliseconds: 2000);
+// Subido a 4s (desde 2s, que ya venía de 1.5s): cada rotateSegment() implica
+// stopVideoRecording() + startVideoRecording() en el MISMO CameraController
+// (un solo encoder de hardware — no hay forma de grabar sin ese corte real
+// con este plugin, ver la nota extensa en recorder_controller.dart). Esa
+// transición es la única fuente real de discontinuidad de la grabación en
+// sí; duplicar la duración del segmento la reduce a la mitad de frecuencia
+// sin tocar su costo individual, y como el encoder de CameraX necesitaba
+// MÁS margen tras startVideoRecording() antes de aceptar el próximo stop
+// (motivo del bump anterior de 1.5s a 2s), alargar el intervalo es
+// estrictamente más seguro en esa misma dirección, nunca menos. El buffer
+// doble del visor (ver live_stream_viewer.dart) ya elimina la pausa de
+// carga entre clips recibidos — este cambio ataca la otra mitad del
+// problema: cuántas veces por minuto ocurre el corte real de cámara.
+const segmentDuration = Duration(milliseconds: 4000);
 
 class LiveBroadcastState {
   final bool live;
@@ -53,6 +63,16 @@ class LiveBroadcast extends _$LiveBroadcast {
   // subida lenta bloquee el siguiente corte de cámara — ver la nota en
   // _captureAndSend sobre por qué esto se separó del guard de captura.
   Future<void> _uploadChain = Future.value();
+  // Con red lenta, la grabación sigue cortando segmentos cada segmentDuration
+  // aunque la subida de los anteriores no haya terminado — sin este límite,
+  // los archivos .mp4 temporales de cada segmento (y la cola de Futures
+  // encadenados) crecerían sin techo durante todo el SOS. Al tope, se
+  // descarta el segmento más nuevo (se borra su archivo) en vez de acumular:
+  // la grabación de evidencia (RecorderController) no se ve afectada, solo
+  // se pierde ese clip puntual de la transmisión en vivo.
+  int _pendingUploads = 0;
+  static const _maxPendingUploads = 3;
+  static const _uploadTimeout = Duration(seconds: 15);
 
   @override
   LiveBroadcastState build() {
@@ -128,39 +148,75 @@ class LiveBroadcast extends _$LiveBroadcast {
       );
       return;
     }
-    if (_channel == null) return;
+    // A partir de acá cualquier salida temprana debe borrar el archivo del
+    // segmento — de lo contrario queda huérfano en el almacenamiento
+    // temporal para siempre (nunca se sube ni se libera).
+    if (_channel == null) {
+      unawaited(_discardSegmentFile(file));
+      return;
+    }
+    if (_pendingUploads >= _maxPendingUploads) {
+      // Red más lenta que la cadencia de segmentos: en vez de acumular
+      // subidas pendientes (y sus archivos temporales) indefinidamente, se
+      // descarta este segmento — la grabación de evidencia sigue intacta,
+      // solo se salta un clip de la transmisión en vivo.
+      debugPrint(
+        '[LiveBroadcast] cola de subida saturada ($_pendingUploads) — se descarta segmento seq=$_seq',
+      );
+      unawaited(_discardSegmentFile(file));
+      return;
+    }
     final seq = _seq++;
     final capturedFile = file;
+    _pendingUploads++;
     // Encadenado (no unawaited) para preservar el orden de seq al mandar el
     // broadcast, aunque una subida sea más lenta que la siguiente.
     _uploadChain = _uploadChain.then((_) async {
       try {
-        final url = await _repo.uploadSegment(
-          file: capturedFile,
-          alertId: alertId,
-          seq: seq,
-        );
+        final url = await _repo
+            .uploadSegment(file: capturedFile, alertId: alertId, seq: seq)
+            .timeout(_uploadTimeout);
         debugPrint('[LiveBroadcast] segmento $seq subido: $url');
         if (_channel == null) return;
-        await _repo.sendSegment(
-          _channel!,
-          VideoSegmentPayload(
-            url: url,
-            seq: seq,
-            ts: DateTime.now().millisecondsSinceEpoch,
-          ),
-        );
+        await _repo
+            .sendSegment(
+              _channel!,
+              VideoSegmentPayload(
+                url: url,
+                seq: seq,
+                ts: DateTime.now().millisecondsSinceEpoch,
+              ),
+            )
+            .timeout(_uploadTimeout);
         debugPrint('[LiveBroadcast] segmento $seq transmitido por broadcast');
         state = state.copyWith(segmentsSent: seq + 1);
       } catch (e, st) {
+        // Red lenta/caída a mitad de subida: se registra el error y se
+        // continúa con el siguiente segmento — nunca se bloquea ni se
+        // reintenta este mismo clip indefinidamente.
         debugPrint('[LiveBroadcast] ERROR en segmento $seq: $e\n$st');
         state = state.copyWith(
           error: 'live_broadcastFailed'.tr(namedArgs: {'e': '$e'}),
         );
+      } finally {
+        _pendingUploads--;
+        await _discardSegmentFile(capturedFile);
       }
     });
   }
 
+  // Borra el archivo temporal de un segmento ya procesado (subido, fallido o
+  // descartado por saturación) — sin esto, cada segmento cortado por
+  // rotateSegment() (uno cada segmentDuration mientras dura la transmisión)
+  // quedaría en el almacenamiento temporal del dispositivo para siempre.
+  Future<void> _discardSegmentFile(File file) async {
+    try {
+      await file.delete();
+    } catch (_) {
+      /* ya no existía o el filesystem no lo permitió — no es crítico */
+    }
+  }
+
   Future<void> stop() async {
     if (!state.live) return;
     _timer?.cancel();
-- 
2.43.0

