import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_client.dart';

// Puerto de lib/live-stream.ts. La web transmite chunks WebM crudos por el
// canal broadcast de Supabase Realtime (MediaRecorder + MediaSource en el
// receptor); `camera` no expone un equivalente a MediaRecorder.ondataavailable
// ni el receptor tiene MediaSource, así que aquí se transmiten CLIPS
// COMPLETOS Y CORTOS (~1.5s, mp4) subidos a Storage — el canal solo pasa la
// URL firmada, no el binario. Mayor latencia por segmento (~1-2s vs ~0.3-0.8s
// en la web) pero cada clip es decodificable por sí solo, sin necesitar
// MediaSource. El evento `video_segment` es nuevo — el receptor de la web
// (LiveStreamViewer / app/emergency/[alertId]) también fue actualizado para
// entenderlo, ver ese lado del repo.
String liveChannelName(String alertId) => 'live-sos-$alertId';

class LiveStatusPayload {
  final bool live;
  final int ts;
  const LiveStatusPayload({required this.live, required this.ts});

  Map<String, dynamic> toJson() => {'live': live, 'ts': ts, 'mode': 'segment'};
}

class VideoSegmentPayload {
  final String url;
  final int seq;
  final int ts;
  const VideoSegmentPayload({
    required this.url,
    required this.seq,
    required this.ts,
  });

  Map<String, dynamic> toJson() => {'url': url, 'seq': seq, 'ts': ts};

  factory VideoSegmentPayload.fromJson(Map<String, dynamic> json) {
    return VideoSegmentPayload(
      url: json['url'] as String,
      seq: json['seq'] as int,
      ts: json['ts'] as int,
    );
  }
}

class LiveStreamRepository {
  RealtimeChannel channel(String alertId) =>
      supabase.channel(liveChannelName(alertId));

  Future<void> sendStatus(RealtimeChannel channel, {required bool live}) async {
    await channel.sendBroadcastMessage(
      event: 'status',
      payload: LiveStatusPayload(
        live: live,
        ts: DateTime.now().millisecondsSinceEpoch,
      ).toJson(),
    );
  }

  Future<void> sendSegment(
    RealtimeChannel channel,
    VideoSegmentPayload payload,
  ) async {
    await channel.sendBroadcastMessage(
      event: 'video_segment',
      payload: payload.toJson(),
    );
  }

  // Sube un segmento al mismo bucket `recordings` (privado) usado por las
  // grabaciones normales, bajo una carpeta `live/` separada, y devuelve una
  // URL firmada de corta duración — suficiente para que el receptor la
  // reproduzca casi de inmediato, sin dejar el clip accesible para siempre.
  Future<String> uploadSegment({
    required File file,
    required String alertId,
    required int seq,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('No autenticado');
    final bytes = await file.readAsBytes();
    // El primer segmento de la ruta DEBE ser el user.id — la política RLS
    // "storage recordings: owner insert" exige
    // (storage.foldername(name))[1] = auth.uid(). Con 'live/' primero (como
    // estaba antes) el INSERT fallaba por RLS en silencio: uploadSegment()
    // lanzaba, el catch de _captureAndSend lo atrapaba, y nunca se mandaba
    // ningún video_segment — el visor se quedaba esperando para siempre.
    final path = '${user.id}/live/$alertId/$seq.mp4';
    await supabase.storage
        .from('recordings')
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'video/mp4',
            upsert: true,
          ),
        );
    return supabase.storage.from('recordings').createSignedUrl(path, 600);
  }
}
