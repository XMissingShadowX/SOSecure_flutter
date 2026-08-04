import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/env.dart';
import '../supabase_client.dart';

// Espeja app/api/pin/*: todo el hasheo/verificación del PIN vive server-side (bcrypt).
// Este cliente solo pasa el access token de Supabase como Authorization Bearer — las
// rutas Next.js ya validan sesión con supabase.auth.getUser() del lado del servidor.
class PinApi {
  Future<Map<String, String>> _authHeaders() async {
    final token = supabase.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<PinConfig> getConfig() async {
    final res = await http.get(
      Uri.parse('${Env.apiBaseUrl}/api/pin/'),
      headers: await _authHeaders(),
    );
    if (res.statusCode != 200) {
      throw Exception(
        'No se pudo leer la configuración del PIN (${res.statusCode}): ${res.body}',
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return PinConfig(
      pinEnabled: body['pin_enabled'] as bool? ?? false,
      pinConfigured: body['pin_configured'] as bool? ?? false,
      pinTimeoutMinutes: body['pin_timeout_minutes'] as int? ?? 5,
    );
  }

  Future<void> savePin({
    String? pin,
    bool? pinEnabled,
    int? pinTimeoutMinutes,
  }) async {
    final res = await http.post(
      Uri.parse('${Env.apiBaseUrl}/api/pin/'),
      headers: await _authHeaders(),
      body: jsonEncode({
        if (pin != null) 'pin': pin,
        if (pinEnabled != null) 'pin_enabled': pinEnabled,
        if (pinTimeoutMinutes != null) 'pin_timeout_minutes': pinTimeoutMinutes,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception(
        'No se pudo guardar el PIN (${res.statusCode}): ${res.body}',
      );
    }
  }

  // Devuelve ok=true si el PIN es correcto, o el status 429 con Retry-After si hay lockout.
  Future<PinVerifyResult> verify(String pin) async {
    final res = await http.post(
      Uri.parse('${Env.apiBaseUrl}/api/pin/verify/'),
      headers: await _authHeaders(),
      body: jsonEncode({'pin': pin}),
    );
    if (res.statusCode == 429) {
      final retryAfter = int.tryParse(res.headers['retry-after'] ?? '') ?? 60;
      return PinVerifyResult(ok: false, lockedOutSeconds: retryAfter);
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return PinVerifyResult(ok: body['ok'] as bool? ?? false);
  }

  // Solicita el reset — no borra el PIN todavía, manda un Magic Link. El borrado real
  // ocurre en /api/pin/finalize-reset cuando el usuario abre el link.
  Future<void> requestReset() async {
    await http.delete(
      Uri.parse('${Env.apiBaseUrl}/api/pin/'),
      headers: await _authHeaders(),
    );
  }
}

class PinConfig {
  final bool pinEnabled;
  final bool pinConfigured;
  final int pinTimeoutMinutes;

  PinConfig({
    required this.pinEnabled,
    required this.pinConfigured,
    required this.pinTimeoutMinutes,
  });
}

class PinVerifyResult {
  final bool ok;
  final int? lockedOutSeconds;

  PinVerifyResult({required this.ok, this.lockedOutSeconds});
}
