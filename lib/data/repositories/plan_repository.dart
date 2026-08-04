import '../supabase_client.dart';

// Espeja lib/premium.ts y lib/family.ts del proyecto web: lecturas directas
// vía el cliente Supabase con RLS (mismo backend, mismas tablas). Cancelar sí
// requiere las rutas Next.js (llaman a Mercado Pago/PayPal), ver plan_api.dart.

class PremiumSubscription {
  final String status;
  const PremiumSubscription({required this.status});

  bool get isActive => status == 'active';

  factory PremiumSubscription.fromJson(Map<String, dynamic> json) =>
      PremiumSubscription(status: json['status'] as String? ?? 'pending');
}

class FamilyGroup {
  final String status;
  final String role; // 'owner' o 'member', resuelto por quién llamó
  const FamilyGroup({required this.status, required this.role});

  bool get isActive => status == 'active';

  factory FamilyGroup.fromJson(Map<String, dynamic> json, {required String role}) =>
      FamilyGroup(status: json['status'] as String? ?? 'pending', role: role);
}

class PlanRepository {
  Future<PremiumSubscription?> getPremiumSubscription() async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;
    final data = await supabase
        .from('premium_subscriptions')
        .select('status')
        .eq('user_id', user.id)
        .maybeSingle();
    if (data == null) return null;
    return PremiumSubscription.fromJson(data);
  }

  // Devuelve el grupo familiar relevante para el usuario actual: primero
  // busca si es dueño, si no, si es miembro activo — igual que la web
  // resuelve getOwnedGroup() / getMemberGroup() por separado y decide cuál
  // mostrar en la UI.
  Future<FamilyGroup?> getFamilyGroup() async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;

    final owned = await supabase
        .from('family_groups')
        .select('status')
        .eq('owner_id', user.id)
        .maybeSingle();
    if (owned != null) return FamilyGroup.fromJson(owned, role: 'owner');

    final member = await supabase
        .from('family_members')
        .select('status, family_groups!inner(status)')
        .eq('user_id', user.id)
        .eq('status', 'active')
        .maybeSingle();
    if (member == null) return null;
    final group = member['family_groups'] as Map<String, dynamic>?;
    if (group == null) return null;
    return FamilyGroup.fromJson(group, role: 'member');
  }
}
