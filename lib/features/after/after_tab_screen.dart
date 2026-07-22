import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/repositories/incidents_repository.dart';
import '../../data/repositories/recordings_repository.dart';
import '../../domain/models/sos_alert.dart';
import '../../state/alert_history_provider.dart';
import '../../state/contacts_provider.dart';
import '../../state/location_provider.dart';
import '../../state/recordings_provider.dart';

// Puerto de components/tabs/after-tab.tsx para la Fase 3: historial de alertas
// SOS (marcar resuelta/falsa alarma), grabaciones (descargar/borrar) y
// "llegué bien" (solo el fallback de WhatsApp — la mensajería interna vía
// chat_messages es Fase 6). Las zonas de peligro (mapa/incidentes) quedan
// para la Fase 5.
class AfterTabScreen extends ConsumerWidget {
  const AfterTabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        _AfterStatusCard(),
        SizedBox(height: 16),
        _ArrivedWellCard(),
        SizedBox(height: 16),
        _AlertHistorySection(),
        SizedBox(height: 16),
        _RecordingsSection(),
        SizedBox(height: 16),
        _DangerZonesSection(),
      ],
    );
  }
}

// Puerto de la sección "Zonas de peligro" en after-tab.tsx — ver nota en
// IncidentsRepository.getNearbyDangerZones() sobre por qué esto consulta
// directo en vez de reutilizar el sistema de mapa (Fase 5, aún no construida).
class _DangerZonesSection extends ConsumerStatefulWidget {
  const _DangerZonesSection();

  @override
  ConsumerState<_DangerZonesSection> createState() => _DangerZonesSectionState();
}

class _DangerZonesSectionState extends ConsumerState<_DangerZonesSection> {
  final _repo = IncidentsRepository();
  List<DangerZone>? _zones;

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(locationWatcherProvider);
    if (location.hasCoordinates && _zones == null) {
      _repo.getNearbyDangerZones(latitude: location.latitude!, longitude: location.longitude!).then((z) {
        if (mounted) setState(() => _zones = z);
      });
    }
    final zones = _zones ?? const [];
    if (zones.isEmpty) return const SizedBox.shrink();

    final warning = Theme.of(context).colorScheme.tertiary;
    return Card(
      color: Color.alphaBlend(warning.withValues(alpha: 0.08), Theme.of(context).colorScheme.surface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: warning.withValues(alpha: 0.5))),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Icon(Icons.warning_amber_rounded, color: warning, size: 20), const SizedBox(width: 8), const Text('Zonas de peligro cercanas', style: TextStyle(fontWeight: FontWeight.w600))]),
            const SizedBox(height: 8),
            ...zones.map((z) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(Icons.location_on, color: warning, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${z.count} incidente${z.count > 1 ? 's' : ''} reportado${z.count > 1 ? 's' : ''}', style: const TextStyle(fontSize: 13)),
                            Text('${z.latitude.toStringAsFixed(4)}, ${z.longitude.toStringAsFixed(4)}', style: const TextStyle(fontSize: 11, color: Colors.grey, fontFamily: 'monospace')),
                          ],
                        ),
                      ),
                      Chip(label: const Text('Evitar', style: TextStyle(fontSize: 10)), backgroundColor: Theme.of(context).colorScheme.error.withValues(alpha: 0.15), visualDensity: VisualDensity.compact),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

// Puerto de la tarjeta de cabecera de after-tab.tsx (after_title/after_subtitle).
class _AfterStatusCard extends StatelessWidget {
  const _AfterStatusCard();

  @override
  Widget build(BuildContext context) {
    final safe = Theme.of(context).colorScheme.tertiary;
    return Card(
      color: Color.alphaBlend(safe.withValues(alpha: 0.06), Theme.of(context).colorScheme.surface),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, color: safe, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                children: const [
                  Text('Modo DESPUÉS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15), textAlign: TextAlign.center),
                  Text('Seguimiento y protección post-incidente', style: TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.center),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Puerto de handleArrivedWell() en after-tab.tsx, solo la rama de WhatsApp
// (`wa.me`) — el envío por mensajería interna de SOSecure (chat_messages +
// resolución de contacto por email) depende del sistema de chat que se porta
// en la Fase 6, no antes.
class _ArrivedWellCard extends ConsumerStatefulWidget {
  const _ArrivedWellCard();

  @override
  ConsumerState<_ArrivedWellCard> createState() => _ArrivedWellCardState();
}

class _ArrivedWellCardState extends ConsumerState<_ArrivedWellCard> {
  bool _sending = false;
  int? _sentCount;

  Future<void> _notifyArrived() async {
    final contacts = ref.read(contactsProvider).valueOrNull ?? [];
    if (contacts.isEmpty || _sending) return;
    setState(() => _sending = true);

    final now = DateTime.now();
    final text = '✅ Llegué bien a mi destino — ${now.toLocal().toString().substring(0, 16)}\n\n'
        'Mensaje enviado automáticamente desde la app SOSecure.';

    var sent = 0;
    for (final contact in contacts) {
      final phone = contact.phone.replaceAll(RegExp(r'\D'), '');
      if (phone.isEmpty) continue;
      final opened = await launchUrl(
        Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(text)}'),
        mode: LaunchMode.externalApplication,
      );
      if (opened) sent++;
      if (contact != contacts.last) await Future.delayed(const Duration(milliseconds: 600));
    }

    if (!mounted) return;
    setState(() {
      _sending = false;
      _sentCount = sent;
    });
  }

  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(contactsProvider).valueOrNull ?? [];
    final safe = Theme.of(context).colorScheme.tertiary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.home_outlined, color: safe, size: 20),
                const SizedBox(width: 8),
                const Text('Llegué bien', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 4),
            const Text('Avisa a tus contactos que llegaste seguro a tu destino.', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            if (_sentCount != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: safe.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                child: Text('$_sentCount contacto${_sentCount == 1 ? '' : 's'} notificado${_sentCount == 1 ? '' : 's'} por WhatsApp', style: TextStyle(color: safe, fontSize: 13)),
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: safe),
                  onPressed: contacts.isEmpty || _sending ? null : _notifyArrived,
                  icon: _sending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check),
                  label: Text(_sending ? 'Enviando...' : 'Notificar que llegué bien'),
                ),
              ),
            if (contacts.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('No tienes contactos de emergencia guardados.', style: TextStyle(fontSize: 11, color: Colors.red))),
          ],
        ),
      ),
    );
  }
}

const _dayOptions = {'7d': 7, '1m': 30, '3m': 90, '6m': 180};

class _AlertHistorySection extends ConsumerWidget {
  const _AlertHistorySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = ref.watch(alertHistoryDaysProvider);
    final history = ref.watch(alertHistoryProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined, color: Theme.of(context).colorScheme.error, size: 20),
                const SizedBox(width: 8),
                const Expanded(child: Text('Historial de alertas SOS', style: TextStyle(fontWeight: FontWeight.w600))),
                DropdownButton<String>(
                  value: _dayOptions.entries.firstWhere((e) => e.value == days, orElse: () => _dayOptions.entries.first).key,
                  underline: const SizedBox.shrink(),
                  items: _dayOptions.keys.map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
                  onChanged: (v) {
                    if (v != null) ref.read(alertHistoryDaysProvider.notifier).set(_dayOptions[v]!);
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            history.when(
              loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Padding(padding: const EdgeInsets.all(12), child: Text('Error: $e')),
              data: (alerts) {
                if (alerts.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: Text('No hay alertas en este período', style: TextStyle(fontSize: 12, color: Colors.grey))),
                  );
                }
                return Column(children: alerts.map((a) => _AlertTile(alert: a)).toList());
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertTile extends ConsumerWidget {
  final SosAlert alert;
  const _AlertTile({required this.alert});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destructive = Theme.of(context).colorScheme.error;
    final isActive = alert.status == 'active';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.warning_amber_rounded, color: destructive, size: 20),
      title: Text(alert.createdAt?.toLocal().toString().substring(0, 16) ?? '—', style: const TextStyle(fontSize: 13)),
      subtitle: Text('${alert.latitude.toStringAsFixed(4)}, ${alert.longitude.toStringAsFixed(4)}', style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
      trailing: PopupMenuButton<String>(
        child: Chip(
          label: Text(_statusLabel(alert.status), style: const TextStyle(fontSize: 11)),
          backgroundColor: isActive ? destructive.withValues(alpha: 0.15) : Theme.of(context).colorScheme.surfaceContainerHighest,
          labelStyle: TextStyle(color: isActive ? destructive : null),
        ),
        onSelected: (status) => ref.read(alertHistoryProvider.notifier).markStatus(alert.id, status),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'resolved', child: Text('Marcar como resuelta')),
          PopupMenuItem(value: 'false_alarm', child: Text('Marcar como falsa alarma')),
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'active':
        return 'Activa';
      case 'false_alarm':
        return 'Falsa alarma';
      default:
        return 'Resuelta';
    }
  }
}

class _RecordingsSection extends ConsumerWidget {
  const _RecordingsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordings = ref.watch(recordingsProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.videocam_outlined, color: Theme.of(context).colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                const Text('Grabaciones', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            recordings.when(
              loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Padding(padding: const EdgeInsets.all(12), child: Text('Error: $e')),
              data: (list) {
                if (list.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: Text('No hay grabaciones', style: TextStyle(fontSize: 12, color: Colors.grey))),
                  );
                }
                return Column(children: list.map((r) => _RecordingTile(rec: r)).toList());
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordingTile extends ConsumerStatefulWidget {
  final StoredRecording rec;
  const _RecordingTile({required this.rec});

  @override
  ConsumerState<_RecordingTile> createState() => _RecordingTileState();
}

class _RecordingTileState extends ConsumerState<_RecordingTile> {
  bool _downloading = false;

  // A diferencia de la web (donde <a download> basta), en Android
  // launchUrl(externalApplication) sobre una URL http solo la ABRE en el
  // navegador. Guardar en una carpeta privada de la app (intento anterior)
  // tampoco sirve: esas carpetas no las indexa MediaStore, así que el archivo
  // nunca aparece en la Galería. `Gal` inserta el archivo vía MediaStore
  // correctamente (maneja permisos de galería en Android 10+ y anteriores).
  Future<void> _download() async {
    final url = widget.rec.signedUrl;
    if (url == null || _downloading) return;
    setState(() => _downloading = true);
    File? tempFile;
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');

      final hasAccess = await Gal.hasAccess(toAlbum: true) || await Gal.requestAccess(toAlbum: true);
      if (!hasAccess) throw Exception('Permiso de galería denegado');

      final tempDir = await getTemporaryDirectory();
      final ext = widget.rec.storagePath.split('.').last;
      tempFile = File('${tempDir.path}/sosecure-${widget.rec.id}.$ext');
      await tempFile.writeAsBytes(res.bodyBytes);

      if (widget.rec.recordingType == 'video') {
        await Gal.putVideo(tempFile.path, album: 'SOSecure');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Guardado en la galería (álbum SOSecure)')),
        );
      } else {
        // El audio no aplica a la Galería (Gal solo maneja fotos/videos) —
        // se guarda en el almacenamiento propio de la app.
        final docsDir = await getApplicationDocumentsDirectory();
        final saved = await tempFile.copy('${docsDir.path}/${tempFile.uri.pathSegments.last}');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Audio guardado en ${saved.path}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al descargar: $e')));
    } finally {
      if (tempFile != null && await tempFile.exists()) await tempFile.delete();
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rec = widget.rec;
    final durationS = (rec.durationMs / 1000).round();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(rec.recordingType == 'video' ? Icons.videocam : Icons.mic, size: 20),
      title: Text(rec.createdAt.toLocal().toString().substring(0, 16), style: const TextStyle(fontSize: 13)),
      subtitle: Text('${durationS}s${rec.latitude != null ? ' · ${rec.latitude!.toStringAsFixed(4)}, ${rec.longitude!.toStringAsFixed(4)}' : ''}', style: const TextStyle(fontSize: 11)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: _downloading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download, size: 20),
            onPressed: rec.signedUrl == null || _downloading ? null : _download,
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 20, color: Theme.of(context).colorScheme.error),
            onPressed: () => ref.read(recordingsProvider.notifier).delete(rec),
          ),
        ],
      ),
    );
  }
}
