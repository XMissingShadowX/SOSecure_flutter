import 'package:easy_localization/easy_localization.dart';
import 'package:geolocator/geolocator.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'location_provider.g.dart';

class LocationState {
  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final bool loading;
  final String? error;

  const LocationState({
    this.latitude,
    this.longitude,
    this.accuracy,
    this.loading = true,
    this.error,
  });

  bool get hasCoordinates => latitude != null && longitude != null;

  LocationState copyWith({
    double? latitude,
    double? longitude,
    double? accuracy,
    bool? loading,
    String? error,
  }) {
    return LocationState(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracy: accuracy ?? this.accuracy,
      loading: loading ?? this.loading,
      error: error,
    );
  }
}

// Único watcher de geolocalización de toda la app — espeja el patrón de app-shell.tsx
// (useGeolocation({ watch: true }) vive una sola vez, todo lo demás lee del store). Ninguna
// otra feature debe llamar a Geolocator directamente, solo leer este provider.
@Riverpod(keepAlive: true)
class LocationWatcher extends _$LocationWatcher {
  @override
  LocationState build() {
    _start();
    return const LocationState();
  }

  Future<void> _start() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        state = state.copyWith(
          loading: false,
          error: 'location_permissionDenied'.tr(),
        );
        return;
      }

      if (!await Geolocator.isLocationServiceEnabled()) {
        state = state.copyWith(
          loading: false,
          error: 'location_gpsDisabled'.tr(),
        );
        return;
      }

      // enableHighAccuracy/timeout/maximumAge equivalentes a hooks/use-geolocation.ts.
      const settings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      );
      final subscription =
          Geolocator.getPositionStream(locationSettings: settings).listen(
            (position) {
              state = LocationState(
                latitude: position.latitude,
                longitude: position.longitude,
                accuracy: position.accuracy,
                loading: false,
              );
            },
            onError: (_) {
              state = state.copyWith(
                loading: false,
                error: 'location_fetchFailed'.tr(),
              );
            },
          );
      ref.onDispose(subscription.cancel);
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: 'location_genericError'.tr(namedArgs: {'e': '$e'}),
      );
    }
  }
}
