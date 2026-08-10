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

// Servidor de rutas peatonales de FOSSGIS (la fundación alemana de
// OpenStreetMap). Es el único público con perfil a pie REAL y no pide API key.
const _footRouterBase = 'https://routing.openstreetmap.de/routed-foot';

// Respaldo si el de arriba no responde. Ojo: este solo tiene cargado el perfil
// de COCHE aunque se le pida /foot/ (ver la nota en fetchRoutes), así que su
// duración se descarta y se estima desde la distancia.
const _fallbackRouterBase = 'https://router.project-osrm.org';

// Velocidad de caminata para estimar la duración cuando se usa el respaldo
// (4.8 km/h, el promedio de un adulto).
const _walkingMetersPerSecond = 1.33;

class RoutesRepository {
  // [nearLatitude]/[nearLongitude] sesgan los resultados hacia esa posición.
  // Sin ellos Photon rankea a nivel mundial: buscar "farmacia" podía devolver
  // una en otro país antes que la de la esquina.
  Future<List<GeocodeResult>> searchPlaces(
    String query, {
    int limit = 5,
    double? nearLatitude,
    double? nearLongitude,
  }) async {
    final bias = (nearLatitude != null && nearLongitude != null)
        ? '&lat=$nearLatitude&lon=$nearLongitude'
        : '';
    final uri = Uri.parse(
      'https://photon.komoot.io/api/?q=${Uri.encodeComponent(query)}'
      '&limit=$limit$bias',
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

  // Rutas peatonales con alternativas. Devuelve hasta 3 rutas crudas (puntos +
  // distancia/duración) — el mapeo a RouteOption (nombre, puntaje de seguridad)
  // vive en routes_provider.dart.
  //
  // Antes esto apuntaba a router.project-osrm.org pidiendo /route/v1/foot/,
  // pero ese servidor público solo tiene cargado el perfil de COCHE e ignora el
  // que se pide en la URL. Comprobado pidiendo el mismo trayecto como
  // foot/walking/driving/bike/car: los cinco devuelven idéntico, ~43 km/h. Un
  // trayecto de 2.72 km se mostraba como 3.8 min cuando caminando son ~32.
  //
  // El servidor de FOSSGIS sí tiene perfil peatonal real: para ese mismo
  // trayecto devuelve 2.42 km en 32.3 min (4.5 km/h). Corrige tanto la duración
  // como la distancia, porque la ruta a pie puede usar andadores que la de
  // coche no (300 m menos en el caso medido).
  Future<
    List<({List<LatLng> points, double distanceMeters, double durationSeconds})>
  >
  fetchRoutes({required LatLng origin, required LatLng destination}) async {
    final coords =
        '${origin.longitude},${origin.latitude};'
        '${destination.longitude},${destination.latitude}';
    const query = '?overview=full&geometries=geojson&alternatives=true';

    try {
      return await _requestRoutes(
        '$_footRouterBase/route/v1/foot/$coords$query',
        estimateDuration: false,
      );
    } catch (_) {
      // Si el servidor peatonal no responde, se cae al otro para no dejar al
      // usuario sin ruta — pero descartando su duración de coche.
      return _requestRoutes(
        '$_fallbackRouterBase/route/v1/foot/$coords$query',
        estimateDuration: true,
      );
    }
  }

  Future<
    List<({List<LatLng> points, double distanceMeters, double durationSeconds})>
  >
  _requestRoutes(String url, {required bool estimateDuration}) async {
    final res = await http.get(
      Uri.parse(url),
      headers: {'User-Agent': _userAgent},
    );
    if (res.statusCode != 200) {
      throw Exception('OSRM error (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (data['code'] != 'Ok') throw Exception('OSRM: ${data['code']}');
    final routes = data['routes'] as List;
    return routes.map((r) {
      final points =
          ((r['geometry'] as Map<String, dynamic>)['coordinates'] as List)
              .map(
                (c) =>
                    LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
              )
              .toList();
      final distanceMeters = (r['distance'] as num).toDouble();
      return (
        points: points,
        distanceMeters: distanceMeters,
        durationSeconds: estimateDuration
            ? distanceMeters / _walkingMetersPerSecond
            : (r['duration'] as num).toDouble(),
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
