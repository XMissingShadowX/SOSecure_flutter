import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
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
    final path = family ? '/api/family/checkout' : '/api/premium/checkout';
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

  Future<void> cancelPremium() async {
    final res = await http.post(
      Uri.parse('${Env.apiBaseUrl}/api/premium/cancel'),
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
      Uri.parse('${Env.apiBaseUrl}/api/family/cancel'),
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
      Uri.parse('${Env.apiBaseUrl}/api/delete-account'),
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
