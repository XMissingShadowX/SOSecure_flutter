// Espeja LiveContact en hooks/use-live-location.ts.
class LiveContact {
  final String userId;
  final String displayName;
  final double latitude;
  final double longitude;
  final DateTime updatedAt;

  LiveContact({
    required this.userId,
    required this.displayName,
    required this.latitude,
    required this.longitude,
    required this.updatedAt,
  });

  factory LiveContact.fromJson(Map<String, dynamic> json) {
    return LiveContact(
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String? ?? 'Contacto',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
