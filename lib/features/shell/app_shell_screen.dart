import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/brand.dart';
import '../../core/glass.dart';
import '../../core/theme.dart';
import '../../data/supabase_client.dart';
import '../../state/auth_provider.dart';
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

  // Espeja el `isOnline` de app-shell.tsx (useState + listeners window
  // online/offline). Vive como estado local del shell —igual que en la web—
  // en vez de como provider: solo el badge del header lo consume. La cola
  // offline tiene su propia suscripción porque necesita seguir viva aunque
  // el shell no esté montado (ver offline_queue_provider.dart).
  bool _isOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    Connectivity().checkConnectivity().then(_updateOnline);
    _connectivitySub = Connectivity().onConnectivityChanged.listen(
      _updateOnline,
    );
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  void _updateOnline(List<ConnectivityResult> results) {
    final online = !results.contains(ConnectivityResult.none);
    if (mounted && online != _isOnline) setState(() => _isOnline = online);
  }

  // Getter (no `final`/`static const`) para que cada build() de
  // AppShellScreen construya instancias NUEVAS de las 5 pantallas. Un widget
  // const (o una misma instancia reutilizada vía `final`) es tratado por
  // Flutter como "sin cambios" en `updateChild` (compara por identidad de
  // objeto) y salta por completo su reconstrucción — con la lista
  // cacheada en un `final`/`static const` aquí, TODO el contenido de las 5
  // pestañas quedaba congelado en el idioma con el que se montó la app la
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
    // Puerto de `<div className="min-h-screen bg-background ambient-bg">` en
    // app-shell.tsx: las manchas radiales van detrás de TODO (header y nav
    // incluidos), y esas dos superficies se vuelven translúcidas para dejarlas
    // ver — igual que `.glass-nav` sobre `.ambient-bg` en la web.
    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // Puerto del <header> de app-shell.tsx: marca (escudo + "SOSecure") a la
        // izquierda, badges de estado a su lado, y el menú de cuenta a la
        // derecha. NO lleva el nombre de la pestaña activa — de eso ya se encarga
        // la barra inferior, igual que en la web.
        appBar: AppBar(
          // h-14 (56px) + px-4 del header web.
          toolbarHeight: 56,
          titleSpacing: 16,
          // glass-nav: sin sombra ni tinte al hacer scroll; solo el borde inferior.
          backgroundColor: AppGlass.bgStrong(theme.brightness),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          shape: Border(bottom: BorderSide(color: theme.colorScheme.outline)),
          title: Row(
            children: [
              const SosecureLogo(size: 26),
              const SizedBox(width: 8),
              const Text(
                'SOSecure',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              // Los dos badges son excluyentes entre sí, igual que en la web: el
              // de sincronización solo tiene sentido con conexión (si no hay red,
              // la cola no se puede vaciar y lo relevante es "sin internet").
              if (!_isOnline) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: _HeaderBadge(
                    icon: Icons.wifi_off,
                    label: 'header_offline'.tr(),
                    color: AppColors.warning,
                  ),
                ),
              ] else if (pendingCount > 0) ...[
                const SizedBox(width: 8),
                // Cuántos elementos (alertas SOS, en esta fase) están esperando
                // reconexión para subirse.
                Flexible(
                  child: _HeaderBadge(
                    icon: Icons.notifications_active_outlined,
                    label: 'header_sync'.tr(namedArgs: {'n': '$pendingCount'}),
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            // Antes vivía como tarjeta fija en Home (_SafetyTipsCard) — quedaba
            // enterrada por scroll y solo visible en esa tab. Como botón junto al
            // de cuenta, los consejos quedan a un toque desde cualquier pestaña.
            // Respeta simpleMode igual que la tarjeta original (oculto ahí).
            if (!simpleMode) const _SafetyTipsButton(),
            const _AccountMenuButton(),
            const SizedBox(width: 4),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.2),
                      border: Border(
                        bottom: BorderSide(
                          color: AppColors.warning.withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.extension,
                          size: 14,
                          color: AppColors.warning,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'settings_simpleModeActive'.tr(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.warning,
                            ),
                          ),
                        ),
                      ],
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
              hideIdleButton:
                  _index == 4 || ref.watch(emergencyChatOpenProvider),
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
            // glass-strong en bottom-navigation.tsx.
            backgroundColor: AppGlass.bgStrong(theme.brightness),
            surfaceTintColor: Colors.transparent,
            elevation: 0,
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
      ),
    );
  }
}

// Pastilla de estado del header (sin internet / pendientes por sincronizar).
// Puerto de los dos <div> con bg-{color}/20 rounded-full de app-shell.tsx: el
// color lo define quien la usa y tiñe fondo, ícono y texto por igual.
class _HeaderBadge extends StatelessWidget {
  const _HeaderBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          // Flexible + ellipsis: en pantallas angostas el badge cede antes que
          // desbordar el AppBar (la marca "SOSecure" nunca se recorta).
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Botón de "Consejos de seguridad" en el header, junto al de cuenta. Antes
// era _SafetyTipsCard, una tarjeta fija en Home (home_tip1/2/3) — movida
// aquí para que quede accesible desde cualquier pestaña, no solo Home.
class _SafetyTipsButton extends StatelessWidget {
  const _SafetyTipsButton();

  List<String> _tips() => ['home_tip1'.tr(), 'home_tip2'.tr(), 'home_tip3'.tr()];

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.lightbulb_outline),
      tooltip: 'home_tips_title'.tr(),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) {
          final primary = Theme.of(context).colorScheme.primary;
          final tips = _tips();
          return AlertDialog(
            title: Text('home_tips_title'.tr()),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < tips.length; i++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: i < tips.length - 1 ? 10 : 0,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: primary.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              color: primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(tips[i])),
                      ],
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('close'.tr()),
              ),
            ],
          );
        },
      ),
    );
  }
}

// Puerto del DropdownMenu de UserCircle en app-shell.tsx: correo del usuario
// (solo informativo), Ajustes y Cerrar sesión. Sustituye al botón directo de
// Ajustes que tenía este header — cerrar sesión pasa de estar enterrado al
// final de la pantalla de Ajustes a quedar a dos toques, como en la web.
class _AccountMenuButton extends ConsumerWidget {
  const _AccountMenuButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final email = ref.watch(currentUserProvider)?.email;

    return PopupMenuButton<String>(
      icon: const Icon(Icons.account_circle_outlined),
      position: PopupMenuPosition.under,
      onSelected: (value) async {
        if (value == 'settings') {
          context.push('/settings');
        } else if (value == 'signout') {
          await supabase.auth.signOut();
          if (context.mounted) context.go('/login');
        }
      },
      itemBuilder: (context) => [
        if (email != null) ...[
          PopupMenuItem<String>(
            enabled: false,
            height: 36,
            child: Text(
              email,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const PopupMenuDivider(),
        ],
        PopupMenuItem<String>(
          value: 'settings',
          child: Row(
            children: [
              const Icon(Icons.settings_outlined, size: 18),
              const SizedBox(width: 12),
              Text('header_settings'.tr()),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'signout',
          child: Row(
            children: [
              const Icon(Icons.logout, size: 18),
              const SizedBox(width: 12),
              Text('header_signout'.tr()),
            ],
          ),
        ),
      ],
    );
  }
}
