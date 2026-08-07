import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:url_launcher/url_launcher.dart';

import '../../domain/models/live_contact.dart';
import '../../state/contact_locations_provider.dart';
import '../../state/live_sharing_provider.dart';
import '../../state/location_provider.dart';
import '../../platform/sos_alarm.dart';
import '../../state/security_timer_provider.dart';
import '../../state/voice_sos_provider.dart';
import '../map/map_tab_screen.dart';
import '../routes/routes_tab_screen.dart';

// Puerto parcial de components/tabs/before-tab.tsx para la Fase 3: compartir
// ubicación en vivo (hooks/use-live-location.ts) y el temporizador de
// seguridad. Rutas/mapa (OSRM, Photon, flutter_map) llegan en la Fase 5 — el
// resto de esta pantalla queda placeholder hasta entonces.
class BeforeTabScreen extends ConsumerStatefulWidget {
  const BeforeTabScreen({super.key});

  @override
  ConsumerState<BeforeTabScreen> createState() => _BeforeTabScreenState();
}

class _BeforeTabScreenState extends ConsumerState<BeforeTabScreen> {
  @override
  void initState() {
    super.initState();
    // Los callbacks de aviso/expiración se registran una sola vez — el provider
    // vive keepAlive, así que sobreviven a rebuilds de este widget.
    final timerNotifier = ref.read(securityTimerProvider.notifier);
    timerNotifier.onFiveMinuteWarning = () {
      SosAlarm.triggerWarning(
        '⏱️ SOSecure',
        'before_timerFiveMinWarning'.tr(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⏱️ ${'before_timerFiveMinWarning'.tr()}'),
        ),
      );
    };
    timerNotifier.onExpired = () {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⏰ ${'before_timerExpiredAlert'.tr()}'),
          backgroundColor: Colors.red,
        ),
      );
    };
  }

  @override
  Widget build(BuildContext context) {
    // Orden y agrupación calcada de before-tab.tsx: cabecera, luego las
    // secciones colapsables de rutas y mapa (ambas cerradas por defecto, igual
    // que routesExpanded/mapExpanded en la web), y después temporizador, zonas
    // seguras, ubicación en vivo y palabra clave — en ese orden exacto.
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        // Nota general para esta lista: NINGUNA de las cards de abajo puede
        // ser `const` — cada una muestra texto vía .tr(), y un hijo const es
        // canonicalizado por Flutter (misma identidad de objeto entre
        // builds), lo que hace que Flutter salte por completo su
        // reconstrucción vía el fast-path de `updateChild` aunque este
        // ListView se reconstruya. Con `const` aquí, el contenido de estas
        // cards quedaba congelado en el idioma con el que se montó la
        // primera vez.
        _BeforeStatusCard(),
        const SizedBox(height: 16),
        _CollapsibleSection(
          icon: Icons.navigation_outlined,
          title: 'before_safeRoute'.tr(),
          child: RoutesTabScreen(),
        ),
        const SizedBox(height: 16),
        _CollapsibleSection(
          icon: Icons.map_outlined,
          title: 'before_mapIncidents'.tr(),
          child: MapTabScreen(),
        ),
        const SizedBox(height: 16),
        _SecurityTimerCard(),
        const SizedBox(height: 16),
        _SafeZonesCard(),
        const SizedBox(height: 16),
        _LiveSharingCard(),
        const SizedBox(height: 16),
        _VoiceKeywordCard(),
      ],
    );
  }
}

// Puerto de los botones routesExpanded/mapExpanded de before-tab.tsx — ambas
// secciones arrancan colapsadas y el usuario las abre a demanda.
class _CollapsibleSection extends StatefulWidget {
  final IconData icon;
  final String title;
  final Widget child;
  const _CollapsibleSection({
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<_CollapsibleSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(widget.icon, size: 20, color: primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.grey,
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[const SizedBox(height: 8), widget.child],
      ],
    );
  }
}

// Puerto de la tarjeta de cabecera de before-tab.tsx (before_title/before_subtitle).
class _BeforeStatusCard extends StatelessWidget {
  const _BeforeStatusCard();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      color: Color.alphaBlend(
        primary.withValues(alpha: 0.05),
        Theme.of(context).colorScheme.surface,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'before_title'.tr(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    'before_subtitle'.tr(),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecurityTimerCard extends ConsumerStatefulWidget {
  const _SecurityTimerCard();

  @override
  ConsumerState<_SecurityTimerCard> createState() => _SecurityTimerCardState();
}

class _SecurityTimerCardState extends ConsumerState<_SecurityTimerCard> {
  final _minutesController = TextEditingController(text: '30');
  int _selectedPreset = 30;

  @override
  void dispose() {
    _minutesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timer = ref.watch(securityTimerProvider);
    final destructive = Theme.of(context).colorScheme.error;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timer_outlined, color: destructive, size: 20),
                const SizedBox(width: 8),
                Text(
                  'before_timer'.tr(),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'before_timerHint'.tr(),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            if (timer.active && timer.remaining != null) ...[
              Center(
                child: Text(
                  _formatDuration(timer.remaining!),
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: destructive,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.tertiary,
                  ),
                  onPressed: () =>
                      ref.read(securityTimerProvider.notifier).cancel(),
                  icon: const Icon(Icons.check),
                  label: Text('before_timerArrived'.tr()),
                ),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _minutesController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'before_timerMinutes'.tr(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () {
                      final mins = int.tryParse(_minutesController.text) ?? 30;
                      ref
                          .read(securityTimerProvider.notifier)
                          .start(Duration(minutes: mins));
                    },
                    child: Text('before_timerStart'.tr()),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [10, 15, 30, 60].map((m) {
                  final selected = _selectedPreset == m;
                  final primary = Theme.of(context).colorScheme.primary;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: m == 60 ? 0 : 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => setState(() {
                          _selectedPreset = m;
                          _minutesController.text = m.toString();
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected
                                ? primary.withValues(alpha: 0.15)
                                : Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected ? primary : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Text(
                            '${m}min',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: selected ? primary : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _LiveSharingCard extends ConsumerWidget {
  const _LiveSharingCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSharing = ref.watch(liveSharingProvider);
    final contacts = ref.watch(contactLocationsProvider);
    final location = ref.watch(locationWatcherProvider);
    final primary = Theme.of(context).colorScheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.share_location_outlined, color: primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'before_shareMyLocation'.tr(),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Switch(
                  value: isSharing,
                  onChanged: (_) =>
                      ref.read(liveSharingProvider.notifier).toggle(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'before_liveShareDesc'.tr(),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (contacts.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'before_sharingWithYouNow'.tr(),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              ...contacts.map(
                (c) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(
                    Icons.person_pin_circle_outlined,
                    size: 20,
                  ),
                  title: Text(
                    c.displayName,
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    '${c.latitude.toStringAsFixed(4)}, ${c.longitude.toStringAsFixed(4)}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ],
            if ((isSharing && location.hasCoordinates) ||
                contacts.isNotEmpty) ...[
              const SizedBox(height: 12),
              _LiveSharingMap(
                selfPoint: (isSharing && location.hasCoordinates)
                    ? ll.LatLng(location.latitude!, location.longitude!)
                    : null,
                contacts: contacts,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Puerto simplificado de TrackingMap (before-tab.tsx): un marcador verde para
// "Tú" (si estás compartiendo) y uno azul por cada contacto con ubicación en
// vivo — sin el enfoque/click-to-focus de la web, solo la vista conjunta.
class _LiveSharingMap extends StatelessWidget {
  final ll.LatLng? selfPoint;
  final List<LiveContact> contacts;
  const _LiveSharingMap({required this.selfPoint, required this.contacts});

  @override
  Widget build(BuildContext context) {
    final points = [
      if (selfPoint != null) selfPoint!,
      ...contacts.map((c) => ll.LatLng(c.latitude, c.longitude)),
    ];
    if (points.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 220,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: points.first,
            initialZoom: 15,
            initialCameraFit: points.length > 1
                ? CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(points),
                    padding: const EdgeInsets.all(40),
                  )
                : null,
          ),
          children: [
            TileLayer(
              urlTemplate: isDark
                  ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
                  : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: 'com.sosecure.app',
            ),
            MarkerLayer(
              markers: [
                if (selfPoint != null)
                  Marker(
                    point: selfPoint!,
                    width: 90,
                    height: 48,
                    child: const _LiveMarkerLabel(
                      label: 'Tú',
                      color: Color(0xFF4ADE80),
                    ),
                  ),
                ...contacts.map(
                  (c) => Marker(
                    point: ll.LatLng(c.latitude, c.longitude),
                    width: 90,
                    height: 48,
                    child: _LiveMarkerLabel(
                      label: c.displayName,
                      color: const Color(0xFF3B82F6),
                    ),
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

class _LiveMarkerLabel extends StatelessWidget {
  final String label;
  final Color color;
  const _LiveMarkerLabel({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 10),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

Map<String, (String, IconData)> get _safeZoneQueries => {
  'before_sz_pharmacy'.tr(): ('farmacia', Icons.local_pharmacy_outlined),
  'before_sz_police'.tr(): ('ministerio+publico', Icons.local_police_outlined),
  'before_sz_hospital'.tr(): ('hospital', Icons.local_hospital_outlined),
  'before_sz_store'.tr(): ('tienda+24+horas', Icons.storefront_outlined),
};

// Puerto fiel de la sección "Zonas Seguras" de before-tab.tsx — son 4 botones
// fijos que abren una búsqueda de Google Maps con la ubicación actual, sin
// cálculo de cercanía propio (así funciona también en la web: no hay Overpass
// ni tabla de zonas reales, es delegar la búsqueda a Google Maps).
class _SafeZonesCard extends ConsumerWidget {
  const _SafeZonesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(locationWatcherProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'before_safeZones'.tr(),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            if (!location.hasCoordinates)
              Text(
                'before_activateForZones'.tr(),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.4,
              children: _safeZoneQueries.entries.map((e) {
                final (query, icon) = e.value;
                return OutlinedButton.icon(
                  icon: Icon(icon, size: 18),
                  label: Text(e.key, style: const TextStyle(fontSize: 12)),
                  onPressed: !location.hasCoordinates
                      ? null
                      : () => launchUrl(
                          Uri.parse(
                            'https://www.google.com/maps/search/$query/@${location.latitude},${location.longitude},15z',
                          ),
                          mode: LaunchMode.externalApplication,
                        ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceKeywordCard extends ConsumerStatefulWidget {
  const _VoiceKeywordCard();

  @override
  ConsumerState<_VoiceKeywordCard> createState() => _VoiceKeywordCardState();
}

class _VoiceKeywordCardState extends ConsumerState<_VoiceKeywordCard> {
  @override
  Widget build(BuildContext context) {
    final voice = ref.watch(voiceSosProvider);
    final primary = Theme.of(context).colorScheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.mic_none_outlined, color: primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'before_voiceKeyword'.tr(),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Switch(
                  value: voice.enabled,
                  onChanged: (v) =>
                      ref.read(voiceSosProvider.notifier).setEnabled(v),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              voice.enabled
                  ? (voice.listening
                        ? 'before_voiceListening'.tr(
                            namedArgs: {'keyword': voice.keyword},
                          )
                        : 'before_voiceActivating'.tr())
                  : 'before_voiceIdle'.tr(),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (voice.errorMessage != null) ...[
              const SizedBox(height: 4),
              Text(
                voice.errorMessage!,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'before_voiceKeywordLabel'.tr(namedArgs: {'word': voice.keyword}),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: () => _editKeyword(context, ref, voice.keyword),
                  child: Text('before_voiceKeywordChange'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editKeyword(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('before_voiceKeyword'.tr()),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'before_voiceKeywordPlaceholder'.tr(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text('save'.tr()),
          ),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      await ref
          .read(voiceSosProvider.notifier)
          .setKeyword(result.trim().toLowerCase());
    }
  }
}
