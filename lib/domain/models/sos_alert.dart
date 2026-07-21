// Espeja la fila insertada/leída en la tabla sos_alerts (ver sos-button.tsx).
class SosAlert {
  final String id;
  final String userId;
  final double latitude;
  final double longitude;
  final String status; // 'active' | 'resolved' | 'false_alarm'
  final List<String> contactsNotified;

  SosAlert({
    required this.id,
    required this.userId,
    required this.latitude,
    required this.longitude,
    required this.status,
    required this.contactsNotified,
  });

  factory SosAlert.fromJson(Map<String, dynamic> json) {
    return SosAlert(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      status: json['status'] as String? ?? 'active',
      contactsNotified: (json['contacts_notified'] as List?)?.cast<String>() ?? const [],
    );
  }
}
