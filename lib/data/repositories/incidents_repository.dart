import '../../domain/models/incident.dart';
import '../../domain/models/incident_type.dart';
import '../supabase_client.dart';

// Puerto de reportIncident() en during-tab.tsx, más loadIncidents()/reportIncident()/
// saveEdit()/handleDelete() de map-tab.tsx.
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
  Future<List<DangerZone>> getNearbyDangerZones({
    required double latitude,
    required double longitude,
    double radiusDegrees = 0.05,
  }) async {
    final data =
        await supabase
                .from('incidents')
                .select('latitude, longitude')
                .eq('severity', 'high')
                .gte('latitude', latitude - radiusDegrees)
                .lte('latitude', latitude + radiusDegrees)
                .gte('longitude', longitude - radiusDegrees)
                .lte('longitude', longitude + radiusDegrees)
            as List;

    final zones = <DangerZone>[];
    for (final row in data) {
      final map = row as Map<String, dynamic>;
      final lat = (map['latitude'] as num).toDouble();
      final lng = (map['longitude'] as num).toDouble();
      final existing = zones.where(
        (z) =>
            (z.latitude - lat).abs() < 0.005 &&
            (z.longitude - lng).abs() < 0.005,
      );
      if (existing.isNotEmpty) {
        existing.first.count++;
      } else {
        zones.add(DangerZone(latitude: lat, longitude: lng, count: 1));
      }
    }
    return zones;
  }

  // Puerto de loadIncidents() en map-tab.tsx.
  Future<List<Incident>> listActive() async {
    final data =
        await supabase
                .from('incidents')
                .select('*')
                .eq('is_active', true)
                .order('reported_at', ascending: false)
                .limit(100)
            as List;
    return data
        .map((row) => Incident.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  // Puerto del insert completo de reportIncident() en map-tab.tsx (a diferencia
  // del de during-tab.tsx: aquí sí devuelve la fila creada, para poder
  // notificar a usuarios cercanos con el id real).
  Future<Incident> reportFull({
    required String title,
    String? description,
    required String incidentType,
    required IncidentSeverity severity,
    required double latitude,
    required double longitude,
  }) async {
    final user = supabase.auth.currentUser;
    final row = await supabase
        .from('incidents')
        .insert({
          'user_id': user?.id,
          'title': title,
          'description': description,
          'incident_type': incidentType,
          'severity': severity,
          'latitude': latitude,
          'longitude': longitude,
        })
        .select()
        .single();
    final incident = Incident.fromJson(row);
    try {
      await supabase.functions.invoke(
        'notify-nearby-users',
        body: {
          'incident_id': incident.id,
          'incident_lat': latitude,
          'incident_lng': longitude,
          'title': title,
          'severity': severity,
        },
      );
    } catch (_) {
      // La notificación es best-effort — el incidente ya se guardó igual.
    }
    return incident;
  }

  Future<void> updateIncident({
    required String id,
    required String title,
    String? description,
    required String incidentType,
    required IncidentSeverity severity,
  }) async {
    await supabase
        .from('incidents')
        .update({
          'title': title,
          'description': description,
          'incident_type': incidentType,
          'severity': severity,
        })
        .eq('id', id);
  }

  Future<void> deleteIncident(String id) async {
    await supabase.from('incidents').delete().eq('id', id);
  }

  Future<bool> isAdmin(String userId) async {
    final result = await supabase.rpc('is_admin', params: {'uid': userId});
    return result as bool? ?? false;
  }
}

class DangerZone {
  final double latitude;
  final double longitude;
  int count;
  DangerZone({
    required this.latitude,
    required this.longitude,
    required this.count,
  });
}
