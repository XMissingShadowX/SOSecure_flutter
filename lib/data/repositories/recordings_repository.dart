import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../supabase_client.dart';

const _uuid = Uuid();

// Puerto de lib/recordings.ts — mismos límites que el bucket Storage `recordings`
// (allowlist a nivel Postgres, la barrera real). Esto solo rechaza temprano en el
// cliente para no gastar ancho de banda subiendo algo que el bucket va a rechazar.
const int maxRecordingSizeBytes = 50 * 1024 * 1024; // 50 MB
const List<String> allowedRecordingMimeTypes = [
  'audio/webm',
  'video/webm',
  'audio/mp4',
  'video/mp4',
  'audio/ogg',
  // El paquete `camera` puede producir .mov (QuickTime) en iOS — confirmado en el spike
  // de Fase 2 que Android produce mp4 (ver notas del RecorderController). Si iOS resulta
  // inevitablemente .mov, agregar 'video/quicktime' aquí Y en el allowlist del bucket
  // (Postgres) antes de portar la Fase 2 a iOS — no asumido todavía, solo Android probado.
];

class RecordingValidationException implements Exception {
  final String message;
  RecordingValidationException(this.message);
  @override
  String toString() => message;
}

void validateRecordingFile(File file, String mimeType, int sizeBytes) {
  final baseMime = mimeType.split(';').first.trim();
  if (!allowedRecordingMimeTypes.contains(baseMime)) {
    throw RecordingValidationException('Tipo de archivo no permitido: $baseMime');
  }
  if (sizeBytes > maxRecordingSizeBytes) {
    throw RecordingValidationException(
      'El archivo excede el tamaño máximo de ${maxRecordingSizeBytes ~/ (1024 * 1024)} MB',
    );
  }
}

class RecordingsRepository {
  // Sube la grabación final de una alerta SOS y crea el registro en `recordings`,
  // enlazándolo a la alerta vía `sos_alert_id` — puerto de saveRecordingToCloud()
  // en sos-button.tsx.
  Future<void> uploadSosRecording({
    required File file,
    required String mimeType,
    required int durationMs,
    required double? latitude,
    required double? longitude,
    required String sosAlertId,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('No autenticado');

    final bytes = await file.readAsBytes();
    validateRecordingFile(file, mimeType, bytes.length);

    final ext = mimeType.contains('mp4') ? 'mp4' : (mimeType.contains('quicktime') ? 'mov' : 'webm');
    final recId = _uuid.v4();
    final path = '${user.id}/$recId.$ext';

    await supabase.storage.from('recordings').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );

    await supabase.from('recordings').insert({
      'id': recId,
      'user_id': user.id,
      'storage_path': path,
      'recording_type': 'video',
      'mime_type': mimeType,
      'duration_ms': durationMs,
      'file_size_bytes': bytes.length,
      'latitude': latitude,
      'longitude': longitude,
      'sos_alert_id': sosAlertId,
    });

    // `video_url` guarda el storage_path (bucket privado) — igual que la web, la página
    // pública pide una URL firmada fresca en cada visita vía /api/emergency/[id]/video.
    await supabase.from('sos_alerts').update({'video_url': path}).eq('id', sosAlertId);
  }

  // Puerto de uploadRecordingToDB() en lib/recordings.ts — grabación libre desde
  // during-tab.dart, sin ligar a ninguna alerta SOS (sos_alert_id queda null).
  // Devuelve la URL firmada recién creada para compartir de inmediato.
  Future<String?> uploadStandaloneRecording({
    required File file,
    required String recordingType, // 'audio' | 'video'
    required String mimeType,
    required int durationMs,
    required double? latitude,
    required double? longitude,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('No autenticado');

    final bytes = await file.readAsBytes();
    validateRecordingFile(file, mimeType, bytes.length);

    final ext = mimeType.contains('mp4') ? (recordingType == 'audio' ? 'm4a' : 'mp4') : 'webm';
    final recId = _uuid.v4();
    final path = '${user.id}/$recId.$ext';

    await supabase.storage.from('recordings').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );

    await supabase.from('recordings').insert({
      'id': recId,
      'user_id': user.id,
      'storage_path': path,
      'recording_type': recordingType,
      'mime_type': mimeType,
      'duration_ms': durationMs,
      'file_size_bytes': bytes.length,
      'latitude': latitude,
      'longitude': longitude,
    });

    try {
      return await supabase.storage.from('recordings').createSignedUrl(path, 3600);
    } catch (_) {
      return null;
    }
  }

  // Puerto de la carga de grabaciones en after-tab.tsx. A diferencia de la web (que
  // confía en la columna `public_url` guardada en su momento), acá se genera una URL
  // firmada fresca en cada listado — funciona sin importar si el bucket es público o
  // privado, y no se rompe si la URL guardada expiró.
  Future<List<StoredRecording>> listMyRecordings({int limit = 20}) async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];
    final data = await supabase
        .from('recordings')
        .select('id, recording_type, storage_path, duration_ms, created_at, latitude, longitude')
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .limit(limit) as List;

    final recordings = <StoredRecording>[];
    for (final row in data) {
      final map = row as Map<String, dynamic>;
      final path = map['storage_path'] as String;
      String? url;
      try {
        url = await supabase.storage.from('recordings').createSignedUrl(path, 3600);
      } catch (_) {
        url = null;
      }
      recordings.add(StoredRecording(
        id: map['id'] as String,
        recordingType: map['recording_type'] as String,
        storagePath: path,
        signedUrl: url,
        durationMs: map['duration_ms'] as int? ?? 0,
        createdAt: DateTime.parse(map['created_at'] as String),
        latitude: (map['latitude'] as num?)?.toDouble(),
        longitude: (map['longitude'] as num?)?.toDouble(),
      ));
    }
    return recordings;
  }

  // Puerto de la consulta de video vinculado a una alerta en la vista de
  // detalle de after-tab.tsx (equivalente a /api/emergency/[id]/video, pero
  // consumido directo desde el cliente autenticado en vez de una ruta pública).
  Future<StoredRecording?> getRecordingForAlert(String alertId) async {
    final data = await supabase
        .from('recordings')
        .select('id, recording_type, storage_path, duration_ms, created_at, latitude, longitude')
        .eq('sos_alert_id', alertId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (data == null) return null;
    final path = data['storage_path'] as String;
    String? url;
    try {
      url = await supabase.storage.from('recordings').createSignedUrl(path, 3600);
    } catch (_) {
      url = null;
    }
    return StoredRecording(
      id: data['id'] as String,
      recordingType: data['recording_type'] as String,
      storagePath: path,
      signedUrl: url,
      durationMs: data['duration_ms'] as int? ?? 0,
      createdAt: DateTime.parse(data['created_at'] as String),
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
    );
  }

  Future<void> deleteRecording(StoredRecording rec) async {
    await supabase.storage.from('recordings').remove([rec.storagePath]);
    await supabase.from('recordings').delete().eq('id', rec.id);
  }
}

class StoredRecording {
  final String id;
  final String recordingType; // 'audio' | 'video'
  final String storagePath;
  final String? signedUrl;
  final int durationMs;
  final DateTime createdAt;
  final double? latitude;
  final double? longitude;

  StoredRecording({
    required this.id,
    required this.recordingType,
    required this.storagePath,
    required this.signedUrl,
    required this.durationMs,
    required this.createdAt,
    required this.latitude,
    required this.longitude,
  });
}
