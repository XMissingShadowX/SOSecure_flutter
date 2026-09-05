import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../supabase_client.dart';

// Espeja app/api/pin/*: todo el hasheo/verificación del PIN vive server-side (bcrypt).
// Este cliente solo pasa el access token de Supabase como Authorization Bearer — las
// rutas Next.js ya validan sesión con supabase.auth.getUser() del lado del servidor.
class PinApi {
  // Restaurar la sesión persistida es síncrono, pero si el access token ya venció
  // (JWT de ~1h), Supabase la refresca en segundo plano y ese refresh NO se espera
  // en initSupabase(). Sin este chequeo, PinLockScreen dispara getConfig()/verify()
  // en initState() con el token viejo y el backend responde 401 antes de que el
  // refresh en segundo plano termine — ver CLAUDE.md/plan: "401 al iniciar la app".
  Future<Session?> _ensureFreshSession() async {
    final session = supabase.auth.currentSession;
    if (session == null) return null;
    final expiresAt = session.expiresAt;
    if (expiresAt == null) return session;
    final expiry = DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000);
    if (DateTime.now().isBefore(expiry.subtract(const Duration(seconds: 30)))) {
      return session;
    }
    try {
      final result = await supabase.auth.refreshSession();
      return result.session ?? session;
    } catch (_) {
      return session;
    }
  }

  Future<Map<String, String>> _authHeaders() async {
    final session = await _ensureFreshSession();
    final token = session?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // Reintenta una sola vez con sesión refrescada si el servidor igual devuelve 401
  // (ej. el refresh proactivo de arriba falló silenciosamente, o el reloj del
  // dispositivo está desfasado). Evita mostrar el error 401 al usuario cuando basta
  // con un refresh de sesión para resolverlo.
  Future<http.Response> _withRetry(
    Future<http.Response> Function(Map<String, String> headers) request,
  ) async {
    var res = await request(await _authHeaders());
    if (res.statusCode == 401) {
      try {
        final result = await supabase.auth.refreshSession();
        if (result.session != null) {
          res = await request({
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${result.session!.accessToken}',
          });
        }
      } catch (_) {
        // Sin sesión recuperable — se deja el 401 original, el caller lo reporta.
      }
    }
    return res;
  }

  // Namespaced por user id: sin esto, el último estado cacheado de un usuario
  // (ej. "PIN desactivado") podría colarse para otra cuenta que inicia sesión
  // sin red en el mismo dispositivo, saltándose un PIN que sí tiene activado
  // — sería un bypass de seguridad real, no solo un bug cosmético.
  String _cacheKey(String userId, String field) => 'pin_cache_${userId}_$field';

  Future<void> _cacheConfig(PinConfig config) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cacheKey(userId, 'enabled'), config.pinEnabled);
    await prefs.setBool(_cacheKey(userId, 'configured'), config.pinConfigured);
    await prefs.setInt(_cacheKey(userId, 'timeout'), config.pinTimeoutMinutes);
  }

  Future<PinConfig?> _readCachedConfig() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return null;
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_cacheKey(userId, 'enabled'));
    // null significa que nunca se guardó nada para este usuario — no hay
    // fallback posible, hay que dejar que el error original se propague.
    if (enabled == null) return null;
    return PinConfig(
      pinEnabled: enabled,
      pinConfigured: prefs.getBool(_cacheKey(userId, 'configured')) ?? false,
      pinTimeoutMinutes: prefs.getInt(_cacheKey(userId, 'timeout')) ?? 5,
      fromCache: true,
    );
  }

  // Fallback offline: si la llamada de red falla (sin internet, DNS, timeout —
  // no un 4xx/5xx real del servidor, que sigue siendo un error duro), se usa
  // el último estado de PIN conocido guardado localmente. Esto es seguro
  // porque solo cambia qué tan rápido se entera la app de que el PIN sigue
  // desactivado (deja pasar antes en vez de bloquear a un usuario sin PIN por
  // no tener señal) — nunca permite saltarse la verificación de un PIN que sí
  // está activo, porque esa verificación (bcrypt.compare) vive solo en el
  // servidor y sigue exigiendo red en PinApi.verify().
  Future<PinConfig> getConfig() async {
    try {
      final res = await _withRetry(
        (headers) => http.get(
          Uri.parse('${Env.apiBaseUrl}/api/pin/'),
          headers: headers,
        ),
      );
      if (res.statusCode != 200) {
        throw Exception(
          'pin_readConfigError'.tr(
            namedArgs: {'code': '${res.statusCode}', 'body': res.body},
          ),
        );
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final config = PinConfig(
        pinEnabled: body['pin_enabled'] as bool? ?? false,
        pinConfigured: body['pin_configured'] as bool? ?? false,
        pinTimeoutMinutes: body['pin_timeout_minutes'] as int? ?? 5,
      );
      unawaited(_cacheConfig(config));
      return config;
    } catch (e) {
      final cached = await _readCachedConfig();
      if (cached != null) return cached;
      rethrow;
    }
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
        'pin_saveConfigError'.tr(
          namedArgs: {'code': '${res.statusCode}', 'body': res.body},
        ),
      );
    }
  }

  // Devuelve ok=true si el PIN es correcto, o el status 429 con Retry-After si hay lockout.
  Future<PinVerifyResult> verify(String pin) async {
    final res = await _withRetry(
      (headers) => http.post(
        Uri.parse('${Env.apiBaseUrl}/api/pin/verify/'),
        headers: headers,
        body: jsonEncode({'pin': pin}),
      ),
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
  // true si vino del fallback local (sin red) en vez de la respuesta real del
  // servidor — ver PinApi.getConfig(). PinLockScreen lo usa para avisar al
  // usuario que el estado del PIN es el último conocido, no confirmado ahora.
  final bool fromCache;

  PinConfig({
    required this.pinEnabled,
    required this.pinConfigured,
    required this.pinTimeoutMinutes,
    this.fromCache = false,
  });
}

class PinVerifyResult {
  final bool ok;
  final int? lockedOutSeconds;

  PinVerifyResult({required this.ok, this.lockedOutSeconds});
}
