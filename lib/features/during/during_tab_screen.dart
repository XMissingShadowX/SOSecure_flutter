import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/location_provider.dart';
import '../../state/sos_provider.dart';

// Puerto mínimo de components/tabs/during-tab.tsx para la Fase 2: estado de grabación
// activa e historial reciente de ubicación. La UX completa de cola offline llega en la
// Fase 3. El panel completo de SOS activo (con la grabación en vivo) lo maneja
// SosButton — este tab solo resume el estado cuando el usuario navega aquí.
class DuringTabScreen extends ConsumerWidget {
  const DuringTabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sos = ref.watch(sosProvider);
    final location = ref.watch(locationWatcherProvider);

    if (!sos.active) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No hay ninguna alerta SOS activa.\nMantén presionado el botón SOS para activar una.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: Icon(Icons.circle, color: Theme.of(context).colorScheme.error, size: 14),
            title: const Text('SOS activo'),
            subtitle: Text(sos.alert != null ? 'Alerta #${sos.alert!.id.substring(0, 8)}' : 'Creando alerta...'),
          ),
        ),
        if (location.hasCoordinates)
          Card(
            child: ListTile(
              leading: const Icon(Icons.my_location),
              title: const Text('Ubicación actual'),
              subtitle: Text('${location.latitude!.toStringAsFixed(6)}, ${location.longitude!.toStringAsFixed(6)}'),
            ),
          ),
        if (sos.contactsNotified.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Contactos notificados', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: sos.contactsNotified.map((n) => Chip(label: Text(n))).toList(),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
