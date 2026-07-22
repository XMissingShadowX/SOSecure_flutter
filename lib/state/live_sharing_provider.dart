import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/repositories/live_location_repository.dart';
import 'auth_provider.dart';
import 'location_provider.dart';

part 'live_sharing_provider.g.dart';

const _isLiveSharingKey = 'sosecure.isLiveSharing';
const _broadcastInterval = Duration(seconds: 30);

// Puerto de la parte de app-shell.tsx que hace el broadcasting real (el toggle
// en sí vivía en hooks/use-live-location.ts, separado del broadcast — aquí se
// unifican porque en Flutter no hay dos "surfaces" de la app corriendo a la vez
// como pestañas del navegador). isLiveSharing SÍ persiste (igual que en
// lib/store.ts), así que al reabrir la app con el flag en true, retoma el
// broadcasting automáticamente.
@Riverpod(keepAlive: true)
class LiveSharing extends _$LiveSharing {
  final _repo = LiveLocationRepository();
  Timer? _timer;

  @override
  bool build() {
    _load();
    ref.onDispose(() => _timer?.cancel());
    return false;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_isLiveSharingKey) ?? false;
    if (saved) {
      state = true;
      _startBroadcast();
    }
  }

  Future<void> toggle() async {
    final next = !state;
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isLiveSharingKey, next);

    if (next) {
      _startBroadcast();
    } else {
      _timer?.cancel();
      _timer = null;
      final userId = ref.read(currentUserProvider)?.id;
      if (userId != null) await _repo.stopSharing(userId);
    }
  }

  void _startBroadcast() {
    _timer?.cancel();
    _broadcastOnce();
    _timer = Timer.periodic(_broadcastInterval, (_) => _broadcastOnce());
  }

  Future<void> _broadcastOnce() async {
    final user = ref.read(currentUserProvider);
    final location = ref.read(locationWatcherProvider);
    if (user == null || !location.hasCoordinates) return;
    try {
      await _repo.broadcast(
        userId: user.id,
        displayName: (user.userMetadata?['full_name'] as String?) ?? user.email ?? 'Usuario',
        latitude: location.latitude!,
        longitude: location.longitude!,
      );
    } catch (_) {
      // Sin conexión — el próximo tick de 30s reintenta, igual que en la web.
    }
  }
}
