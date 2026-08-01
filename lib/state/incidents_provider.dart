import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/repositories/incidents_repository.dart';
import '../data/supabase_client.dart';
import '../domain/models/incident.dart';

part 'incidents_provider.g.dart';

// Puerto de nearbyIncidents (lib/store.ts) + la suscripción realtime de
// loadIncidents()/postgres_changes en map-tab.tsx.
@Riverpod(keepAlive: true)
class Incidents extends _$Incidents {
  final _repo = IncidentsRepository();
  RealtimeChannel? _channel;

  @override
  Future<List<Incident>> build() async {
    _channel ??= supabase
        .channel('incidents')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'incidents',
          callback: (_) => refresh(),
        )
        .subscribe();
    ref.onDispose(() {
      if (_channel != null) supabase.removeChannel(_channel!);
    });
    return _repo.listActive();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() => _repo.listActive());
  }

  Future<Incident> report({
    required String title,
    String? description,
    required String incidentType,
    required String severity,
    required double latitude,
    required double longitude,
  }) async {
    final incident = await _repo.reportFull(
      title: title,
      description: description,
      incidentType: incidentType,
      severity: severity,
      latitude: latitude,
      longitude: longitude,
    );
    await refresh();
    return incident;
  }

  Future<void> updateIncident({
    required String id,
    required String title,
    String? description,
    required String incidentType,
    required String severity,
  }) async {
    await _repo.updateIncident(
      id: id,
      title: title,
      description: description,
      incidentType: incidentType,
      severity: severity,
    );
    await refresh();
  }

  Future<void> delete(String id) async {
    await _repo.deleteIncident(id);
    await refresh();
  }
}

// Puerto de currentUserId/isAdmin en map-tab.tsx.
@riverpod
class MapPermissions extends _$MapPermissions {
  @override
  Future<({String? userId, bool isAdmin})> build() async {
    final user = supabase.auth.currentUser;
    if (user == null) return (userId: null, isAdmin: false);
    final admin = await IncidentsRepository().isAdmin(user.id);
    return (userId: user.id, isAdmin: admin);
  }
}
