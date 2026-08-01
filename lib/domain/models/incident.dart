import 'incident_type.dart';

// Puerto de Incident (lib/types.ts).
class Incident {
  final String id;
  final String? userId;
  final String title;
  final String? description;
  final String incidentType;
  final IncidentSeverity severity;
  final double latitude;
  final double longitude;
  final bool isActive;
  final DateTime reportedAt;

  const Incident({
    required this.id,
    required this.userId,
    required this.title,
    required this.description,
    required this.incidentType,
    required this.severity,
    required this.latitude,
    required this.longitude,
    required this.isActive,
    required this.reportedAt,
  });

  factory Incident.fromJson(Map<String, dynamic> json) {
    return Incident(
      id: json['id'] as String,
      userId: json['user_id'] as String?,
      title: json['title'] as String,
      description: json['description'] as String?,
      incidentType: json['incident_type'] as String,
      severity: json['severity'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      isActive: json['is_active'] as bool? ?? true,
      reportedAt: DateTime.parse(json['reported_at'] as String),
    );
  }
}
