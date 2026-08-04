import '../../domain/models/emergency_contact.dart';
import '../supabase_client.dart';

// Espeja home-tab.tsx: nunca lee/escribe la tabla emergency_contacts directo (el teléfono
// va cifrado con pgcrypto y RLS de SELECT/INSERT/UPDATE está eliminada en esa tabla). Todo
// pasa por las 3 RPCs SECURITY DEFINER — la clave AES nunca llega al cliente en ningún caso.
class ContactsRepository {
  Future<List<EmergencyContact>> getMyContacts() async {
    final data = await supabase.rpc('get_my_contacts');
    return (data as List)
        .map((e) => EmergencyContact.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<EmergencyContact> addContact({
    required String name,
    required String phone,
    String? email,
    String? relationship,
    required int priority,
    required String importance,
  }) async {
    final data = await supabase.rpc(
      'add_emergency_contact',
      params: {
        'p_name': name,
        'p_phone': phone,
        'p_email': email,
        'p_relationship': relationship,
        'p_priority': priority,
        'p_importance': importance,
      },
    );
    return EmergencyContact.fromJson(data as Map<String, dynamic>);
  }

  Future<EmergencyContact> updateContact({
    required String id,
    required String name,
    required String phone,
    String? email,
    String? relationship,
    required String importance,
  }) async {
    final data = await supabase.rpc(
      'update_emergency_contact',
      params: {
        'p_id': id,
        'p_name': name,
        'p_phone': phone,
        'p_email': email,
        'p_relationship': relationship,
        'p_importance': importance,
      },
    );
    return EmergencyContact.fromJson(data as Map<String, dynamic>);
  }

  // Borrar no requiere descifrar — sí sigue permitido directo sobre la tabla
  // (política RLS "owner_delete" activa, ver CLAUDE.md).
  Future<void> deleteContact(String id) async {
    await supabase.from('emergency_contacts').delete().eq('id', id);
  }
}
