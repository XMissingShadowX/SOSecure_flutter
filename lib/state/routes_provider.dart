import 'package:easy_localization/easy_localization.dart';
import 'package:latlong2/latlong.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/repositories/routes_repository.dart';
import '../domain/models/incident.dart';
import '../domain/models/route_option.dart';
import 'incidents_provider.dart';
import 'premium_provider.dart';

part 'routes_provider.g.dart';

class RoutesState {
  final LatLng? origin;
  final LatLng? destination;
  final String? destinationLabel;
  final List<RouteOption> options;
  final String? selectedRouteId;
  final bool loading;
  final String? error;
  final bool limitReached;

  const RoutesState({
    this.origin,
    this.destination,
    this.destinationLabel,
    this.options = const [],
    this.selectedRouteId,
    this.loading = false,
    this.error,
    this.limitReached = false,
  });

  RoutesState copyWith({
    LatLng? origin,
    LatLng? destination,
    String? destinationLabel,
    List<RouteOption>? options,
    String? selectedRouteId,
    bool? loading,
    String? error,
    bool? limitReached,
  }) {
    return RoutesState(
      origin: origin ?? this.origin,
      destination: destination ?? this.destination,
      destinationLabel: destinationLabel ?? this.destinationLabel,
      options: options ?? this.options,
      selectedRouteId: selectedRouteId ?? this.selectedRouteId,
      loading: loading ?? this.loading,
      error: error,
      limitReached: limitReached ?? this.limitReached,
    );
  }

  static Map<String, String> get _names => {
    'safest': 'routes_safest'.tr(),
    'fastest': 'routes_fastest'.tr(),
    'alternate': 'routes_alternate'.tr(),
  };
  static String nameFor(String id, int index) =>
      _names[id] ?? 'routes_routeN'.tr(namedArgs: {'n': '${index + 1}'});
}

// Puerto de la orquestación de routes-tab.tsx (handleSearch/resetRoute +
// onRoutesLoaded de route-map.tsx). `origin` guarda el punto usado para el
// último cálculo (GPS o uno buscado manualmente) para que el mapa lo dibuje
// correctamente en vez de asumir siempre la ubicación GPS actual.
@riverpod
class Routes extends _$Routes {
  final _repo = RoutesRepository();
  static const _ids = ['safest', 'fastest', 'alternate'];

  @override
  RoutesState build() => const RoutesState();

  Future<void> planTo({
    required LatLng origin,
    required GeocodeResult destination,
  }) async {
    final isPremium = await ref.read(isPremiumProvider.future);
    final allowed = await _repo.checkAndRecordSearch(isPremium: isPremium);
    if (!allowed) {
      state = state.copyWith(limitReached: true);
      return;
    }
    state = RoutesState(
      origin: origin,
      destination: LatLng(destination.latitude, destination.longitude),
      destinationLabel: destination.displayName,
      loading: true,
    );
    await _loadRoutes(origin);
  }

  Future<void> _loadRoutes(LatLng origin) async {
    final dest = state.destination;
    if (dest == null) return;
    try {
      final raw = await _repo.fetchRoutes(origin: origin, destination: dest);
      final incidents =
          ref.read(incidentsProvider).valueOrNull ?? const <Incident>[];
      final tuples = incidents
          .map(
            (i) => (
              latitude: i.latitude,
              longitude: i.longitude,
              severity: i.severity,
            ),
          )
          .toList();
      final baseSafety = calculateSafetyScore(
        destLat: dest.latitude,
        destLng: dest.longitude,
        incidents: tuples,
      );

      final options = <RouteOption>[];
      for (var i = 0; i < raw.length; i++) {
        final id = i < _ids.length ? _ids[i] : 'route-$i';
        final score = (baseSafety.score - i * 10).clamp(0, 100);
        final incidentsOnRoute =
            (baseSafety.incidentsNearby - (raw.length - 1 - i)).clamp(
              0,
              1 << 30,
            );
        options.add(
          RouteOption(
            id: id,
            name: RoutesState.nameFor(id, i),
            points: raw[i].points,
            distanceMeters: raw[i].distanceMeters,
            durationSeconds: raw[i].durationSeconds,
            safetyScore: SafetyScore(
              score: score,
              incidentsNearby: incidentsOnRoute,
              riskLevel: score < 50
                  ? 'danger'
                  : (score < 75 ? 'caution' : 'safe'),
            ),
            incidentsOnRoute: incidentsOnRoute,
          ),
        );
      }
      state = state.copyWith(
        options: options,
        selectedRouteId: 'safest',
        loading: false,
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: 'routes_calcFailed'.tr(namedArgs: {'e': '$e'}),
      );
    }
  }

  void selectRoute(String id) => state = state.copyWith(selectedRouteId: id);

  void reset() => state = const RoutesState();
}
