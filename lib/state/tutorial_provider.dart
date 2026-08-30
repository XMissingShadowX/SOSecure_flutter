import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/supabase_client.dart';

part 'tutorial_provider.g.dart';

const _hasSeenTutorialKeyPrefix = 'sosecure.hasSeenTutorial.';

// Flag namespaced por cuenta (no por dispositivo, a diferencia de SimpleMode en
// settings_provider.dart): "¿ya vio el tutorial?" es un hecho sobre una identidad, no
// una preferencia de dispositivo. Un flag global rompería el caso de un dispositivo
// compartido donde una cuenta existente cierra sesión y una cuenta nueva se registra —
// heredaría el estado "visto" de la cuenta anterior y nunca vería el tutorial.
//
// Default `true` (visto) cuando la clave nunca se escribió: cualquier instalación
// previa a este feature, cualquier usuario existente, cualquier reinstalación, falla
// cerrado y nunca ve el tutorial. El único lugar que escribe `false` es
// SignUpScreen._signUp(), en el momento exacto en que se crea la cuenta.
@Riverpod(keepAlive: true)
class TutorialSeen extends _$TutorialSeen {
  @override
  bool build() {
    _load();
    return true;
  }

  String? get _key {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return null;
    return '$_hasSeenTutorialKeyPrefix$userId';
  }

  Future<void> _load() async {
    final key = _key;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(key) ?? true;
  }

  // Usado por PinLockScreen justo antes de decidir a dónde navegar: este provider es
  // keepAlive y de vida larga, así que el `state` cacheado puede quedar desactualizado
  // si hubo un cambio de sesión (logout/login) desde que se construyó — relee siempre.
  Future<bool> refresh() async {
    await _load();
    return state;
  }

  // Llamado desde SignUpScreen._signUp() con el id explícito de AuthResponse.user, no
  // con el getter ambiente supabase.auth.currentUser — en la rama de confirmación por
  // correo todavía no hay sesión ambiente, así que ese getter sería null ahí.
  Future<void> markPendingForNewSignup(String userId) async {
    final key = '$_hasSeenTutorialKeyPrefix$userId';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, false);
    state = false;
  }

  Future<void> markSeen() async {
    final key = _key;
    if (key == null) return;
    state = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, true);
  }
}
