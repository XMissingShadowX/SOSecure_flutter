import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/supabase_client.dart';

part 'premium_provider.g.dart';

// Puerto de hooks/use-premium.ts — misma RPC SECURITY DEFINER, sin lógica extra
// en el cliente (el criterio de qué cuenta como premium/familiar vive en la BD).
@riverpod
class IsPremium extends _$IsPremium {
  @override
  Future<bool> build() async {
    final result = await supabase.rpc('has_premium_access');
    return result as bool? ?? false;
  }
}
