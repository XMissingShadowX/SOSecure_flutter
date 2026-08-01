import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../state/contact_locations_provider.dart';
import '../../state/live_sharing_provider.dart';
import '../../state/location_provider.dart';
import '../../platform/sos_alarm.dart';
import '../../state/security_timer_provider.dart';
import '../../state/voice_sos_provider.dart';

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
        'Quedan 5 minutos para que expire tu temporizador de seguridad',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '⏱️ Quedan 5 minutos para que expire tu temporizador de seguridad',
          ),
        ),
      );
    };
    timerNotifier.onExpired = () {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⏰ Temporizador expirado — se activó una alerta SOS'),
          backgroundColor: Colors.red,
        ),
      );
    };
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        _BeforeStatusCard(),
        SizedBox(height: 16),
        _SecurityTimerCard(),
        SizedBox(height: 16),
        _LiveSharingCard(),
        SizedBox(height: 16),
        _VoiceKeywordCard(),
        SizedBox(height: 16),
        _SafeZonesCard(),
        SizedBox(height: 16),
        _RoutesPlaceholder(),
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
                children: const [
                  Text(
                    'Modo ANTES',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    'Prepárate antes de salir',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
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
                const Text(
                  'Temporizador de seguridad',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Si no confirmas que llegaste bien antes de que expire, se activa una alerta SOS automáticamente.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
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
                  label: const Text('Llegué bien'),
                ),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _minutesController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Minutos',
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
                    child: const Text('Iniciar'),
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
                const Expanded(
                  child: Text(
                    'Compartir mi ubicación en vivo',
                    style: TextStyle(fontWeight: FontWeight.w600),
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
            const Text(
              'Tus contactos con cuenta SOSecure podrán ver tu ubicación mientras esté activo.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (contacts.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Compartiendo contigo ahora',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
          ],
        ),
      ),
    );
  }
}

const _safeZoneQueries = {
  'Farmacia': ('farmacia', Icons.local_pharmacy_outlined),
  'Policía': ('ministerio+publico', Icons.local_police_outlined),
  'Hospital': ('hospital', Icons.local_hospital_outlined),
  'Tienda 24h': ('tienda+24+horas', Icons.storefront_outlined),
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
            const Text(
              'Zonas seguras cercanas',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            if (!location.hasCoordinates)
              const Text(
                'Activa tu ubicación para buscar zonas cercanas',
                style: TextStyle(fontSize: 12, color: Colors.grey),
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
                const Expanded(
                  child: Text(
                    'Palabra clave de voz',
                    style: TextStyle(fontWeight: FontWeight.w600),
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
                        ? 'Escuchando: "${voice.keyword}"'
                        : 'Activando micrófono...')
                  : 'Di la palabra clave para activar el SOS con las manos libres.',
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
                    'Palabra: "${voice.keyword}"',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: () => _editKeyword(context, ref, voice.keyword),
                  child: const Text('Cambiar'),
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
        title: const Text('Palabra clave de SOS'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'ej. socorro'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Guardar'),
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

class _RoutesPlaceholder extends StatelessWidget {
  const _RoutesPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Rutas seguras y mapa — Fase 5',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ),
    );
  }
}
