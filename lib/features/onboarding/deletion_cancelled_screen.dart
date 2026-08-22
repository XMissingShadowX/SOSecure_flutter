import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// Se llega aquí desde login_screen.dart cuando el login cancela un borrado
// de cuenta agendado (ver PlanApi.cancelScheduledDeletion). A propósito NO
// está en la lista `loggingInRoute` de router.dart — si lo estuviera, el
// redirect del router la sacaría de inmediato apenas detecta sesión activa,
// que es justo el estado en el que aterriza esta pantalla.
class DeletionCancelledScreen extends StatelessWidget {
  const DeletionCancelledScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'settings_deleteAccountCancelled'.tr(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => context.go('/'),
                  child: Text('settings_deleteAccountCancelledContinue'.tr()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
