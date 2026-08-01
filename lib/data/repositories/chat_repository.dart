import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/env.dart';
import '../supabase_client.dart';

// Puerto de la llamada fetch('/api/chat') en medic-tab.tsx — la clave de
// Anthropic y el system prompt viven solo en el backend Next.js
// (app/api/chat/route.ts), este cliente solo reenvía el historial.
class ChatRepository {
  Future<String> sendMessage(List<Map<String, String>> messages) async {
    final token = supabase.auth.currentSession?.accessToken;
    final res = await http.post(
      Uri.parse('${Env.apiBaseUrl}/api/chat/'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'messages': messages}),
    );
    if (res.statusCode != 200) {
      throw Exception('Error al contactar el asistente (${res.statusCode})');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['content'] as String? ?? '';
  }
}
