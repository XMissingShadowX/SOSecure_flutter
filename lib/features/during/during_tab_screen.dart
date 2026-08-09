import 'dart:io';

import 'package:camera/camera.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../core/glass.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/repositories/incidents_repository.dart';
import '../../data/repositories/recordings_repository.dart';
import '../../data/repositories/geocoding_repository.dart';
import '../../domain/models/incident_type.dart';
import '../../domain/models/location_sample.dart';
import '../../state/contacts_provider.dart';
import '../../state/location_history_provider.dart';
import '../../state/location_provider.dart';
import '../../state/auth_provider.dart';
import '../../state/offline_queue_provider.dart';
import '../../state/sos_provider.dart';
import '../../state/standalone_recorder_provider.dart';
import '../../state/voice_sos_provider.dart';

// Puerto completo de components/tabs/during-tab.tsx: estado de SOS, reporte
// de incidente con cuestionario dinámico, activaciones alternativas (toque
// secreto/voz/temporizador), grabación libre de audio/video (no ligada a
// ninguna alerta), e historial de ubicación con geocodificación inversa.
class DuringTabScreen extends ConsumerWidget {
  const DuringTabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      // Bottom extra para que la última tarjeta no quede tapada por el botón
      // flotante SOS — mismo ajuste que en before_tab_screen.dart.
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      // Sin `const` en la lista: `children: const [...]` propaga const a
      // cada elemento, canonicalizándolos — Flutter entonces salta su
      // reconstrucción por completo en rebuilds posteriores (los trata como
      // "sin cambios" por identidad de objeto), congelando el texto .tr()
      // de cada card en el idioma con el que se montaron la primera vez.
      children: [
        _StatusCard(),
        const SizedBox(height: 16),
        _IncidentReportCard(),
        const SizedBox(height: 16),
        _AltActivationCard(),
        const SizedBox(height: 16),
        _RecordingCard(),
        const SizedBox(height: 16),
        _LocationHistoryCard(),
      ],
    );
  }
}

class _StatusCard extends ConsumerWidget {
  const _StatusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sos = ref.watch(sosProvider);
    final destructive = Theme.of(context).colorScheme.error;
    final primary = Theme.of(context).colorScheme.primary;

    // Ver nota de Color.alphaBlend en after_tab_screen.dart (_ArrivedWellCard)
    // — mismo fix para el mismo glitch de Card + color translúcido en M3.
    final surface = Theme.of(context).colorScheme.surface;
    return GlassCard(
      color: sos.active
          ? Color.alphaBlend(destructive.withValues(alpha: 0.08), surface)
          : Color.alphaBlend(primary.withValues(alpha: 0.05), surface),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.radio,
              color: sos.active ? destructive : primary,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                sos.active
                    ? (sos.alert != null
                          ? 'during_sosActiveAlert'.tr(
                              namedArgs: {
                                'ref': sos.alert!.id.substring(0, 8),
                              },
                            )
                          : 'during_sosActiveCreating'.tr())
                    : 'during_emergencyModeSubtitle'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: sos.active ? destructive : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Puerto del formulario de reporte de incidentes (reportIncident() en during-tab.tsx).
class _IncidentReportCard extends ConsumerStatefulWidget {
  const _IncidentReportCard();

  @override
  ConsumerState<_IncidentReportCard> createState() =>
      _IncidentReportCardState();
}

class _IncidentReportCardState extends ConsumerState<_IncidentReportCard> {
  final _repo = IncidentsRepository();
  IncidentType _type = IncidentType.theftAssaultViolence;
  final _descriptionController = TextEditingController();
  List<String> _answers = ['', '', ''];
  String? _error;
  bool _sending = false;
  bool _done = false;

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
    try {
      await _repo.reportIncident(
        type: _type,
        title: _typeLabels[_type]!,
        description: _descriptionController.text.isEmpty
            ? null
            : _descriptionController.text,
        severity: severity,
        latitude: location.latitude!,
        longitude: location.longitude!,
      );
      setState(() {
        _done = true;
        _descriptionController.clear();
        _answers = ['', '', ''];
      });
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _done = false);
      });
    } catch (e) {
      // Puerto de la cola offline (offline_queue_provider.dart) también para
      // reportes de incidentes, no solo alertas SOS — antes de esto un fallo
      // de red aquí simplemente perdía el reporte, sin reintento.
      final userId = ref.read(currentUserProvider)?.id;
      if (userId != null) {
        await ref
            .read(offlineQueueProvider.notifier)
            .enqueue(
              table: 'incidents',
              payload: {
                'user_id': userId,
                'title': _typeLabels[_type]!,
                'description': _descriptionController.text.isEmpty
                    ? null
                    : _descriptionController.text,
                'incident_type': _type.value,
                'severity': severity,
                'latitude': location.latitude,
                'longitude': location.longitude,
              },
            );
        setState(() {
          _done = true;
          _descriptionController.clear();
          _answers = ['', '', ''];
        });
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _done = false);
        });
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
    final location = ref.watch(locationWatcherProvider);
    final questions = incidentQuestions[_type] ?? [];

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.add_circle_outline,
                  color: Theme.of(context).colorScheme.tertiary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'map_reportTitle'.tr(),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<IncidentType>(
              value: _type,
              decoration: InputDecoration(
                labelText: 'during_incidentType'.tr(),
                isDense: true,
              ),
              items: _typeLabels.entries
                  .map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                  )
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _type = v;
                  _answers = ['', '', ''];
                });
              },
            ),
            ...questions.asMap().entries.map((entry) {
              final idx = entry.key;
              final question = entry.value;
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(question, style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        for (final opt in const ['si', 'no', 'no_se'])
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                right: opt == 'no_se' ? 0 : 6,
                              ),
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: _answers[idx] == opt
                                      ? Theme.of(context).colorScheme.primary
                                            .withValues(alpha: 0.15)
                                      : null,
                                ),
                                onPressed: () =>
                                    setState(() => _answers[idx] = opt),
                                child: Text(
                                  opt == 'si'
                                      ? 'yes'.tr()
                                      : opt == 'no'
                                      ? 'no'.tr()
                                      : 'during_dontKnow'.tr(),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'during_detailsLabel'.tr(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
            if (_done)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.tertiary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle, size: 16),
                    const SizedBox(width: 6),
                    Text('during_reportSentShort'.tr()),
                  ],
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _sending || !location.hasCoordinates
                      ? null
                      : _submit,
                  child: Text(
                    _sending ? 'sending'.tr() : 'during_sendReport'.tr(),
                  ),
                ),
              ),
            if (!location.hasCoordinates)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'during_locationNeededShort'.tr(),
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Puerto de la tarjeta "Activación alternativa" — solo informativa (voz/temporizador)
// más el botón funcional de toque secreto (3 toques en 3s).
class _AltActivationCard extends ConsumerStatefulWidget {
  const _AltActivationCard();

  @override
  ConsumerState<_AltActivationCard> createState() => _AltActivationCardState();
}

class _AltActivationCardState extends ConsumerState<_AltActivationCard> {
  int _tapCount = 0;
  DateTime? _firstTapAt;

  void _onSecretTap() {
    final now = DateTime.now();
    if (_firstTapAt == null ||
        now.difference(_firstTapAt!) > const Duration(seconds: 3)) {
      _firstTapAt = now;
      _tapCount = 1;
    } else {
      _tapCount++;
    }
    setState(() {});
    if (_tapCount >= 3) {
      _tapCount = 0;
      _firstTapAt = null;
      ref.read(sosProvider.notifier).activate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final voice = ref.watch(voiceSosProvider);
    final sos = ref.watch(sosProvider);
    final warning = Theme.of(context).colorScheme.tertiary;

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'during_altActivation'.tr(),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'during_altMethodsDesc'.tr(),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            _altRow(
              '👆',
              'during_tapSeq'.tr(),
              'during_tapSeqDesc'.tr(),
            ),
            _altRow(
              '🎙️',
              'during_voiceActivation'.tr(),
              voice.enabled
                  ? 'during_voiceSayKeyword'.tr(
                      namedArgs: {'kw': voice.keyword},
                    )
                  : 'during_voiceNoKeyword'.tr(),
              trailing: voice.enabled && voice.listening && !sos.active
                  ? Text(
                      'during_listeningDot'.tr(),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.green,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : null,
            ),
            _altRow(
              '⏱️',
              'during_timerExpired'.tr(),
              'during_timerExpiredDesc'.tr(),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: warning, style: BorderStyle.solid),
              ),
              onPressed: _onSecretTap,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('👆${'during_secretTap'.tr()}'),
                  const Spacer(),
                  CircleAvatar(
                    radius: 11,
                    backgroundColor: warning,
                    child: Text(
                      '${3 - _tapCount}',
                      style: const TextStyle(fontSize: 11, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _altRow(
    String emoji,
    String title,
    String subtitle, {
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }
}

// Puerto de toggleAudio()/toggleVideo() + panel de acciones post-grabación.
class _RecordingCard extends ConsumerStatefulWidget {
  const _RecordingCard();

  @override
  ConsumerState<_RecordingCard> createState() => _RecordingCardState();
}

class _RecordingCardState extends ConsumerState<_RecordingCard> {
  final _recordingsRepo = RecordingsRepository();
  File? _lastFile;
  String? _lastType; // 'audio' | 'video'
  String _statusMsg = '';
  bool _busy = false;

  Future<void> _toggleAudio() async {
    final notifier = ref.read(standaloneRecorderProvider.notifier);
    if (ref.read(standaloneRecorderProvider).mode == StandaloneRecMode.audio) {
      final file = await notifier.stopAudio();
      setState(() {
        _lastFile = file;
        _lastType = 'audio';
        _statusMsg = file != null ? 'during_audioReady'.tr() : '';
      });
    } else {
      setState(() {
        _lastFile = null;
        _statusMsg = '';
      });
      await notifier.startAudio();
    }
  }

  Future<void> _toggleVideo() async {
    final notifier = ref.read(standaloneRecorderProvider.notifier);
    if (ref.read(standaloneRecorderProvider).mode == StandaloneRecMode.video) {
      final file = await notifier.stopVideo();
      setState(() {
        _lastFile = file;
        _lastType = 'video';
        _statusMsg = file != null ? 'during_videoReady'.tr() : '';
      });
    } else {
      setState(() {
        _lastFile = null;
        _statusMsg = '';
      });
      await notifier.startVideo();
    }
  }

  Future<void> _saveToGallery() async {
    if (_lastFile == null) return;
    setState(() => _busy = true);
    try {
      if (_lastType == 'video') {
        await Gal.putVideo(_lastFile!.path, album: 'SOSecure');
        setState(() => _statusMsg = 'during_savedGallery'.tr());
      } else {
        // El audio no aplica a la Galería (Gal solo maneja fotos/videos) —
        // se guarda en el almacenamiento propio de la app.
        final docsDir = await getApplicationDocumentsDirectory();
        final saved = await _lastFile!.copy(
          '${docsDir.path}/${_lastFile!.uri.pathSegments.last}',
        );
        setState(
          () => _statusMsg = 'during_audioSavedAt'.tr(
            namedArgs: {'path': saved.path},
          ),
        );
      }
    } catch (e) {
      setState(
        () => _statusMsg = 'during_saveError'.tr(namedArgs: {'e': '$e'}),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Puerto de sendRecordingToContacts() — usa el share sheet nativo de Android
  // (equivalente real a la Web Share API que la web intenta primero), en vez
  // de wa.me (que no puede adjuntar el archivo, solo abrir un chat con texto).
  Future<void> _shareToContacts() async {
    if (_lastFile == null) return;
    setState(() => _busy = true);
    try {
      await Share.shareXFiles([
        XFile(_lastFile!.path),
      ], text: 'during_recordingTitle'.tr());
      setState(() => _statusMsg = 'during_shared'.tr());
    } catch (e) {
      setState(
        () => _statusMsg = 'during_shareError'.tr(namedArgs: {'e': '$e'}),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadToCloud() async {
    if (_lastFile == null || _lastType == null) return;
    setState(() {
      _busy = true;
      _statusMsg = 'during_uploadingCloud'.tr();
    });
    final location = ref.read(locationWatcherProvider);
    try {
      final mimeType = _lastType == 'video' ? 'video/mp4' : 'audio/mp4';
      await _recordingsRepo.uploadStandaloneRecording(
        file: _lastFile!,
        recordingType: _lastType!,
        mimeType: mimeType,
        durationMs: 0,
        latitude: location.latitude,
        longitude: location.longitude,
      );
      setState(() => _statusMsg = 'during_savedCloud'.tr());
    } catch (e) {
      setState(
        () => _statusMsg = 'during_uploadError'.tr(namedArgs: {'e': '$e'}),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clear() {
    setState(() {
      _lastFile = null;
      _lastType = null;
      _statusMsg = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final recorder = ref.watch(standaloneRecorderProvider);
    final contacts = ref.watch(contactsProvider).valueOrNull ?? [];
    final destructive = Theme.of(context).colorScheme.error;
    final primary = Theme.of(context).colorScheme.primary;

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.videocam_outlined, color: primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'during_recordEvidence'.tr(),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (recorder.mode == StandaloneRecMode.video &&
                recorder.videoController != null &&
                recorder.videoController!.value.isInitialized)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CameraPreview(recorder.videoController!),
                ),
              ),
            if (recorder.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '⚠️ ${recorder.errorMessage}',
                  style: TextStyle(color: destructive, fontSize: 12),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: recorder.mode == StandaloneRecMode.video
                        ? null
                        : _toggleAudio,
                    icon: Icon(
                      recorder.mode == StandaloneRecMode.audio
                          ? Icons.mic_off
                          : Icons.mic,
                    ),
                    label: Text(
                      recorder.mode == StandaloneRecMode.audio
                          ? 'during_stopAudio'.tr()
                          : 'during_audioRec'.tr(),
                    ),
                    style: recorder.mode == StandaloneRecMode.audio
                        ? OutlinedButton.styleFrom(foregroundColor: destructive)
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: recorder.mode == StandaloneRecMode.audio
                        ? null
                        : _toggleVideo,
                    icon: Icon(
                      recorder.mode == StandaloneRecMode.video
                          ? Icons.videocam_off
                          : Icons.videocam,
                    ),
                    label: Text(
                      recorder.mode == StandaloneRecMode.video
                          ? 'during_stopVideo'.tr()
                          : 'during_videoRec'.tr(),
                    ),
                    style: recorder.mode == StandaloneRecMode.video
                        ? OutlinedButton.styleFrom(foregroundColor: destructive)
                        : null,
                  ),
                ),
              ],
            ),
            if (_lastFile != null) ...[
              const SizedBox(height: 12),
              const Divider(),
              Text(
                _statusMsg.isEmpty
                    ? 'during_recordingReady'.tr()
                    : _statusMsg,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _saveToGallery,
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: Text('during_saveDevice'.tr()),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busy || contacts.isEmpty
                          ? null
                          : _shareToContacts,
                      icon: const Icon(Icons.send_outlined, size: 18),
                      label: Text(
                        contacts.isEmpty
                            ? 'during_sendToContactsBtnEmpty'.tr()
                            : 'during_sendToContactsBtn'.tr(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _uploadToCloud,
                      icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                      label: Text('during_saveCloud'.tr()),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextButton(onPressed: _clear, child: Text('discard'.tr())),
                ],
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'during_recHint'.tr(),
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LocationHistoryCard extends ConsumerStatefulWidget {
  const _LocationHistoryCard();

  @override
  ConsumerState<_LocationHistoryCard> createState() =>
      _LocationHistoryCardState();
}

class _LocationHistoryCardState extends ConsumerState<_LocationHistoryCard> {
  final _geocoding = GeocodingRepository();
  final _names = <String, String>{};

  Future<void> _resolve(LocationSample sample) async {
    final key =
        '${sample.latitude.toStringAsFixed(5)},${sample.longitude.toStringAsFixed(5)}';
    if (_names.containsKey(key)) return;
    final name = await _geocoding.reverseGeocode(
      sample.latitude,
      sample.longitude,
    );
    if (mounted) setState(() => _names[key] = name);
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(locationHistoryProvider);
    final last5 = history.length > 5
        ? history.sublist(history.length - 5)
        : history;
    for (final s in last5) {
      _resolve(s);
    }
    final reversed = last5.reversed.toList();

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'during_locationHistory'.tr(),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (reversed.isEmpty)
              Text(
                'during_noLocationHistory'.tr(),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              )
            else
              ...reversed.asMap().entries.map((entry) {
                final i = entry.key;
                final sample = entry.value;
                final key =
                    '${sample.latitude.toStringAsFixed(5)},${sample.longitude.toStringAsFixed(5)}';
                final minutesAgo = DateTime.now()
                    .difference(sample.timestamp)
                    .inMinutes;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Chip(
                        label: Text(
                          i == 0
                              ? 'now'.tr()
                              : 'minutes_ago'.tr(
                                  namedArgs: {'n': '$minutesAgo'},
                                ),
                          style: const TextStyle(fontSize: 10),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _names[key] ?? '📍 ${'loading'.tr()}',
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
