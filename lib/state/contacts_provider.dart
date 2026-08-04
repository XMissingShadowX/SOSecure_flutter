import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/repositories/contacts_repository.dart';
import '../domain/models/emergency_contact.dart';

part 'contacts_provider.g.dart';

// Contactos NO se persisten localmente (decisión confirmada en el plan de migración) —
// siempre se piden vía RPC al abrir la app, ya que el dato descifrado es sensible y el
// servidor es la única fuente de verdad.
@riverpod
class Contacts extends _$Contacts {
  final _repo = ContactsRepository();

  @override
  Future<List<EmergencyContact>> build() => _repo.getMyContacts();

  Future<void> addContact({
    required String name,
    required String phone,
    String? email,
    String? relationship,
    required String importance,
  }) async {
    final current = state.valueOrNull ?? [];
    final created = await _repo.addContact(
      name: name,
      phone: phone,
      email: email,
      relationship: relationship,
      priority: current.length + 1,
      importance: importance,
    );
    state = AsyncData([...current, created]);
  }

  Future<void> updateContact({
    required String id,
    required String name,
    required String phone,
    String? email,
    String? relationship,
    required String importance,
  }) async {
    final updated = await _repo.updateContact(
      id: id,
      name: name,
      phone: phone,
      email: email,
      relationship: relationship,
      importance: importance,
    );
    final current = state.valueOrNull ?? [];
    state = AsyncData([
      for (final c in current)
        if (c.id == id) updated else c,
    ]);
  }

  Future<void> removeContact(String id) async {
    await _repo.deleteContact(id);
    final current = state.valueOrNull ?? [];
    state = AsyncData(current.where((c) => c.id != id).toList());
  }
}
