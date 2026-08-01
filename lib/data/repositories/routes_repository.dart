import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../supabase_client.dart';

class GeocodeResult {
  final String displayName;
  final double latitude;
  final double longitude;
  const GeocodeResult({
    required this.displayName,
    required this.latitude,
    required this.longitude,
  });
}

// Puerto de la búsqueda de destino/origen con Photon (routes-tab.tsx) y el
// fetch de rutas con OSRM (route-map.tsx) — ambas APIs públicas, sin API key.
//
// Photon devuelve 403 si el header User-Agent es el default de Dart
// ("Dart/x.x (dart:io)") — a diferencia del navegador (que manda su propio
// UA), acá hay que declarar uno explícito o toda búsqueda falla en silencio
// (antes se interpretaba el 403 como "sin resultados", nunca como error real).
const _userAgent = 'SOSecure/1.0 (Flutter; contacto@sosecure.site)';

class RoutesRepository {
  Future<List<GeocodeResult>> searchPlaces(
    String query, {
    int limit = 5,
  }) async {
    final uri = Uri.parse(
      'https://photon.komoot.io/api/?q=${Uri.encodeComponent(query)}&limit=$limit',
    );
    final res = await http.get(
      uri,
      headers: {'Accept': 'application/json', 'User-Agent': _userAgent},
    );
    if (res.statusCode != 200) {
      throw Exception('Photon error (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final features = data['features'] as List? ?? [];
    return features.map((f) {
      final props = f['properties'] as Map<String, dynamic>;
      final coords =
          (f['geometry'] as Map<String, dynamic>)['coordinates'] as List;
      final parts = [
        props['name'],
        props['street'],
        props['city'],
        props['country'],
      ].where((p) => p != null && (p as String).isNotEmpty).join(', ');
      return GeocodeResult(
        displayName: parts.isEmpty ? query : parts,
        latitude: (coords[1] as num).toDouble(),
        longitude: (coords[0] as num).toDouble(),
      );
    }).toList();
  }

  // Puerto del fetch de OSRM (route-map.tsx): perfil peatonal, rutas alternativas.
  // Devuelve hasta 3 rutas crudas (puntos + distancia/duración) — el mapeo a
  // RouteOption (nombre, puntaje de seguridad) vive en routes_provider.dart.
  Future<
    List<({List<LatLng> points, double distanceMeters, double durationSeconds})>
  >
  fetchRoutes({required LatLng origin, required LatLng destination}) async {
    final uri = Uri.parse(
      'https://router.project-osrm.org/route/v1/foot/'
      '${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}'
      '?overview=full&geometries=geojson&alternatives=true',
    );
    final res = await http.get(uri, headers: {'User-Agent': _userAgent});
    if (res.statusCode != 200)
      throw Exception('OSRM error (${res.statusCode})');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (data['code'] != 'Ok') throw Exception('OSRM: ${data['code']}');
    final routes = data['routes'] as List;
    return routes.map((r) {
      final coords =
          ((r['geometry'] as Map<String, dynamic>)['coordinates'] as List)
              .map(
                (c) =>
                    LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
              )
              .toList();
      return (
        points: coords,
        distanceMeters: (r['distance'] as num).toDouble(),
        durationSeconds: (r['duration'] as num).toDouble(),
      );
    }).toList();
  }

  // Puerto de checkAndRecordSearch(): límite de 1 búsqueda/día para no-premium.
  Future<bool> checkAndRecordSearch({required bool isPremium}) async {
    if (isPremium) return true;
    final user = supabase.auth.currentUser;
    if (user == null) return true;
    final count = await supabase.rpc(
      'count_route_searches_today',
      params: {'p_user_id': user.id},
    );
    if ((count as int? ?? 0) >= 1) return false;
    await supabase.rpc('insert_route_search', params: {'p_user_id': user.id});
    return true;
  }
}
