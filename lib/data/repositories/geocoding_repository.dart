import 'dart:convert';

import 'package:http/http.dart' as http;

// Puerto de reverseGeocode() en during-tab.tsx. Header User-Agent personalizado
// requerido — Photon rechaza el user agent por defecto del cliente HTTP de Dart
// con 403 (mismo problema ya resuelto para el autocompletado de home-tab en Fase 1).
class GeocodingRepository {
  final _cache = <String, String>{};

  Future<String> reverseGeocode(double lat, double lng) async {
    final key = '${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}';
    if (_cache.containsKey(key)) return _cache[key]!;

    try {
      final res = await http.get(
        Uri.parse('https://photon.komoot.io/reverse?lat=$lat&lon=$lng&limit=1'),
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14) SOSecureFlutter/1.0',
        },
      );
      if (res.statusCode != 200) throw Exception('photon error');
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final features = data['features'] as List?;
      if (features == null || features.isEmpty) return _fallback(lat, lng);

      final props =
          (features.first as Map<String, dynamic>)['properties']
              as Map<String, dynamic>? ??
          {};
      final street = (props['street'] ?? props['name'] ?? '') as String;
      final number = (props['housenumber'] ?? '') as String;
      final district = (props['district'] ?? props['suburb'] ?? '') as String;
      final city =
          (props['city'] ?? props['town'] ?? props['village'] ?? '') as String;

      String result;
      if (street.isNotEmpty) {
        final parts = [
          street + (number.isNotEmpty ? ' $number' : ''),
          district.isNotEmpty ? district : city,
        ].where((p) => p.isNotEmpty).toList();
        result = parts.join(', ');
      } else {
        final name = props['name'] as String?;
        result = [
          name,
          city,
        ].whereType<String>().where((p) => p.isNotEmpty).join(', ');
        if (result.isEmpty) result = _fallback(lat, lng);
      }
      _cache[key] = result;
      return result;
    } catch (_) {
      return _fallback(lat, lng);
    }
  }

  String _fallback(double lat, double lng) =>
      '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
}
