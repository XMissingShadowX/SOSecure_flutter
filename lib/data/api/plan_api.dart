import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart' as http;

import '../../core/env.dart';
import '../supabase_client.dart';

// Espeja app/api/premium/cancel, app/api/family/cancel y app/api/delete-account:
// mismo patrón que PinApi — pasa el access token de Supabase como Authorization
// Bearer, esas rutas ya soportan ese header además de cookies (ver
// lib/supabase/server.ts::getAuthedUser en el proyecto web).
// La barra final NO es opcional: next.config.ts del proyecto web tiene
// `trailingSlash: true`, así que una URL sin ella devuelve un 308 hacia la
// versión con barra. Ese redirect deja el POST sin cuerpo y responde HTML
// ("Redirecting..."), que revienta al hacer jsonDecode. Mismo motivo por el
// que pin_api.dart y chat_repository.dart ya las llevan.
class PlanApi {
  Future<Map<String, String>> _authHeaders() async {
    final token = supabase.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Pide a la web la URL de pago de la pasarela y la devuelve.
  ///
  /// Antes la app abría la *página* del checkout (`/plan-premium/pago`) en el
  /// navegador externo, que no comparte la sesión de Supabase con la app —
  /// el usuario tenía que volver a iniciar sesión ahí solo para llegar a la
  /// pasarela. Llamando la API con el Bearer que ya tenemos, obtenemos el
  /// `init_point` de Mercado Pago / el `approve` link de PayPal y abrimos ese
  /// directamente, saltándonos el login.
  ///
  /// [provider] es 'mercadopago' o 'paypal' — mismos valores que acepta la web.
  Future<String> startCheckout({
    required bool family,
    required String provider,
  }) async {
    final path = family ? '/api/family/checkout/' : '/api/premium/checkout/';
    final res = await http.post(
      Uri.parse('${Env.apiBaseUrl}$path'),
      headers: await _authHeaders(),
      body: jsonEncode({'action': 'create-session', 'provider': provider}),
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>?;
    if (res.statusCode != 200) {
      throw Exception(
        body?['error'] ??
            'plan_checkoutError'.tr(namedArgs: {'code': '${res.statusCode}'}),
      );
    }
    final url = body?['url'] as String?;
    if (url == null || url.isEmpty) {
      throw Exception('plan_checkoutError'.tr(namedArgs: {'code': 'url'}));
    }
    return url;
  }

  /// Invita a un correo al plan familiar del usuario actual. Espeja
  /// POST /api/family/invite (un solo elemento en `members`, la app invita de
  /// a uno en vez del batch que soporta la web). Lanza si el correo es
  /// inválido, si ya se llegó al límite de 5, o si la fila individual falló.
  Future<void> inviteFamilyMember({required String email, String? name}) async {
    final res = await http.post(
      Uri.parse('${Env.apiBaseUrl}/api/family/invite/'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'members': [
          {'email': email, if (name != null && name.isNotEmpty) 'name': name},
        ],
      }),
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>?;
    if (res.statusCode != 200) {
      throw Exception(
        body?['error'] ??
            'family_inviteError'.tr(),
      );
    }
    final results = body?['results'] as List?;
    final result = results?.isNotEmpty == true
        ? results!.first as Map<String, dynamic>
        : null;
    if (result == null || result['ok'] != true) {
      throw Exception(result?['reason'] ?? 'family_inviteError'.tr());
    }
  }

  /// Vincula la cuenta actual a un grupo familiar por su token de invitación.
  /// Espeja POST /api/family/accept. Devuelve el nombre del grupo al que se
  /// unió, para el mensaje de bienvenida.
  Future<String> acceptFamilyInvite(String token) async {
    final res = await http.post(
      Uri.parse('${Env.apiBaseUrl}/api/family/accept/'),
      headers: await _authHeaders(),
      body: jsonEncode({'token': token}),
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>?;
    if (res.statusCode != 200) {
      throw Exception(body?['error'] ?? 'family_joinInvalidToken'.tr());
    }
    return body?['group_name'] as String? ?? 'Plan Familiar';
  }

  Future<void> cancelPremium() async {
    final res = await http.post(
      Uri.parse('${Env.apiBaseUrl}/api/premium/cancel/'),
      headers: await _authHeaders(),
    );
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>?;
      throw Exception(
        body?['error'] ??
            'plan_cancelError'.tr(namedArgs: {'code': '${res.statusCode}'}),
      );
    }
  }

  Future<void> cancelFamily() async {
    final res = await http.post(
      Uri.parse('${Env.apiBaseUrl}/api/family/cancel/'),
      headers: await _authHeaders(),
    );
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>?;
      throw Exception(
        body?['error'] ??
            'plan_cancelError'.tr(namedArgs: {'code': '${res.statusCode}'}),
      );
    }
  }

  Future<void> deleteAccount() async {
    final res = await http.post(
      Uri.parse('${Env.apiBaseUrl}/api/delete-account/'),
      headers: await _authHeaders(),
    );
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>?;
      throw Exception(
        body?['error'] ??
            'plan_deleteAccountApiError'.tr(
              namedArgs: {'code': '${res.statusCode}'},
            ),
      );
    }
  }
}
