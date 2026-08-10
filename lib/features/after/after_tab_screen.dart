import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../core/glass.dart';
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
      // Bottom extra para que la última tarjeta no quede tapada por el botón
      // flotante SOS — mismo ajuste que en before_tab_screen.dart.
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      // Sin `const` en la lista — ver la misma nota en during_tab_screen.dart.
      children: [
        _AfterStatusCard(),
        const SizedBox(height: 16),
        _ArrivedWellCard(),
        const SizedBox(height: 16),
        _AlertHistorySection(),
        const SizedBox(height: 16),
        _RecordingsSection(),
        const SizedBox(height: 16),
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
  ConsumerState<_DangerZonesSection> createState() =>
      _DangerZonesSectionState();
}

class _DangerZonesSectionState extends ConsumerState<_DangerZonesSection> {
  final _repo = IncidentsRepository();
  List<DangerZone>? _zones;

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(locationWatcherProvider);
    if (location.hasCoordinates && _zones == null) {
      _repo
          .getNearbyDangerZones(
            latitude: location.latitude!,
            longitude: location.longitude!,
          )
          .then((z) {
            if (mounted) setState(() => _zones = z);
          });
    }
    final zones = _zones ?? const [];
    if (zones.isEmpty) return const SizedBox.shrink();

    final warning = Theme.of(context).colorScheme.tertiary;
    return GlassCard(
      color: Color.alphaBlend(
        warning.withValues(alpha: 0.08),
        Theme.of(context).colorScheme.surface,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: warning.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: warning, size: 20),
                const SizedBox(width: 8),
                Text(
                  'after_dangerZones'.tr(),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...zones.map(
              (z) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.location_on, color: warning, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'after_incidents'.tr(
                              namedArgs: {
                                'n': '${z.count}',
                                's': z.count > 1 ? 's' : '',
                              },
                            ),
                            style: const TextStyle(fontSize: 13),
                          ),
                          Text(
                            '${z.latitude.toStringAsFixed(4)}, ${z.longitude.toStringAsFixed(4)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                    Chip(
                      label: Text(
                        'after_avoid'.tr(),
                        style: const TextStyle(fontSize: 10),
                      ),
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.error.withValues(alpha: 0.15),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            ),
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
    return GlassCard(
      color: Color.alphaBlend(
        safe.withValues(alpha: 0.06),
        Theme.of(context).colorScheme.surface,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, color: safe, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                children: [
                  Text(
                    'after_title'.tr(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    'after_subtitle'.tr(),
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
    final text = 'after_arrivedMessage'.tr(
      namedArgs: {'time': now.toLocal().toString().substring(0, 16)},
    );

    var sent = 0;
    for (final contact in contacts) {
      final phone = contact.phone.replaceAll(RegExp(r'\D'), '');
      if (phone.isEmpty) continue;
      final opened = await launchUrl(
        Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(text)}'),
        mode: LaunchMode.externalApplication,
      );
      if (opened) sent++;
      if (contact != contacts.last)
        await Future.delayed(const Duration(milliseconds: 600));
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

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.home_outlined, color: safe, size: 20),
                const SizedBox(width: 8),
                Text(
                  'after_arrivedBtn'.tr(),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'after_arrivedDesc'.tr(),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            if (_sentCount != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: safe.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'after_notifiedCount'.tr(
                    namedArgs: {
                      'n': '$_sentCount',
                      's': _sentCount == 1 ? '' : 's',
                    },
                  ),
                  style: TextStyle(color: safe, fontSize: 13),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: safe),
                  onPressed: contacts.isEmpty || _sending
                      ? null
                      : _notifyArrived,
                  icon: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check),
                  label: Text(
                    _sending ? 'sending'.tr() : 'after_notifyArrivedBtn'.tr(),
                  ),
                ),
              ),
            if (contacts.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'after_noContactsSaved'.tr(),
                  style: const TextStyle(fontSize: 11, color: Colors.red),
                ),
              ),
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

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.shield_outlined,
                  color: Theme.of(context).colorScheme.error,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'after_sosHistory'.tr(),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                DropdownButton<String>(
                  value: _dayOptions.entries
                      .firstWhere(
                        (e) => e.value == days,
                        orElse: () => _dayOptions.entries.first,
                      )
                      .key,
                  underline: const SizedBox.shrink(),
                  items: _dayOptions.keys
                      .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null)
                      ref
                          .read(alertHistoryDaysProvider.notifier)
                          .set(_dayOptions[v]!);
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            history.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(12),
                child: Text('error_withDetail'.tr(namedArgs: {'e': '$e'})),
              ),
              data: (alerts) {
                if (alerts.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        'after_noAlerts'.tr(),
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  );
                }
                return Column(
                  children: alerts.map((a) => _AlertTile(alert: a)).toList(),
                );
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
      onTap: () => _showDetail(context, ref),
      leading: Icon(Icons.warning_amber_rounded, color: destructive, size: 20),
      title: Text(
        alert.createdAt?.toLocal().toString().substring(0, 16) ?? '—',
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(
        '${alert.latitude.toStringAsFixed(4)}, ${alert.longitude.toStringAsFixed(4)}',
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
      ),
      trailing: PopupMenuButton<String>(
        child: Chip(
          label: Text(
            _statusLabel(alert.status),
            style: const TextStyle(fontSize: 11),
          ),
          backgroundColor: isActive
              ? destructive.withValues(alpha: 0.15)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          labelStyle: TextStyle(color: isActive ? destructive : null),
        ),
        onSelected: (status) => ref
            .read(alertHistoryProvider.notifier)
            .markStatus(alert.id, status),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'resolved',
            child: Text('after_markResolved'.tr()),
          ),
          PopupMenuItem(
            value: 'false_alarm',
            child: Text('after_markFalseAlarm'.tr()),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'active':
        return 'after_active'.tr();
      case 'false_alarm':
        return 'sos_falseAlarm'.tr();
      default:
        return 'after_resolved'.tr();
    }
  }

  void _showDetail(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AlertDetailSheet(alert: alert),
    );
  }
}

// Vista de detalle de alerta (pendiente del plan original de Fase 3): info
// completa de una alerta pasada — estado, ubicación, contactos notificados,
// y la grabación vinculada si existe (vía sos_alert_id en `recordings`).
class _AlertDetailSheet extends ConsumerStatefulWidget {
  final SosAlert alert;
  const _AlertDetailSheet({required this.alert});

  @override
  ConsumerState<_AlertDetailSheet> createState() => _AlertDetailSheetState();
}

class _AlertDetailSheetState extends ConsumerState<_AlertDetailSheet> {
  final _recordingsRepo = RecordingsRepository();
  StoredRecording? _recording;
  bool _loadingRecording = true;

  @override
  void initState() {
    super.initState();
    _recordingsRepo.getRecordingForAlert(widget.alert.id).then((rec) {
      if (mounted)
        setState(() {
          _recording = rec;
          _loadingRecording = false;
        });
    });
  }

  @override
  Widget build(BuildContext context) {
    final alert = widget.alert;
    final destructive = Theme.of(context).colorScheme.error;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: destructive, size: 22),
                const SizedBox(width: 8),
                Text(
                  'after_alertNumber'.tr(
                    namedArgs: {'id': alert.id.substring(0, 8)},
                  ),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _row(
              'date_label'.tr(),
              alert.createdAt?.toLocal().toString().substring(0, 19) ?? '—',
            ),
            _row('status_label'.tr(), alert.status),
            _row(
              'sos_locationLabel'.tr(),
              '${alert.latitude.toStringAsFixed(6)}, ${alert.longitude.toStringAsFixed(6)}',
            ),
            const SizedBox(height: 8),
            Text(
              'sos_contactsNotified'.tr(),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 6),
            alert.contactsNotified.isEmpty
                ? Text(
                    'none_label'.tr(),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  )
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: alert.contactsNotified
                        .map(
                          (n) => Chip(
                            label: Text(
                              n,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        )
                        .toList(),
                  ),
            const SizedBox(height: 16),
            Text(
              'after_recordingLabel'.tr(),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 6),
            if (_loadingRecording)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_recording == null)
              Text(
                'after_noRecordingLinked'.tr(),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              )
            else
              _RecordingTile(rec: _recording!),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class _RecordingsSection extends ConsumerWidget {
  const _RecordingsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordings = ref.watch(recordingsProvider);
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.videocam_outlined,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'after_recordings'.tr(),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            recordings.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(12),
                child: Text('error_withDetail'.tr(namedArgs: {'e': '$e'})),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        'after_noRecordings'.tr(),
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  );
                }
                return Column(
                  children: list.map((r) => _RecordingTile(rec: r)).toList(),
                );
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

      final hasAccess =
          await Gal.hasAccess(toAlbum: true) ||
          await Gal.requestAccess(toAlbum: true);
      if (!hasAccess) throw Exception('after_galleryPermDenied'.tr());

      final tempDir = await getTemporaryDirectory();
      final ext = widget.rec.storagePath.split('.').last;
      tempFile = File('${tempDir.path}/sosecure-${widget.rec.id}.$ext');
      await tempFile.writeAsBytes(res.bodyBytes);

      if (widget.rec.recordingType == 'video') {
        await Gal.putVideo(tempFile.path, album: 'SOSecure');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('after_savedGalleryAlbum'.tr())),
        );
      } else {
        // El audio no aplica a la Galería (Gal solo maneja fotos/videos) —
        // se guarda en el almacenamiento propio de la app.
        final docsDir = await getApplicationDocumentsDirectory();
        final saved = await tempFile.copy(
          '${docsDir.path}/${tempFile.uri.pathSegments.last}',
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'during_audioSavedAt'.tr(namedArgs: {'path': saved.path}),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('after_downloadError'.tr(namedArgs: {'e': '$e'})),
        ),
      );
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
      leading: Icon(
        rec.recordingType == 'video' ? Icons.videocam : Icons.mic,
        size: 20,
      ),
      title: Text(
        rec.createdAt.toLocal().toString().substring(0, 16),
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(
        '${durationS}s${rec.latitude != null ? ' · ${rec.latitude!.toStringAsFixed(4)}, ${rec.longitude!.toStringAsFixed(4)}' : ''}',
        style: const TextStyle(fontSize: 11),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: _downloading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download, size: 20),
            onPressed: rec.signedUrl == null || _downloading ? null : _download,
          ),
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              size: 20,
              color: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => ref.read(recordingsProvider.notifier).delete(rec),
          ),
        ],
      ),
    );
  }
}
