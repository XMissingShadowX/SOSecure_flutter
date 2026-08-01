import 'package:latlong2/latlong.dart';

// Puerto de RouteInfo/RouteGeometry (route-map.tsx) + RouteOption (lib/types.ts).
class RouteOption {
  final String id; // 'safest' | 'fastest' | 'alternate' | 'route-N'
  final String name;
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final SafetyScore safetyScore;
  final int incidentsOnRoute;

  const RouteOption({
    required this.id,
    required this.name,
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.safetyScore,
    required this.incidentsOnRoute,
  });

  String get distanceLabel => distanceMeters >= 1000
      ? '${(distanceMeters / 1000).toStringAsFixed(1)} km'
      : '${distanceMeters.round()} m';

  String get durationLabel {
    if (durationSeconds >= 3600) {
      final h = (durationSeconds / 3600).floor();
      final m = ((durationSeconds % 3600) / 60).floor();
      return '${h}h $m min';
    }
    return '${(durationSeconds / 60).floor()} min';
  }
}

// Puerto de SafetyScore (lib/types.ts) + calculateSafetyScore() (routes-tab.tsx).
class SafetyScore {
  final int score;
  final int incidentsNearby;
  final String riskLevel; // 'safe' | 'caution' | 'danger'

  const SafetyScore({
    required this.score,
    required this.incidentsNearby,
    required this.riskLevel,
  });
}

SafetyScore calculateSafetyScore({
  required double destLat,
  required double destLng,
  required List<({double latitude, double longitude, String severity})>
  incidents,
}) {
  final nearby = incidents.where((i) {
    return (i.latitude - destLat).abs() < 0.01 &&
        (i.longitude - destLng).abs() < 0.01;
  }).toList();

  final high = nearby.where((i) => i.severity == 'high').length;
  final medium = nearby.where((i) => i.severity == 'medium').length;
  final low = nearby.where((i) => i.severity == 'low').length;

  var score = 100;
  score -= high * 25;
  score -= medium * 10;
  score -= low * 5;
  score = score.clamp(0, 100);

  final riskLevel = score < 50 ? 'danger' : (score < 75 ? 'caution' : 'safe');
  return SafetyScore(
    score: score,
    incidentsNearby: nearby.length,
    riskLevel: riskLevel,
  );
}
