import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/env.dart';
import '../supabase_client.dart';

// Espeja app/api/premium/cancel, app/api/family/cancel y app/api/delete-account:
// mismo patrón que PinApi — pasa el access token de Supabase como Authorization
// Bearer, esas rutas ya soportan ese header además de cookies (ver
// lib/supabase/server.ts::getAuthedUser en el proyecto web).
class PlanApi {
  Future<Map<String, String>> _authHeaders() async {
    final token = supabase.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> cancelPremium() async {
    final res = await http.post(
      Uri.parse('${Env.apiBaseUrl}/api/premium/cancel'),
      headers: await _authHeaders(),
    );
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>?;
      throw Exception(body?['error'] ?? 'No se pudo cancelar (${res.statusCode})');
    }
  }

  Future<void> cancelFamily() async {
    final res = await http.post(
      Uri.parse('${Env.apiBaseUrl}/api/family/cancel'),
      headers: await _authHeaders(),
    );
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>?;
      throw Exception(body?['error'] ?? 'No se pudo cancelar (${res.statusCode})');
    }
  }

  Future<void> deleteAccount() async {
    final res = await http.post(
      Uri.parse('${Env.apiBaseUrl}/api/delete-account'),
      headers: await _authHeaders(),
    );
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>?;
      throw Exception(body?['error'] ?? 'No se pudo eliminar la cuenta (${res.statusCode})');
    }
  }
}
