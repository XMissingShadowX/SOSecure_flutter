import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/repositories/live_location_repository.dart';
import '../domain/models/live_contact.dart';
import 'contacts_provider.dart';

part 'contact_locations_provider.g.dart';

const _pollInterval = Duration(seconds: 30);

// Puerto de la parte de lectura de hooks/use-live-location.ts (pollContacts) —
// resuelve los contactos con cuenta SOSecure (por email) y sondea su ubicación
// en user_locations cada 30s, igual que la web (sin Supabase Realtime).
@Riverpod(keepAlive: true)
class ContactLocations extends _$ContactLocations {
  final _repo = LiveLocationRepository();
  Timer? _timer;

  @override
  List<LiveContact> build() {
    ref.onDispose(() => _timer?.cancel());
    _start();
    return const [];
  }

  Future<void> _start() async {
    await _poll();
    _timer?.cancel();
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  Future<void> _poll() async {
    final contacts = ref.read(contactsProvider).valueOrNull ?? [];
    final emails = contacts.map((c) => c.email).whereType<String>().toList();
    if (emails.isEmpty) {
      state = const [];
      return;
    }
    try {
      final idMap = await _repo.resolveContactUserIds(emails);
      if (idMap.isEmpty) {
        state = const [];
        return;
      }
      state = await _repo.getContactLocations(idMap.values.toList());
    } catch (_) {
      // Sin conexión — se mantiene el último estado conocido hasta el próximo tick.
    }
  }
}
