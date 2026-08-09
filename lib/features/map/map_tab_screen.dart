import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../core/glass.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../domain/models/incident.dart';
import '../../domain/models/incident_type.dart';
import '../../state/auth_provider.dart';
import '../../state/incidents_provider.dart';
import '../../state/location_provider.dart';
import '../../state/offline_queue_provider.dart';

// Puerto de components/tabs/map-tab.tsx + components/incident-map.tsx: mapa de
// incidentes en tiempo real (Supabase Realtime, ver incidents_provider.dart),
// reporte/edición/borrado de incidentes propios (o cualquiera si es admin),
// filtros por severidad/tipo/tiempo, y lista de incidentes recientes.
//
// El toggle "marcadores/calor" de la web usa leaflet.heat (canvas real). No
// hay paquete flutter_map_heatmap compatible con la versión de latlong2 que
// usa el resto del proyecto — se aproxima con círculos semitransparentes por
// incidente (radio/opacidad según severidad), documentado aquí porque no es
// una réplica pixel-perfect del heatmap original.
const _defaultCenter = ll.LatLng(20.9674, -89.6231);
const _defaultZoom = 14.0;

const _severityColors = {
  'high': Color(0xFFEF4444),
  'medium': Color(0xFFF59E0B),
  'low': Color(0xFF3B82F6),
};

Map<String, String> get _incidentTypeLabels => {
  'theft-assault-violence': 'during_incidentTheft'.tr(),
  'harassment-suspicious': 'during_incidentHarassment'.tr(),
  'accident': 'during_incidentAccident'.tr(),
  'SOS': 'during_incidentSOS'.tr(),
};

// Puerto embebido (no es un tab propio — igual que en la web, donde MapTab se
// monta dentro de before-tab.tsx con embedded=true, compartiendo espacio con
// las rutas). mapHeight espeja el h-[350px] de la versión "embedded" web.
class MapTabScreen extends ConsumerStatefulWidget {
  final double mapHeight;
  const MapTabScreen({super.key, this.mapHeight = 320});

  @override
  ConsumerState<MapTabScreen> createState() => _MapTabScreenState();
}

class _MapTabScreenState extends ConsumerState<MapTabScreen> {
  final _mapController = MapController();
  String _filterSeverity = 'all';
  String _filterType = 'all';
  String _filterTime = '7d';
  bool _heatMode = false;
  bool _refreshing = false;

  List<Incident> _applyFilters(List<Incident> incidents) {
    final now = DateTime.now();
    return incidents.where((i) {
      if (_filterSeverity != 'all' && i.severity != _filterSeverity) {
        return false;
      }
      if (_filterType != 'all' && i.incidentType != _filterType) return false;
      if (_filterTime != 'all') {
        final diffDays = now.difference(i.reportedAt).inHours / 24;
        if (_filterTime == '1d' && diffDays > 1) return false;
        if (_filterTime == '7d' && diffDays > 7) return false;
        if (_filterTime == '30d' && diffDays > 30) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await ref.read(incidentsProvider.notifier).refresh();
    if (mounted) setState(() => _refreshing = false);
  }

  void _locate() {
    final location = ref.read(locationWatcherProvider);
    if (!location.hasCoordinates) return;
    _mapController.move(ll.LatLng(location.latitude!, location.longitude!), 16);
  }

  void _openReportSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ReportIncidentSheet(),
    );
  }

  void _openIncidentDetail(Incident incident, bool canManage) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _IncidentDetailSheet(incident: incident, canManage: canManage),
    );
  }

  @override
  Widget build(BuildContext context) {
    final incidentsAsync = ref.watch(incidentsProvider);
    final location = ref.watch(locationWatcherProvider);
    final permissionsAsync = ref.watch(mapPermissionsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final incidents = incidentsAsync.valueOrNull ?? [];
    final filtered = _applyFilters(incidents);
    final counts = {
      'high': incidents.where((i) => i.severity == 'high').length,
      'medium': incidents.where((i) => i.severity == 'medium').length,
      'low': incidents.where((i) => i.severity == 'low').length,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: widget.mapHeight,
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: location.hasCoordinates
                      ? ll.LatLng(location.latitude!, location.longitude!)
                      : _defaultCenter,
                  initialZoom: _defaultZoom,
                ),
                children: [
                  TileLayer(
                    urlTemplate: isDark
                        ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
                        : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                    subdomains: const ['a', 'b', 'c', 'd'],
                    userAgentPackageName: 'com.sosecure.app',
                  ),
                  if (_heatMode)
                    CircleLayer(
                      // 3 anillos concéntricos por incidente (radio decreciente,
                      // opacidad creciente) para simular el falloff radial de un
                      // heatmap real — una sola capa plana se veía como manchas
                      // sólidas en vez de "calor".
                      circles: filtered.expand((i) {
                        final color =
                            _severityColors[i.severity] ??
                            _severityColors['low']!;
                        final intensity = i.severity == 'high'
                            ? 1.0
                            : (i.severity == 'medium' ? 0.6 : 0.35);
                        final point = ll.LatLng(i.latitude, i.longitude);
                        const rings = [
                          (600.0, 0.10),
                          (300.0, 0.18),
                          (120.0, 0.32),
                        ];
                        return rings.map(
                          (ring) => CircleMarker(
                            point: point,
                            radius: ring.$1,
                            useRadiusInMeter: true,
                            color: color.withValues(alpha: ring.$2 * intensity),
                            borderStrokeWidth: 0,
                          ),
                        );
                      }).toList(),
                    ),
                  MarkerLayer(
                    markers: [
                      if (location.hasCoordinates)
                        Marker(
                          point: ll.LatLng(
                            location.latitude!,
                            location.longitude!,
                          ),
                          width: 20,
                          height: 20,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF4ADE80),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (!_heatMode)
                        ...filtered.map((incident) {
                          final permissions = permissionsAsync.valueOrNull;
                          final canManage =
                              permissions != null &&
                              (permissions.isAdmin ||
                                  (permissions.userId != null &&
                                      incident.userId == permissions.userId));
                          return Marker(
                            point: ll.LatLng(
                              incident.latitude,
                              incident.longitude,
                            ),
                            width: 26,
                            height: 26,
                            child: GestureDetector(
                              onTap: () =>
                                  _openIncidentDetail(incident, canManage),
                              child: Container(
                                decoration: BoxDecoration(
                                  color:
                                      _severityColors[incident.severity] ??
                                      _severityColors['low'],
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 3,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.3,
                                      ),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ],
              ),
              Positioned(
                top: 12,
                left: 12,
                child: _MapChip(
                  icon: _heatMode ? '🔥' : '📍',
                  label: _heatMode ? 'map_heat'.tr() : 'map_markers'.tr(),
                  onTap: () => setState(() => _heatMode = !_heatMode),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Row(
                  children: [
                    _RoundIconButton(
                      icon: Icons.my_location,
                      onTap: location.hasCoordinates ? _locate : null,
                    ),
                    const SizedBox(width: 8),
                    _RoundIconButton(
                      icon: Icons.refresh,
                      spinning: _refreshing,
                      onTap: _refresh,
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: 12,
                left: 12,
                child: _LegendCard(counts: counts),
              ),
              Positioned(
                bottom: 12,
                right: 12,
                child: FloatingActionButton.extended(
                  onPressed: _openReportSheet,
                  icon: const Icon(Icons.add),
                  label: Text('map_report'.tr()),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            children: [
              // Tipo tiene etiquetas largas ("Robo / Asalto / Violencia") — en
              // fila propia con todo el ancho para que el dropdown abierto
              // alcance a mostrarlas sin truncarlas.
              DropdownButtonFormField<String>(
                initialValue: _filterType,
                isExpanded: true,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'map_incidentType'.tr(),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'all',
                    child: Text('map_allTypes'.tr()),
                  ),
                  ..._incidentTypeLabels.entries.map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ),
                ],
                onChanged: (v) => setState(() => _filterType = v ?? 'all'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _filterSeverity,
                      isExpanded: true,
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: 'map_severityLabel'.tr(),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text('map_allSeverities'.tr()),
                        ),
                        DropdownMenuItem(
                          value: 'high',
                          child: Text('map_sevHigh'.tr()),
                        ),
                        DropdownMenuItem(
                          value: 'medium',
                          child: Text('map_sevMedium'.tr()),
                        ),
                        DropdownMenuItem(
                          value: 'low',
                          child: Text('map_sevLow'.tr()),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _filterSeverity = v ?? 'all'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _filterTime,
                      isExpanded: true,
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: 'map_whenLabel'.tr(),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text('map_anyTime'.tr()),
                        ),
                        DropdownMenuItem(
                          value: '1d',
                          child: Text('map_time24h'.tr()),
                        ),
                        DropdownMenuItem(
                          value: '7d',
                          child: Text('map_time7d'.tr()),
                        ),
                        DropdownMenuItem(
                          value: '30d',
                          child: Text('map_time30d'.tr()),
                        ),
                      ],
                      onChanged: (v) => setState(() => _filterTime = v ?? '7d'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        GlassCard(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'map_recentIncidents'.tr(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      Chip(
                        label: Text('${filtered.length}'),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 130,
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            'map_noIncidentsShort'.tr(),
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: filtered.length > 5 ? 5 : filtered.length,
                          itemBuilder: (context, index) {
                            final incident = filtered[index];
                            final permissions = permissionsAsync.valueOrNull;
                            final canManage =
                                permissions != null &&
                                (permissions.isAdmin ||
                                    (permissions.userId != null &&
                                        incident.userId == permissions.userId));
                            return ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 5,
                                backgroundColor:
                                    _severityColors[incident.severity],
                              ),
                              title: Text(
                                incident.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                              subtitle: Text(
                                _formatDate(incident.reportedAt),
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: canManage
                                  ? IconButton(
                                      icon: const Icon(
                                        Icons.chevron_right,
                                        size: 18,
                                      ),
                                      onPressed: () => _openIncidentDetail(
                                        incident,
                                        canManage,
                                      ),
                                    )
                                  : null,
                              onTap: () =>
                                  _openIncidentDetail(incident, canManage),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

class _MapChip extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;
  const _MapChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(icon),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool spinning;
  const _RoundIconButton({
    required this.icon,
    this.onTap,
    this.spinning = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: const CircleBorder(),
      elevation: 2,
      child: IconButton(
        icon: spinning
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.primary,
                ),
              )
            : Icon(icon, size: 20),
        onPressed: onTap,
      ),
    );
  }
}

class _LegendCard extends StatelessWidget {
  final Map<String, int> counts;
  const _LegendCard({required this.counts});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'map_severity'.tr(),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            _legendRow(
              _severityColors['high']!,
              'map_high'.tr(namedArgs: {'n': '${counts['high']}'}),
            ),
            _legendRow(
              _severityColors['medium']!,
              'map_medium'.tr(namedArgs: {'n': '${counts['medium']}'}),
            ),
            _legendRow(
              _severityColors['low']!,
              'map_low'.tr(namedArgs: {'n': '${counts['low']}'}),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendRow(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}

// Puerto del formulario de reporte de map-tab.tsx (Dialog -> bottom sheet en
// Flutter): tipo, preguntas de severidad, descripción, y fallback a la cola
// offline si falla el insert (mismo patrón que during-tab.tsx).
class _ReportIncidentSheet extends ConsumerStatefulWidget {
  const _ReportIncidentSheet();

  @override
  ConsumerState<_ReportIncidentSheet> createState() =>
      _ReportIncidentSheetState();
}

class _ReportIncidentSheetState extends ConsumerState<_ReportIncidentSheet> {
  IncidentType _type = IncidentType.theftAssaultViolence;
  final _descriptionController = TextEditingController();
  List<String> _answers = ['', '', ''];
  String? _error;
  bool _sending = false;

  static Map<IncidentType, String> get _typeLabels => {
    IncidentType.theftAssaultViolence: 'during_incidentTheft'.tr(),
    IncidentType.harassmentSuspicious: 'during_incidentHarassment'.tr(),
    IncidentType.accident: 'during_incidentAccident'.tr(),
    IncidentType.sos: 'during_incidentSOS'.tr(),
  };

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final location = ref.read(locationWatcherProvider);
    final questions = incidentQuestions[_type] ?? [];
    final allAnswered =
        questions.isEmpty || _answers.every((a) => a.isNotEmpty);
    if (!location.hasCoordinates) {
      setState(() => _error = 'map_activateLocationToReport'.tr());
      return;
    }
    if (!allAnswered) {
      setState(() => _error = 'map_answerAllQuestions'.tr());
      return;
    }
    setState(() => _sending = true);
    final severity = questions.isNotEmpty
        ? calculateSeverity(_answers)
        : 'medium';
    final title = _typeLabels[_type]!;
    final description = _descriptionController.text.isEmpty
        ? null
        : _descriptionController.text;
    try {
      await ref
          .read(incidentsProvider.notifier)
          .report(
            title: title,
            description: description,
            incidentType: _type.value,
            severity: severity,
            latitude: location.latitude!,
            longitude: location.longitude!,
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      final userId = ref.read(currentUserProvider)?.id;
      if (userId != null) {
        await ref
            .read(offlineQueueProvider.notifier)
            .enqueue(
              table: 'incidents',
              payload: {
                'user_id': userId,
                'title': title,
                'description': description,
                'incident_type': _type.value,
                'severity': severity,
                'latitude': location.latitude,
                'longitude': location.longitude,
              },
            );
        if (mounted) Navigator.pop(context);
      } else {
        setState(
          () => _error = 'map_reportSendError'.tr(namedArgs: {'e': '$e'}),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final questions = incidentQuestions[_type] ?? [];
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'map_reportTitle'.tr(),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<IncidentType>(
                initialValue: _type,
                decoration: InputDecoration(
                  labelText: 'map_incidentType'.tr(),
                ),
                items: _typeLabels.entries
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
                onChanged: (v) => setState(() {
                  _type = v ?? IncidentType.theftAssaultViolence;
                  _answers = ['', '', ''];
                }),
              ),
              for (var i = 0; i < questions.length; i++) ...[
                const SizedBox(height: 12),
                Text(questions[i], style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (final opt in const ['si', 'no', 'no_se'])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              backgroundColor: _answers[i] == opt
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                              foregroundColor: _answers[i] == opt
                                  ? Colors.white
                                  : null,
                            ),
                            onPressed: () => setState(() {
                              final next = [..._answers];
                              next[i] = opt;
                              _answers = next;
                            }),
                            child: Text(
                              opt == 'si'
                                  ? 'yes'.tr()
                                  : (opt == 'no' ? 'no'.tr() : 'map_dontKnow'.tr()),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: 'map_detailsOptional'.tr(),
                  border: const OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _sending ? null : _submit,
                  child: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text('map_submitReport'.tr()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Puerto del popup de incident-map.tsx (detalle + editar/eliminar) para el
// dueño del incidente o un admin.
class _IncidentDetailSheet extends ConsumerStatefulWidget {
  final Incident incident;
  final bool canManage;
  const _IncidentDetailSheet({required this.incident, required this.canManage});

  @override
  ConsumerState<_IncidentDetailSheet> createState() =>
      _IncidentDetailSheetState();
}

class _IncidentDetailSheetState extends ConsumerState<_IncidentDetailSheet> {
  late bool _editing = false;
  late final _titleController = TextEditingController(
    text: widget.incident.title,
  );
  late final _descriptionController = TextEditingController(
    text: widget.incident.description ?? '',
  );
  late String _incidentType = widget.incident.incidentType;
  late String _severity = widget.incident.severity;
  bool _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(incidentsProvider.notifier)
          .updateIncident(
            id: widget.incident.id,
            title: _titleController.text,
            description: _descriptionController.text.isEmpty
                ? null
                : _descriptionController.text,
            incidentType: _incidentType,
            severity: _severity,
          );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('map_deleteIncidentTitle'.tr()),
        content: Text('common_actionCannotUndo'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('delete'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(incidentsProvider.notifier).delete(widget.incident.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final incident = widget.incident;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _editing ? _buildEditForm() : _buildDetail(incident),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildDetail(Incident incident) {
    return [
      Row(
        children: [
          CircleAvatar(
            radius: 6,
            backgroundColor: _severityColors[incident.severity],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              incident.title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        _incidentTypeLabels[incident.incidentType] ?? incident.incidentType,
        style: const TextStyle(fontSize: 13, color: Colors.grey),
      ),
      if (incident.description != null) ...[
        const SizedBox(height: 8),
        Text(incident.description!),
      ],
      const SizedBox(height: 8),
      Text(
        '${incident.reportedAt}',
        style: const TextStyle(fontSize: 11, color: Colors.grey),
      ),
      if (widget.canManage) ...[
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _editing = true),
                icon: const Icon(Icons.edit, size: 16),
                label: Text('edit'.tr()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: _delete,
                icon: const Icon(Icons.delete, size: 16),
                label: Text('delete'.tr()),
              ),
            ),
          ],
        ),
      ],
    ];
  }

  List<Widget> _buildEditForm() {
    return [
      Text(
        'map_editIncident'.tr(),
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _titleController,
        decoration: InputDecoration(labelText: 'map_incidentTitle'.tr()),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: _incidentType,
        decoration: InputDecoration(labelText: 'home_type'.tr()),
        items: _incidentTypeLabels.entries
            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
            .toList(),
        onChanged: (v) => setState(() => _incidentType = v ?? _incidentType),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          for (final level in const ['high', 'medium', 'low'])
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _severity == level
                        ? _severityColors[level]
                        : null,
                    foregroundColor: _severity == level ? Colors.white : null,
                  ),
                  onPressed: () => setState(() => _severity = level),
                  child: Text(
                    level == 'high'
                        ? 'map_sevHigh'.tr()
                        : (level == 'medium'
                              ? 'map_sevMedium'.tr()
                              : 'map_sevLow'.tr()),
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _descriptionController,
        decoration: InputDecoration(
          labelText: 'map_incidentDetails'.tr(),
          border: const OutlineInputBorder(),
        ),
        maxLines: 3,
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => setState(() => _editing = false),
              child: Text('cancel'.tr()),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('save'.tr()),
            ),
          ),
        ],
      ),
    ];
  }
}
