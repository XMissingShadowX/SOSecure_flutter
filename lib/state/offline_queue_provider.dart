import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/supabase_client.dart';
import '../domain/models/offline_queue_item.dart';

part 'offline_queue_provider.g.dart';

const _queueKey = 'sosecure.offlineQueue';

// Puerto de offlineQueue en lib/store.ts + la lógica de sincronización que en
// la web vive inline en map-tab.tsx (syncOfflineQueue). A diferencia de la web
// (que solo escucha window online/offline y sincroniza sin reintento real por
// ítem), aquí se usa connectivity_plus para detectar reconexión y sí se
// reintenta item por item, dejando en la cola los que fallen individualmente
// en vez de vaciarla incondicionalmente — mejora deliberada sobre el
// comportamiento original, necesaria para la confiabilidad del SOS.
@Riverpod(keepAlive: true)
class OfflineQueue extends _$OfflineQueue {
  StreamSubscription<List<ConnectivityResult>>? _sub;

  @override
  List<OfflineQueueItem> build() {
    _load();
    _sub = Connectivity().onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none)) flush();
    });
    ref.onDispose(() => _sub?.cancel());
    return const [];
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_queueKey) ?? [];
    state = raw
        .map(
          (s) =>
              OfflineQueueItem.fromJson(jsonDecode(s) as Map<String, dynamic>),
        )
        .toList();
    if (state.isNotEmpty) flush();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _queueKey,
      state.map((i) => jsonEncode(i.toJson())).toList(),
    );
  }

  Future<void> enqueue({
    required String table,
    required Map<String, dynamic> payload,
  }) async {
    state = [
      ...state,
      OfflineQueueItem(
        table: table,
        payload: payload,
        queuedAt: DateTime.now(),
      ),
    ];
    await _persist();
  }

  Future<void> flush() async {
    if (state.isEmpty) return;
    final remaining = <OfflineQueueItem>[];
    for (final item in state) {
      try {
        await supabase.from(item.table).insert(item.payload);
      } catch (_) {
        remaining.add(item); // se reintenta en el próximo flush, no se descarta
      }
    }
    state = remaining;
    await _persist();
  }
}
