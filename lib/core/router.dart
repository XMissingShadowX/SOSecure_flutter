import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../data/supabase_client.dart';
import '../features/onboarding/login_screen.dart';
import '../features/onboarding/permission_gate_screen.dart';
import '../features/onboarding/sign_up_screen.dart';
import '../features/onboarding/sign_up_success_screen.dart';
import '../features/pin/pin_lock_screen.dart';
import '../features/shell/app_shell_screen.dart';
import '../features/shell/settings_screen.dart';

// Instancia única, creada una sola vez — nunca llamar a buildRouter() dentro de un build()
// de widget: si SosecureApp lo hiciera en cada rebuild (ej. al cambiar el tema), se crearía
// un GoRouter nuevo cada vez, perdiendo el estado de navegación y reiniciando en
// initialLocation ('/permission-gate') aunque el usuario ya estuviera en el shell.
final GoRouter appRouter = buildRouter();

// Guard simple: sin sesión Supabase -> /login. Con sesión -> permission-gate decide si
// pasa a pin-lock, y pin-lock decide si pasa al shell. Espeja el orden de app/page.tsx:
// auth -> permisos -> PIN -> contenido.
GoRouter buildRouter() {
  return GoRouter(
    // Siempre arranca por el gate de permisos/PIN, nunca directo al shell — el PIN debe
    // volver a pedirse en cada apertura de la app (fail-closed, ver pin-lock-screen.dart).
    initialLocation: '/permission-gate',
    redirect: (context, state) {
      final loggedIn = supabase.auth.currentSession != null;
      final loggingInRoute =
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/sign-up' ||
          state.matchedLocation == '/sign-up-success';

      if (!loggedIn && !loggingInRoute) return '/login';
      if (loggedIn && loggingInRoute) return '/permission-gate';
      return null;
    },
    refreshListenable: GoRouterRefreshStream(supabase.auth.onAuthStateChange),
    routes: [
      GoRoute(path: '/', builder: (context, state) => const AppShellScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/sign-up',
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(
        path: '/sign-up-success',
        builder: (context, state) => const SignUpSuccessScreen(),
      ),
      GoRoute(
        path: '/permission-gate',
        builder: (context, state) => const PermissionGateScreen(),
      ),
      GoRoute(
        path: '/pin-lock',
        builder: (context, state) => const PinLockScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
}

// go_router necesita un Listenable para refrescar el redirect cuando cambia el estado
// de auth — envuelve el Stream de Supabase.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
