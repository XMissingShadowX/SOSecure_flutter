// Espeja lib/types.ts FrequentPlace. Nunca toca Supabase — igual que en la web
// (home-tab.tsx.addPlace), vive solo en el store local persistido.
class FrequentPlace {
  final String id;
  final String label;
  final String icon; // 'home' | 'work' | 'school' | 'gym' | 'other'
  final String address;
  final double latitude;
  final double longitude;

  FrequentPlace({
    required this.id,
    required this.label,
    required this.icon,
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  factory FrequentPlace.fromJson(Map<String, dynamic> json) {
    return FrequentPlace(
      id: json['id'] as String,
      label: json['label'] as String,
      icon: json['icon'] as String,
      address: json['address'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'icon': icon,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
      };
}
