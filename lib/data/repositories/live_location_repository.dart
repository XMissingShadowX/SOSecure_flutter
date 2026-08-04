import '../../domain/models/live_contact.dart';
import '../supabase_client.dart';

// Puerto de hooks/use-live-location.ts + la parte de broadcasting de
// app-shell.tsx. Todo por polling/upsert directo a `user_locations` —
// no hay Realtime en el diseño original.
class LiveLocationRepository {
  Future<void> broadcast({
    required String userId,
    required String displayName,
    required double latitude,
    required double longitude,
  }) async {
    await supabase.from('user_locations').upsert({
      'user_id': userId,
      'display_name': displayName,
      'latitude': latitude,
      'longitude': longitude,
      'updated_at': DateTime.now().toIso8601String(),
      'is_sharing': true,
    }, onConflict: 'user_id');
  }

  Future<void> stopSharing(String userId) async {
    await supabase
        .from('user_locations')
        .update({'is_sharing': false})
        .eq('user_id', userId);
  }

  // Resuelve contactos con email → user_id de SOSecure, vía la RPC
  // get_user_id_by_email (equivalente a hooks/use-contact-user-ids.ts).
  Future<Map<String, String>> resolveContactUserIds(List<String> emails) async {
    final result = <String, String>{};
    for (final email in emails) {
      final userId = await supabase.rpc(
        'get_user_id_by_email',
        params: {'p_email': email},
      );
      if (userId != null) result[email] = userId as String;
    }
    return result;
  }

  Future<List<LiveContact>> getContactLocations(
    List<String> contactUserIds,
  ) async {
    if (contactUserIds.isEmpty) return [];
    final data =
        await supabase
                .from('user_locations')
                .select('*')
                .inFilter('user_id', contactUserIds)
                .eq('is_sharing', true)
            as List;
    return data
        .map((e) => LiveContact.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
