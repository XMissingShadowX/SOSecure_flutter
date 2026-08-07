import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/emergency_chat_provider.dart';
import '../../state/offline_queue_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/volume_sos_provider.dart';
import '../after/after_tab_screen.dart';
import '../before/before_tab_screen.dart';
import '../chat/emergency_chat_widget.dart';
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

  List<String> get _titles => [
    'nav_home'.tr(),
    'nav_before'.tr(),
    'nav_during'.tr(),
    'nav_after'.tr(),
    'nav_support'.tr(),
  ];

  // Getter (no `final`/`static const`) para que cada build() de
  // AppShellScreen construya instancias NUEVAS de las 5 pantallas. Un widget
  // const (o una misma instancia reutilizada vía `final`) es tratado por
  // Flutter como "sin cambios" en `updateChild` (compara por identidad de
  // objeto) y salta por completo su reconstrucción — con la lista
  // cacheada en un `final`/`static const` aquí, TODO el contenido de las 5
  // pestañas (no solo el título del AppBar, que sí usa un getter fresco en
  // _titles) quedaba congelado en el idioma con el que se montó la app la
  // primera vez, sin reaccionar a cambios de idioma posteriores — esto era
  // la causa raíz de la mayoría de los textos reportados como
  // "hardcodeados" en Home/Durante/Después/etc.
  List<Widget> get _tabs => [
    HomeTabScreen(),
    BeforeTabScreen(),
    DuringTabScreen(),
    AfterTabScreen(),
    MedicTabScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final pendingCount = ref.watch(offlineQueueProvider).length;
    final simpleMode = ref.watch(simpleModeProvider);
    // Mantiene VolumeSos vivo (keepAlive) desde que arranca el shell, escuchando
    // en toda la app salvo mientras hay un SOS activo — igual que useVolumeSOS
    // montado globalmente en app-shell.tsx.
    ref.watch(volumeSosProvider);

    final theme = Theme.of(context);
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
                  label: Text(
                    '$pendingCount pendiente${pendingCount > 1 ? 's' : ''}',
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'settings_title'.tr(),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Puerto del banner amarillo de app-shell.tsx (simpleMode && ...).
              if (simpleMode)
                Container(
                  width: double.infinity,
                  color: Colors.amber.withValues(alpha: 0.2),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'settings_simpleModeActive'.tr(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.amber,
                    ),
                  ),
                ),
              Expanded(
                // Puerto de className={cn('flex-1 overflow-y-auto', simpleMode && 'text-lg')}
                // — escala el texto base de todas las tabs ~12.5% (equivalente a
                // text-lg de Tailwind sobre el 1rem base) sin tocar cada widget.
                child: Theme(
                  data: simpleMode
                      ? theme.copyWith(
                          textTheme: theme.textTheme.apply(
                            fontSizeFactor: 1.125,
                          ),
                        )
                      : theme,
                  child: IndexedStack(index: _index, children: _tabs),
                ),
              ),
            ],
          ),
          // Puerto de EmergencyChat (chat de contactos + IA de emergencia,
          // Fase 6a) — antes del SosButton en el Stack para que el panel de
          // alerta activa (pantalla completa) lo tape automáticamente durante
          // un SOS en curso, igual que en la web.
          EmergencyChatWidget(),
          // Oculto en Apoyo (índice 4) o mientras el panel del chat de
          // contactos está abierto (su input queda en la misma esquina
          // inferior) — el panel de alerta activa igual se muestra si hay un
          // SOS en curso (ver SosButton.hideIdleButton).
          SosButton(
            hideIdleButton: _index == 4 || ref.watch(emergencyChatOpenProvider),
          ),
        ],
      ),
      bottomNavigationBar: Theme(
        // Puerto de bottom-navigation.tsx: barra e íconos más grandes en modo
        // simple (h-20 vs h-16, íconos w-7 h-7 vs w-5 h-5, label text-xs vs
        // text-[10px]) — NavigationBarThemeData es la única forma de tocar
        // tamaño de ícono/label sin reconstruir NavigationDestination a mano.
        data: theme.copyWith(
          navigationBarTheme: theme.navigationBarTheme.copyWith(
            height: simpleMode ? 80 : 64,
            iconTheme: WidgetStateProperty.resolveWith(
              (states) => IconThemeData(size: simpleMode ? 28 : 24),
            ),
            labelTextStyle: WidgetStateProperty.resolveWith(
              (states) => TextStyle(
                fontSize: simpleMode ? 13 : 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home),
              label: 'nav_home'.tr(),
            ),
            NavigationDestination(
              icon: const Icon(Icons.route_outlined),
              selectedIcon: const Icon(Icons.route),
              label: 'nav_before'.tr(),
            ),
            NavigationDestination(
              icon: const Icon(Icons.videocam_outlined),
              selectedIcon: const Icon(Icons.videocam),
              label: 'nav_during'.tr(),
            ),
            NavigationDestination(
              icon: const Icon(Icons.history_outlined),
              selectedIcon: const Icon(Icons.history),
              label: 'nav_after'.tr(),
            ),
            NavigationDestination(
              icon: const Icon(Icons.favorite_outline),
              selectedIcon: const Icon(Icons.favorite),
              label: 'nav_support'.tr(),
            ),
          ],
        ),
      ),
    );
  }
}
