import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/settings_provider.dart';

// Layout compartido por todos los pasos con contenido real del tutorial — calca el
// patrón ConstrainedBox(maxWidth: 400) + Column de permission_gate_screen.dart, para
// que título/subtítulo/espaciados sean consistentes sin duplicar el layout en cada paso.
//
// Lee simpleModeProvider una sola vez aquí (en vez de en cada step) para escalar
// título/subtítulo y el texto base del contenido — mismo criterio de accesibilidad que
// ya usa el resto de la app (ver NavigationBar en app_shell_screen.dart).
class TutorialStepFrame extends ConsumerWidget {
  const TutorialStepFrame({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final simpleMode = ref.watch(simpleModeProvider);
    final baseFontSize = simpleMode ? 17.0 : 14.0;

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: simpleMode ? 26 : 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    subtitle!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: baseFontSize,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                DefaultTextStyle.merge(
                  style: TextStyle(fontSize: baseFontSize),
                  child: child,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
