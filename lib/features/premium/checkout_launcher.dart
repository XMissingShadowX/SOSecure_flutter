import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/env.dart';
import '../../data/api/plan_api.dart';

// Punto único para arrancar el pago de un plan desde la app.
//
// El problema que resuelve: Mercado Pago y PayPal son flujos de navegador, así
// que la app siempre tuvo que salir a `launchUrl`. Pero abría la *página* del
// checkout en el sitio web, y ese navegador externo no comparte la sesión de
// Supabase con la app — el usuario aterrizaba en una pantalla de login antes
// de poder pagar.
//
// Ahora la app pide la URL de la pasarela a la API con su propio token
// (`PlanApi.startCheckout`) y abre esa URL directamente. Si algo falla —
// backend viejo sin soporte de Bearer, sin red, respuesta inesperada — se cae
// al comportamiento anterior (abrir la página web) en vez de dejar al usuario
// sin forma de pagar.

/// Rutas de la página de pago en el sitio web, usadas solo como respaldo.
const premiumCheckoutPath = '/plan-premium/pago';
const familyCheckoutPath = '/plan-familiar';

Future<bool> _launch(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// Pregunta con qué pasarela quiere pagar. Devuelve 'mercadopago', 'paypal',
/// o null si el usuario cerró el diálogo.
Future<String?> _askProvider(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              'plan_chooseProvider'.tr(),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('Mercado Pago'),
            onTap: () => Navigator.pop(sheetContext, 'mercadopago'),
          ),
          ListTile(
            leading: const Icon(Icons.payment_outlined),
            title: const Text('PayPal'),
            onTap: () => Navigator.pop(sheetContext, 'paypal'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Abre el pago del plan familiar ([family] true) o del premium ([family]
/// false). No lanza: cualquier error termina en el respaldo web o en un
/// SnackBar.
Future<void> openCheckout(BuildContext context, {required bool family}) async {
  final fallbackUri = Uri.parse(
    '${Env.apiBaseUrl}${family ? familyCheckoutPath : premiumCheckoutPath}',
  );

  final provider = await _askProvider(context);
  if (provider == null) return; // el usuario canceló
  if (!context.mounted) return;

  try {
    final url = await PlanApi().startCheckout(
      family: family,
      provider: provider,
    );
    final opened = await _launch(Uri.parse(url));
    if (opened) return;
  } catch (_) {
    // cae al respaldo de abajo
  }

  // Respaldo: la página web de siempre (pedirá iniciar sesión, pero funciona).
  final opened = await _launch(fallbackUri);
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('premium_ctaOpenFailed'.tr())));
  }
}
