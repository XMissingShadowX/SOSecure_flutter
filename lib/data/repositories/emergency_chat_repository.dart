import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart' as http;

import '../../core/env.dart';
import '../../domain/models/emergency_chat_message.dart';
import '../supabase_client.dart';

// Puerto de la persistencia de components/emergency-chat.tsx: chat_messages +
// chat_conversations (Supabase) y el asistente de IA vía /api/emergency-chat/.
// El streaming en vivo (LIVE_ID, LiveStreamViewer) queda fuera — ver Fase 6b.
class EmergencyChatRepository {
  Future<String?> resolveUserIdByEmail(String email) async {
    final result = await supabase.rpc(
      'get_user_id_by_email',
      params: {'p_email': email},
    );
    return result as String?;
  }

  Future<List<EmergencyChatMessage>> loadHistory(String myId) async {
    final data =
        await supabase
                .from('chat_messages')
                .select('*')
                .or('sender_id.eq.$myId,receiver_id.eq.$myId')
                .order('created_at', ascending: true)
                .limit(300)
            as List;
    return data
        .map(
          (row) =>
              EmergencyChatMessage.fromDb(row as Map<String, dynamic>, myId),
        )
        .toList();
  }

  Future<EmergencyChatMessage> sendMessage({
    required String myId,
    required String receiverId,
    required String content,
    String type = 'text',
  }) async {
    final row = await supabase
        .from('chat_messages')
        .insert({
          'sender_id': myId,
          'receiver_id': receiverId,
          'content': content,
          'type': type,
        })
        .select()
        .single();
    await _upsertConversation(myId, receiverId, content);
    return EmergencyChatMessage.fromDb(row, myId);
  }

  Future<void> _upsertConversation(
    String userId,
    String otherId,
    String lastMessage,
  ) async {
    final sorted = [userId, otherId]..sort();
    await supabase.from('chat_conversations').upsert({
      'user_a': sorted[0],
      'user_b': sorted[1],
      'last_message': lastMessage,
      'last_message_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_a,user_b');
  }

  Future<void> markRead({
    required String myId,
    required String senderId,
  }) async {
    await supabase
        .from('chat_messages')
        .update({'is_read': true})
        .eq('receiver_id', myId)
        .eq('sender_id', senderId)
        .eq('is_read', false);
  }

  // Puerto de useAIChat(): SOSecure AI, gateado a premium por la propia UI
  // (igual que la web), con la ubicación actual como contexto del sistema.
  Future<String> sendToAI({
    required List<Map<String, String>> history,
    double? latitude,
    double? longitude,
  }) async {
    final token = supabase.auth.currentSession?.accessToken;
    final res = await http.post(
      Uri.parse('${Env.apiBaseUrl}/api/emergency-chat/'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'messages': history,
        if (latitude != null && longitude != null)
          'location': {'latitude': latitude, 'longitude': longitude},
      }),
    );
    if (res.statusCode != 200) {
      throw Exception(
        'chat_assistantError'.tr(namedArgs: {'code': '${res.statusCode}'}),
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['content'] as String? ?? '';
  }
}
