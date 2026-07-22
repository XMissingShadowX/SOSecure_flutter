import '../../domain/models/incident_type.dart';
import '../supabase_client.dart';

// Puerto de reportIncident() en during-tab.tsx.
class IncidentsRepository {
  Future<void> reportIncident({
    required IncidentType type,
    required String title,
    String? description,
    required IncidentSeverity severity,
    required double latitude,
    required double longitude,
  }) async {
    final user = supabase.auth.currentUser;
    await supabase.from('incidents').insert({
      'user_id': user?.id,
      'title': title,
      'description': description,
      'incident_type': type.value,
      'severity': severity,
      'latitude': latitude,
      'longitude': longitude,
    });
  }

  // Puerto de la agrupación de "zonas de peligro" en after-tab.tsx: incidentes
  // de severidad alta agrupados por cercanía (0.005° ≈ 500m, mismo umbral que
  // la web). A diferencia de la web (que reutiliza `nearbyIncidents` ya
  // cargado por el sistema de mapa, Fase 5 aún no construida), acá se
  // consulta directo por un cuadro delimitador simple alrededor de la
  // ubicación actual — suficiente para esta tarjeta sin depender del mapa.
  Future<List<DangerZone>> getNearbyDangerZones({required double latitude, required double longitude, double radiusDegrees = 0.05}) async {
    final data = await supabase
        .from('incidents')
        .select('latitude, longitude')
        .eq('severity', 'high')
        .gte('latitude', latitude - radiusDegrees)
        .lte('latitude', latitude + radiusDegrees)
        .gte('longitude', longitude - radiusDegrees)
        .lte('longitude', longitude + radiusDegrees) as List;

    final zones = <DangerZone>[];
    for (final row in data) {
      final map = row as Map<String, dynamic>;
      final lat = (map['latitude'] as num).toDouble();
      final lng = (map['longitude'] as num).toDouble();
      final existing = zones.where((z) => (z.latitude - lat).abs() < 0.005 && (z.longitude - lng).abs() < 0.005);
      if (existing.isNotEmpty) {
        existing.first.count++;
      } else {
        zones.add(DangerZone(latitude: lat, longitude: lng, count: 1));
      }
    }
    return zones;
  }
}

class DangerZone {
  final double latitude;
  final double longitude;
  int count;
  DangerZone({required this.latitude, required this.longitude, required this.count});
}
