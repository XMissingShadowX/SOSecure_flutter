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
  final String id;
  final String status;
  final String role; // 'owner' o 'member', resuelto por quién llamó
  const FamilyGroup({required this.id, required this.status, required this.role});

  bool get isActive => status == 'active';

  factory FamilyGroup.fromJson(Map<String, dynamic> json, {required String role}) =>
      FamilyGroup(
        id: json['id'] as String,
        status: json['status'] as String? ?? 'pending',
        role: role,
      );
}

// Espeja FamilyMember de lib/family.ts. 'invited' = ya se le mandó el correo
// pero aún no vincula su cuenta; 'active' = ya aceptó y usa el plan.
class FamilyMember {
  final String id;
  final String email;
  final String? name;
  final String role;
  final String status;
  const FamilyMember({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    required this.status,
  });

  bool get isOwner => role == 'owner';

  factory FamilyMember.fromJson(Map<String, dynamic> json) => FamilyMember(
    id: json['id'] as String,
    email: json['email'] as String? ?? '',
    name: json['name'] as String?,
    role: json['role'] as String? ?? 'member',
    status: json['status'] as String? ?? 'invited',
  );
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
        .select('id, status')
        .eq('owner_id', user.id)
        .maybeSingle();
    if (owned != null) return FamilyGroup.fromJson(owned, role: 'owner');

    final member = await supabase
        .from('family_members')
        .select('status, family_groups!inner(id, status)')
        .eq('user_id', user.id)
        .eq('status', 'active')
        .maybeSingle();
    if (member == null) return null;
    final group = member['family_groups'] as Map<String, dynamic>?;
    if (group == null) return null;
    return FamilyGroup.fromJson(group, role: 'member');
  }

  // Espeja listMembers() de lib/family.ts: RLS permite al dueño leer todas las
  // filas de su grupo directo con el cliente, sin pasar por una API route.
  Future<List<FamilyMember>> listFamilyMembers(String groupId) async {
    final data = await supabase
        .from('family_members')
        .select('*')
        .eq('group_id', groupId)
        .neq('status', 'removed')
        .order('invited_at', ascending: true);
    return (data as List)
        .map((m) => FamilyMember.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  // Espeja removeMember() de lib/family.ts. RLS ya impide que esto afecte al
  // dueño (.neq('role', 'owner')), pero el trigger de la base de datos es la
  // garantía real, no esta cláusula del lado del cliente.
  Future<String?> removeFamilyMember(String memberId) async {
    try {
      await supabase
          .from('family_members')
          .update({'status': 'removed'})
          .eq('id', memberId)
          .neq('role', 'owner');
      return null;
    } catch (e) {
      return e.toString();
    }
  }
}
