import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/offline_queue_provider.dart';
import '../../state/volume_sos_provider.dart';
import '../after/after_tab_screen.dart';
import '../before/before_tab_screen.dart';
import '../during/during_tab_screen.dart';
import '../during/sos_button.dart';
import '../home/home_tab_screen.dart';
import '../medic/medic_tab_screen.dart';

// Puerto de components/app-shell.tsx + bottom-navigation.tsx. Un solo AppBar para las 5
// tabs (con el acceso a Ajustes) en vez de uno por tab. El watcher único de geolocalización
// vive en location_provider.dart (Fase 1). El SOSButton se superpone a las 5 tabs vía
// Stack, igual que en la web (fixed sobre toda la app, no solo sobre during-tab).
class AppShellScreen extends ConsumerStatefulWidget {
  const AppShellScreen({super.key});

  @override
  ConsumerState<AppShellScreen> createState() => _AppShellScreenState();
}

class _AppShellScreenState extends ConsumerState<AppShellScreen> {
  int _index = 0;

  static const _titles = ['Inicio', 'Antes', 'Durante', 'Después', 'Apoyo'];

  static const _tabs = [
    HomeTabScreen(),
    BeforeTabScreen(),
    DuringTabScreen(),
    AfterTabScreen(),
    MedicTabScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final pendingCount = ref.watch(offlineQueueProvider).length;
    // Mantiene VolumeSos vivo (keepAlive) desde que arranca el shell, escuchando
    // en toda la app salvo mientras hay un SOS activo — igual que useVolumeSOS
    // montado globalmente en app-shell.tsx.
    ref.watch(volumeSosProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          // Espeja el badge de header_sync en app-shell.tsx — cuántos elementos
          // (alertas SOS, en esta fase) están esperando reconexión para subirse.
          if (pendingCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Chip(
                  avatar: const Icon(Icons.cloud_off, size: 16),
                  label: Text('$pendingCount pendiente${pendingCount > 1 ? 's' : ''}'),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Ajustes',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: Stack(
        children: [
          IndexedStack(index: _index, children: _tabs),
          const SosButton(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Inicio'),
          NavigationDestination(icon: Icon(Icons.route_outlined), selectedIcon: Icon(Icons.route), label: 'Antes'),
          NavigationDestination(icon: Icon(Icons.videocam_outlined), selectedIcon: Icon(Icons.videocam), label: 'Durante'),
          NavigationDestination(icon: Icon(Icons.history_outlined), selectedIcon: Icon(Icons.history), label: 'Después'),
          NavigationDestination(icon: Icon(Icons.favorite_outline), selectedIcon: Icon(Icons.favorite), label: 'Apoyo'),
        ],
      ),
    );
  }
}
