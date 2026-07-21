// Espeja lib/types.ts EmergencyContact. El teléfono viaja cifrado en la tabla
// emergency_contacts — este modelo solo existe en memoria con el valor ya descifrado,
// devuelto por las RPCs SECURITY DEFINER (get_my_contacts/add/update). Nunca se lee ni
// escribe la tabla directo.
class EmergencyContact {
  final String id;
  final String name;
  final String phone;
  final String? email;
  final String? relationship;
  final String importance; // 'primary' | 'secondary' | 'tertiary'
  final int priority;

  EmergencyContact({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    this.relationship,
    required this.importance,
    required this.priority,
  });

  factory EmergencyContact.fromJson(Map<String, dynamic> json) {
    return EmergencyContact(
      id: json['id'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String,
      email: json['email'] as String?,
      relationship: json['relationship'] as String?,
      importance: json['importance'] as String? ?? 'secondary',
      priority: json['priority'] as int? ?? 0,
    );
  }

  EmergencyContact copyWith({
    String? name,
    String? phone,
    String? email,
    String? relationship,
    String? importance,
  }) {
    return EmergencyContact(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      relationship: relationship ?? this.relationship,
      importance: importance ?? this.importance,
      priority: priority,
    );
  }
}
