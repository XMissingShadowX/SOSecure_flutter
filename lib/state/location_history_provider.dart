import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/models/location_sample.dart';
import 'location_provider.dart';

part 'location_history_provider.g.dart';

const _maxAge = Duration(minutes: 10);
const _maxSamples = 50;

// Puerto de `locationHistory` en lib/store.ts — ventana móvil de muestras de
// ubicación (la web las va empujando en el mismo watcher; aquí se deriva por
// separado escuchando locationWatcherProvider para no acoplar el watcher
// único de GPS a la lógica de historial).
@Riverpod(keepAlive: true)
class LocationHistory extends _$LocationHistory {
  @override
  List<LocationSample> build() {
    ref.listen(locationWatcherProvider, (prev, next) {
      if (!next.hasCoordinates) return;
      final now = DateTime.now();
      final updated = [
        ...state.where((s) => now.difference(s.timestamp) < _maxAge),
        LocationSample(latitude: next.latitude!, longitude: next.longitude!, timestamp: now),
      ];
      state = updated.length > _maxSamples ? updated.sublist(updated.length - _maxSamples) : updated;
    });
    return const [];
  }
}
