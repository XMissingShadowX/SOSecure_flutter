import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'checkout_launcher.dart';

/// Abre la contratación de Premium en el navegador. Para muros de pago que no
/// usan [UpgradeButtons] porque no tienen espacio para un botón completo (la
/// pastilla sobre una ruta bloqueada, por ejemplo).
Future<void> openPremiumCheckout(BuildContext context) =>
    openCheckout(context, family: false);

// Los muros de pago que ve un usuario del plan gratuito (chat de apoyo,
// SOSecure AI, rutas alternativas, límite diario de búsquedas) explicaban la
// limitación pero no ofrecían salida: el usuario tenía que adivinar que la
// contratación estaba enterrada en Ajustes. Estos botones son esa salida —
// el primario abre el pago en el navegador, el secundario lleva a Ajustes,
// donde además está el Plan Familiar y el estado de la suscripción.
class UpgradeButtons extends StatelessWidget {
  const UpgradeButtons({
    super.key,
    this.family = false,
    this.dense = false,
  });

  /// true para contratar el Plan Familiar; false (por defecto) para el Premium.
  final bool family;

  /// Versión compacta (un solo botón, sin "Ver planes") para banners
  /// pequeños donde dos botones apilados no caben.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final upgrade = FilledButton.icon(
      onPressed: () => openCheckout(context, family: family),
      icon: const Icon(Icons.workspace_premium, size: 18),
      label: Text('premium_ctaUpgrade'.tr()),
    );

    if (dense) {
      return Align(alignment: Alignment.centerLeft, child: upgrade);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: double.infinity, child: upgrade),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.tune, size: 18),
            label: Text('premium_ctaSeePlans'.tr()),
          ),
        ),
      ],
    );
  }
}

// Muro de pago a pantalla completa: icono + título + explicación + botones.
// Lo comparten la pestaña de Apoyo y la conversación con SOSecure AI, que
// antes dibujaban cada una su propio bloque de texto suelto.
class PremiumGateCard extends StatelessWidget {
  const PremiumGateCard({
    super.key,
    required this.title,
    required this.description,
    this.icon = Icons.workspace_premium_outlined,
  });

  final String title;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              const UpgradeButtons(),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => openCheckout(context, family: true),
                child: Text('premium_ctaFamily'.tr()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
