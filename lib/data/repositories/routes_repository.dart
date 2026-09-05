import 'dart:convert';
import 'dart:math' as math;

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

// http.get no tiene timeout propio: sin esto, un servidor que acepta la
// conexión y no responde deja la pantalla cargando para siempre. Las respuestas
// medidas van de 200 a 1200 ms.
const _requestTimeout = Duration(seconds: 8);

class RoutesRepository {
  // Radios (km) que se intentan en orden, del más angosto al más ancho.
  // Bug real: `lat`/`lon`/`location_bias_scale` de Photon son solo una
  // sugerencia DÉBIL de ranking, no un filtro — para una palabra genérica
  // como "parque" casi nunca hay una coincidencia de texto fuerte cerca, así
  // que el filtro de distancia del lado cliente (por sobre esos resultados ya
  // limitados) siempre terminaba vacío y caía al fallback global, mostrando
  // "Parque, Lisboa" o "Parque Nacional de Doñana, España" para un usuario en
  // Querétaro. `bbox` sí es un filtro geográfico DURO en Photon — restringe
  // la búsqueda a esa caja desde el propio servidor, imitando el
  // "cerca primero, ensanchar solo si no hay nada" de Google Places.
  static const _searchRadiiKm = [30.0, 120.0, 400.0];
  // 1° de latitud ≈ 111 km siempre; 1° de longitud se encoge con el coseno de
  // la latitud (más angosto lejos del ecuador) — sin este ajuste la caja
  // sería demasiado angosta en longitud a latitudes altas.
  static const _kmPerDegreeLat = 111.0;

  // [nearLatitude]/[nearLongitude] acotan la búsqueda a esa zona (ver arriba).
  Future<List<GeocodeResult>> searchPlaces(
    String query, {
    int limit = 5,
    double? nearLatitude,
    double? nearLongitude,
  }) async {
    final hasNear = nearLatitude != null && nearLongitude != null;
    if (hasNear) {
      for (final radiusKm in _searchRadiiKm) {
        final results = await _queryPhoton(
          query,
          limit: limit,
          nearLatitude: nearLatitude,
          nearLongitude: nearLongitude,
          radiusKm: radiusKm,
        );
        if (results.isNotEmpty) return results;
      }
    }
    // Último recurso (o si no hay ubicación del usuario todavía): sin
    // restricción geográfica, para no dejar al usuario sin nada si de plano
    // no existe ningún resultado ni ensanchando el radio.
    return _queryPhoton(query, limit: limit);
  }

  Future<List<GeocodeResult>> _queryPhoton(
    String query, {
    required int limit,
    double? nearLatitude,
    double? nearLongitude,
    double? radiusKm,
  }) async {
    var extra = '';
    if (nearLatitude != null && nearLongitude != null) {
      extra = '&lat=$nearLatitude&lon=$nearLongitude&location_bias_scale=1.0';
      if (radiusKm != null) {
        final latDelta = radiusKm / _kmPerDegreeLat;
        final lonDelta =
            radiusKm /
            (_kmPerDegreeLat * math.cos(nearLatitude * math.pi / 180).abs().clamp(0.01, 1.0));
        final minLon = nearLongitude - lonDelta;
        final minLat = nearLatitude - latDelta;
        final maxLon = nearLongitude + lonDelta;
        final maxLat = nearLatitude + latDelta;
        extra += '&bbox=$minLon,$minLat,$maxLon,$maxLat';
      }
    }
    final uri = Uri.parse(
      'https://photon.komoot.io/api/?q=${Uri.encodeComponent(query)}'
      '&limit=$limit$extra',
    );
    final res = await http
        .get(
          uri,
          headers: {'Accept': 'application/json', 'User-Agent': _userAgent},
        )
        .timeout(_requestTimeout);
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
    final res = await http
        .get(Uri.parse(url), headers: {'User-Agent': _userAgent})
        .timeout(_requestTimeout);
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
