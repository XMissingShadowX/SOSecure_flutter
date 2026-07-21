import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/supabase_client.dart';

part 'auth_provider.g.dart';

// Expone el stream de auth de Supabase como estado observable — cualquier pantalla puede
// reaccionar a login/logout sin volver a consultar manualmente.
@riverpod
Stream<AuthState> authStateChanges(Ref ref) {
  return supabase.auth.onAuthStateChange;
}

@riverpod
User? currentUser(Ref ref) {
  final auth = ref.watch(authStateChangesProvider);
  return auth.valueOrNull?.session?.user ?? supabase.auth.currentUser;
}
