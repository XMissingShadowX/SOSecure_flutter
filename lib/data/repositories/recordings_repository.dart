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
}
