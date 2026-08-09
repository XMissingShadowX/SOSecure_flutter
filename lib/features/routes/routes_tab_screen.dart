import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../core/glass.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../data/repositories/routes_repository.dart';
import '../../domain/models/route_option.dart';
import '../../state/incidents_provider.dart';
import '../../state/location_provider.dart';
import '../../state/places_provider.dart';
import '../../state/premium_provider.dart';
import '../../state/routes_provider.dart';

const _severityColors = {
  'high': Color(0xFFEF4444),
  'medium': Color(0xFFF59E0B),
  'low': Color(0xFF3B82F6),
};
const _routeColors = {
  'safest': Color(0xFF4ADE80),
  'fastest': Color(0xFF3B82F6),
  'alternate': Color(0xFFF59E0B),
};

// Puerto de components/tabs/routes-tab.tsx + components/route-map.tsx: rutas
// seguras con OSRM (perfil peatonal, alternativas), puntuación de seguridad
// basada en incidentes reales cercanos al destino (incidents_provider.dart),
// y edición de origen (buscar un punto de partida distinto a la ubicación
// GPS actual, igual que isEditingOrigin/customOriginLabel en la web).
class RoutesTabScreen extends ConsumerStatefulWidget {
  const RoutesTabScreen({super.key});

  @override
  ConsumerState<RoutesTabScreen> createState() => _RoutesTabScreenState();
}

class _RoutesTabScreenState extends ConsumerState<RoutesTabScreen> {
  final _repo = RoutesRepository();
  final _destinationController = TextEditingController();
  final _originController = TextEditingController();
  final _mapController = MapController();
  Timer? _debounce;
  Timer? _originDebounce;
  List<GeocodeResult> _suggestions = [];
  List<GeocodeResult> _originSuggestions = [];
  bool _searching = false;
  bool _searchingOrigin = false;
  String? _searchError;

  // Puerto de customOriginLabel/isEditingOrigin (routes-tab.tsx) — null =
  // origen es la ubicación GPS actual (comportamiento por defecto).
  LatLng? _originOverride;
  bool _editingOrigin = false;

  @override
  void dispose() {
    _destinationController.dispose();
    _originController.dispose();
    _debounce?.cancel();
    _originDebounce?.cancel();
    super.dispose();
  }

  void _onOriginChanged(String value) {
    _originDebounce?.cancel();
    if (value.length < 3) {
      setState(() => _originSuggestions = []);
      return;
    }
    _originDebounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _searchingOrigin = true);
      try {
        final results = await _repo.searchPlaces(value);
        if (!mounted) return;
        setState(() {
          _originSuggestions = results;
          _searchingOrigin = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _originSuggestions = [];
          _searchingOrigin = false;
        });
      }
    });
  }

  void _selectOrigin(GeocodeResult result) {
    setState(() {
      _originOverride = LatLng(result.latitude, result.longitude);
      _originController.text = result.displayName;
      _originSuggestions = [];
      _editingOrigin = false;
    });
  }

  void _resetOrigin() {
    setState(() {
      _originOverride = null;
      _originController.clear();
      _originSuggestions = [];
      _editingOrigin = false;
    });
  }

  void _onDestinationChanged(String value) {
    _debounce?.cancel();
    if (value.length < 3) {
      setState(() {
        _suggestions = [];
        _searchError = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() {
        _searching = true;
        _searchError = null;
      });
      try {
        final results = await _repo.searchPlaces(value);
        if (!mounted) return;
        setState(() {
          _suggestions = results;
          _searching = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _suggestions = [];
          _searching = false;
          _searchError = 'No se pudo buscar: $e';
        });
      }
    });
  }

  Future<void> _selectDestination(GeocodeResult result) async {
    final location = ref.read(locationWatcherProvider);
    final origin =
        _originOverride ??
        (location.hasCoordinates
            ? LatLng(location.latitude!, location.longitude!)
            : null);
    if (origin == null) return;
    setState(() => _suggestions = []);
    _destinationController.text = result.displayName;
    await ref
        .read(routesProvider.notifier)
        .planTo(origin: origin, destination: result);
  }

  void _reset() {
    ref.read(routesProvider.notifier).reset();
    _destinationController.clear();
    setState(() => _suggestions = []);
    _resetOrigin();
  }

  @override
  Widget build(BuildContext context) {
    final routes = ref.watch(routesProvider);
    final frequentPlaces = ref.watch(frequentPlacesProvider);
    final isPremiumAsync = ref.watch(isPremiumProvider);
    final isPremium = isPremiumAsync.valueOrNull ?? false;

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.route_outlined,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'routes_title'.tr(),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Puerto de isEditingOrigin/customOriginLabel (routes-tab.tsx):
            // por defecto muestra "Ubicación actual" con opción de tocar para
            // buscar un punto de partida distinto, igual que en la web.
            if (routes.options.isEmpty) ...[
              if (_editingOrigin) ...[
                TextField(
                  controller: _originController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'routes_originLabel'.tr(),
                    hintText: 'routes_originHint'.tr(),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: _resetOrigin,
                      tooltip: 'routes_useCurrentLocation'.tr(),
                    ),
                    prefixIcon: _searchingOrigin
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                  ),
                  onChanged: _onOriginChanged,
                ),
                if (_originSuggestions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    constraints: const BoxConstraints(maxHeight: 180),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _originSuggestions.length,
                      itemBuilder: (context, i) => ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.location_on_outlined,
                          size: 18,
                        ),
                        title: Text(
                          _originSuggestions[i].displayName,
                          style: const TextStyle(fontSize: 13),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _selectOrigin(_originSuggestions[i]),
                      ),
                    ),
                  ),
              ] else
                InkWell(
                  onTap: () => setState(() => _editingOrigin = true),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.my_location,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _originOverride == null
                                ? 'routes_originCurrentLocation'.tr()
                                : '${'routes_originLabel'.tr()}: ${_originController.text}',
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(
                          Icons.edit_outlined,
                          size: 14,
                          color: Colors.grey,
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: _destinationController,
              enabled: routes.options.isEmpty,
              decoration: InputDecoration(
                labelText: 'routes_destinationLabel'.tr(),
                hintText: 'routes_where'.tr(),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
              ),
              onChanged: _onDestinationChanged,
            ),
            if (_searchError != null) ...[
              const SizedBox(height: 6),
              Text(
                _searchError!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
            if (_suggestions.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 4),
                constraints: const BoxConstraints(maxHeight: 180),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _suggestions.length,
                  itemBuilder: (context, i) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.location_on_outlined, size: 18),
                    title: Text(
                      _suggestions[i].displayName,
                      style: const TextStyle(fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _selectDestination(_suggestions[i]),
                  ),
                ),
              ),
            if (frequentPlaces.isNotEmpty && routes.options.isEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: frequentPlaces.map((place) {
                  return OutlinedButton.icon(
                    onPressed: () => _selectDestination(
                      GeocodeResult(
                        displayName: place.label,
                        latitude: place.latitude,
                        longitude: place.longitude,
                      ),
                    ),
                    icon: const Icon(Icons.place_outlined, size: 14),
                    label: Text(
                      place.label,
                      style: const TextStyle(fontSize: 12),
                    ),
                  );
                }).toList(),
              ),
            ],
            if (routes.limitReached) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'routes_dailyLimitReached'.tr(),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
            if (routes.error != null) ...[
              const SizedBox(height: 8),
              Text(
                routes.error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (routes.options.isNotEmpty || routes.limitReached)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _reset,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text('routes_reset'.tr()),
                ),
              ),
            if (routes.loading) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
            if (routes.options.isNotEmpty) ...[
              const SizedBox(height: 12),
              _RouteMapView(mapController: _mapController, routes: routes),
              const SizedBox(height: 12),
              ...routes.options.asMap().entries.map((entry) {
                final index = entry.key;
                final route = entry.value;
                final locked = !isPremium && index > 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _RouteOptionCard(
                    route: route,
                    selected: routes.selectedRouteId == route.id,
                    locked: locked,
                    onTap: locked
                        ? null
                        : () => ref
                              .read(routesProvider.notifier)
                              .selectRoute(route.id),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

class _RouteMapView extends ConsumerWidget {
  final MapController mapController;
  final RoutesState routes;
  const _RouteMapView({required this.mapController, required this.routes});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final incidents = ref.watch(incidentsProvider).valueOrNull ?? [];
    final dest = routes.destination;
    final origin = routes.origin;
    if (origin == null || dest == null) return const SizedBox.shrink();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds(origin, dest),
            padding: const EdgeInsets.all(40),
          ),
        );
      } catch (_) {}
    });

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 260,
        child: FlutterMap(
          mapController: mapController,
          options: MapOptions(initialCenter: origin, initialZoom: 14),
          children: [
            TileLayer(
              urlTemplate: Theme.of(context).brightness == Brightness.dark
                  ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
                  : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: 'com.sosecure.app',
            ),
            CircleLayer(
              circles: incidents.where((i) => i.severity == 'high').map((i) {
                return CircleMarker(
                  point: LatLng(i.latitude, i.longitude),
                  radius: 200,
                  useRadiusInMeter: true,
                  color: _severityColors['high']!.withValues(alpha: 0.2),
                  borderColor: _severityColors['high']!,
                  borderStrokeWidth: 1,
                );
              }).toList(),
            ),
            PolylineLayer(
              polylines: routes.options.map((route) {
                final selected = route.id == routes.selectedRouteId;
                return Polyline(
                  points: route.points,
                  color: (_routeColors[route.id] ?? Colors.grey).withValues(
                    alpha: selected ? 1 : 0.4,
                  ),
                  strokeWidth: selected ? 5 : 3,
                );
              }).toList(),
            ),
            MarkerLayer(
              markers: [
                ...incidents.map(
                  (i) => Marker(
                    point: LatLng(i.latitude, i.longitude),
                    width: 20,
                    height: 20,
                    child: Container(
                      decoration: BoxDecoration(
                        color:
                            _severityColors[i.severity] ??
                            _severityColors['low'],
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ),
                Marker(
                  point: origin,
                  width: 16,
                  height: 16,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF4ADE80),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                  ),
                ),
                Marker(
                  point: dest,
                  width: 32,
                  height: 32,
                  child: Icon(
                    Icons.location_on,
                    color: Theme.of(context).colorScheme.error,
                    size: 32,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteOptionCard extends StatelessWidget {
  final RouteOption route;
  final bool selected;
  final bool locked;
  final VoidCallback? onTap;
  const _RouteOptionCard({
    required this.route,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  Color _riskColor(BuildContext context) {
    switch (route.safetyScore.riskLevel) {
      case 'danger':
        return Theme.of(context).colorScheme.error;
      case 'caution':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF4ADE80);
    }
  }

  @override
  Widget build(BuildContext context) {
    final riskColor = _riskColor(context);
    return Stack(
      children: [
        GlassCard(
          // Color.alphaBlend contra la superficie real, no una opacidad plana
          // sobre el Card — en Material 3 el Card ya trae su propio tinte
          // tonal, así que withValues(alpha:) a secas se ve mucho más oscuro
          // de lo esperado (mismo fix aplicado antes en arrived-well/security
          // timer, ver CLAUDE.md).
          color: selected
              ? Color.alphaBlend(
                  riskColor.withValues(alpha: 0.12),
                  Theme.of(context).colorScheme.surface,
                )
              : null,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: selected ? riskColor : Colors.transparent,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Opacity(
              opacity: locked ? 0.6 : 1,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                route.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (route.id == 'safest') ...[
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.shield_outlined,
                                  size: 14,
                                  color: Color(0xFF4ADE80),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                route.distanceLabel,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Icon(
                                Icons.access_time,
                                size: 12,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                route.durationLabel,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          if (route.incidentsOnRoute > 0) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(
                                  Icons.warning_amber_rounded,
                                  size: 14,
                                  color: Color(0xFFF59E0B),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'routes_incidents'.tr(
                                    namedArgs: {
                                      'n': '${route.incidentsOnRoute}',
                                      's': route.incidentsOnRoute > 1
                                          ? 's'
                                          : '',
                                    },
                                  ),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFF59E0B),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    Column(
                      children: [
                        Text(
                          '${route.safetyScore.score}',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: riskColor,
                          ),
                        ),
                        const Text(
                          'seguridad',
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (locked)
          Positioned.fill(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.4),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 14,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'premium'.tr(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
