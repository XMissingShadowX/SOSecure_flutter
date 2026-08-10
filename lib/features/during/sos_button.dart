import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/live_broadcast_provider.dart';
import '../../state/location_provider.dart';
import '../../state/recorder_controller.dart';
import '../../state/settings_provider.dart';
import '../../state/sos_provider.dart';

const _holdDuration = Duration(milliseconds: 1000);

// Cuánto permanece visible la etiqueta "Mantén presionado para SOS" antes de
// deslizarse hacia abajo. Es una pista de descubrimiento: hace falta las
// primeras veces, pero estorba de forma permanente una vez aprendido el gesto.
const _labelVisibleDuration = Duration(seconds: 10);
const _labelExitDuration = Duration(milliseconds: 320);
const _secretTapCount = 5;
const _secretTapWindow = Duration(milliseconds: 3000);

// Puerto de components/sos-button.tsx (sin streaming en vivo, ver addendum de Fase 2).
// Botón flotante: mantener presionado 1s, o 5 toques rápidos en la franja invisible
// superior (gesto secreto), activan el SOS. Cuando sosActive, muestra el panel de
// alerta con el estado de RecorderController y opciones de finalizar/falsa alarma.
class SosButton extends ConsumerStatefulWidget {
  // El botón flotante idle se oculta en pantallas cuya UI ya usa ese espacio
  // (ej. la caja de mensajes del chat de Apoyo) — el panel de alerta activa
  // sigue mostrándose siempre, sin importar esta bandera, porque un SOS activo
  // no debe poder ocultarse cambiando de tab.
  final bool hideIdleButton;
  const SosButton({super.key, this.hideIdleButton = false});

  @override
  ConsumerState<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends ConsumerState<SosButton> {
  double _holdProgress = 0;
  bool _holding = false;
  Timer? _progressTimer;
  final List<DateTime> _tapTimes = [];

  bool _labelVisible = true;
  Timer? _labelTimer;

  @override
  void initState() {
    super.initState();
    _startLabelTimer();
  }

  /// Muestra la etiqueta y programa su salida a los 10 s. Se rearma cada vez que
  /// la etiqueta vuelve a ser relevante (al soltar el botón, o al reaparecer el
  /// botón tras cancelar un SOS o cerrar el chat), no solo al montar el widget.
  void _startLabelTimer() {
    _labelTimer?.cancel();
    if (mounted && !_labelVisible) setState(() => _labelVisible = true);
    _labelTimer = Timer(_labelVisibleDuration, () {
      if (mounted) setState(() => _labelVisible = false);
    });
  }

  @override
  void didUpdateWidget(SosButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // El botón estaba oculto (chat abierto o tab de Apoyo) y vuelve a aparecer:
    // la pista se muestra otra vez desde cero.
    if (oldWidget.hideIdleButton && !widget.hideIdleButton) _startLabelTimer();
  }

  void _startHold() {
    if (ref.read(sosProvider).active) return;
    // Mientras se mantiene presionado la etiqueta cambia a "Mantén
    // presionando…" y es la única señal de progreso textual, así que se
    // reasoma aunque ya se hubiera ocultado.
    _labelTimer?.cancel();
    setState(() {
      _labelVisible = true;
      _holding = true;
      _holdProgress = 0;
    });
    final start = DateTime.now();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      final elapsed = DateTime.now().difference(start);
      setState(() {
        _holdProgress = (elapsed.inMilliseconds / _holdDuration.inMilliseconds)
            .clamp(0, 1)
            .toDouble();
      });
      if (elapsed >= _holdDuration) {
        timer.cancel();
        setState(() {
          _holding = false;
          _holdProgress = 0;
        });
        ref.read(sosProvider.notifier).activate();
      }
    });
  }

  void _endHold() {
    _progressTimer?.cancel();
    setState(() {
      _holding = false;
      _holdProgress = 0;
    });
    _startLabelTimer();
  }

  void _onSecretTap() {
    final now = DateTime.now();
    _tapTimes.removeWhere((t) => now.difference(t) > _secretTapWindow);
    _tapTimes.add(now);
    if (_tapTimes.length >= _secretTapCount) {
      _tapTimes.clear();
      ref.read(sosProvider.notifier).activate();
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _labelTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sos = ref.watch(sosProvider);
    // Al cancelar un SOS el botón inactivo vuelve a montarse: se reinicia la
    // cuenta para que la pista acompañe otra vez y luego se retire.
    ref.listen(sosProvider, (prev, next) {
      if ((prev?.active ?? false) && !next.active) _startLabelTimer();
    });
    final destructive = Theme.of(context).colorScheme.error;
    final simpleMode = ref.watch(simpleModeProvider);

    if (sos.active) {
      return _SosActivePanel(sos: sos);
    }

    if (widget.hideIdleButton) {
      return const SizedBox.shrink();
    }

    // Puerto de las medidas simpleMode de sos-button.tsx: botón 7rem/112px
    // (vs 5rem/80px normal), ícono w-12/48px (vs w-8/32px), texto text-base
    // (vs text-xs), y más separación del borde inferior (bottom-24 vs bottom-20).
    final outerSize = simpleMode ? 112.0 : 80.0;
    final innerSize = simpleMode ? 100.0 : 72.0;
    final iconSize = simpleMode ? 44.0 : 28.0;
    final labelFontSize = simpleMode ? 15.0 : 11.0;
    final bottomOffset = simpleMode ? 32.0 : 24.0;

    return Stack(
      children: [
        // iOS no expone una API pública para interceptar los botones físicos de
        // volumen (a diferencia de Android, VolumeButtonChannel/MainActivity.kt) —
        // este botón flotante secundario es el sustituto de esa vía de activación
        // en iOS, siempre visible además del botón SOS principal.
        if (Platform.isIOS) const _IosSecondaryButton(),
        Positioned(
          left: 0,
          right: 0,
          bottom: bottomOffset,
          child: Column(
            children: [
              // Franja invisible del gesto secreto (5 toques en 3s), equivalente al
              // <div onClick={handleSecretTap}> oculto encima del botón en la web.
              GestureDetector(
                onTap: _onSecretTap,
                child: Container(
                  width: 80,
                  height: 32,
                  color: Colors.transparent,
                ),
              ),
              GestureDetector(
                onLongPressStart: (_) => _startHold(),
                onLongPressEnd: (_) => _endHold(),
                onLongPressCancel: _endHold,
                child: SizedBox(
                  width: outerSize,
                  height: outerSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (_holding)
                        SizedBox(
                          width: outerSize,
                          height: outerSize,
                          child: CircularProgressIndicator(
                            value: _holdProgress,
                            strokeWidth: 4,
                            color: Colors.white.withValues(alpha: 0.6),
                            backgroundColor: Colors.transparent,
                          ),
                        ),
                      Container(
                        width: innerSize,
                        height: innerSize,
                        decoration: BoxDecoration(
                          color: destructive,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: destructive.withValues(alpha: 0.5),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.white,
                              size: iconSize,
                            ),
                            Text(
                              'SOS',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: labelFontSize,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Pasados 10 s la pista se desliza hacia abajo y se desvanece, y
              // al mismo tiempo deja de ocupar alto — como la Column está
              // anclada al borde inferior (Positioned(bottom:)), esa altura que
              // se libera hace que el botón SOS baje acompañando a la etiqueta.
              //
              // Un AnimatedSlide/AnimatedOpacity a secas no bastaba: mueven y
              // desvanecen el pintado pero conservan el espacio en el layout, y
              // el botón se quedaba clavado. El heightFactor animado del Align
              // es lo que colapsa el hueco; el Transform.translate es el
              // deslizamiento visual, y no se recorta (sin ClipRect) para que la
              // etiqueta se siga viendo salir por encima de la barra inferior.
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 1, end: _labelVisible ? 1.0 : 0.0),
                duration: _labelExitDuration,
                curve: Curves.easeInCubic,
                builder: (context, t, child) => Align(
                  alignment: Alignment.topCenter,
                  heightFactor: t,
                  child: Transform.translate(
                    offset: Offset(0, (1 - t) * 28),
                    child: Opacity(opacity: t, child: child),
                  ),
                ),
                // IgnorePointer evita que la etiqueta capture toques mientras
                // sale o ya invisible — queda sobre la barra de navegación.
                child: IgnorePointer(
                  ignoring: !_labelVisible,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child:
                        // Solo la etiqueta de texto lleva el desenfoque de fondo — el botón
                        // en sí queda tal cual, sin blur (ajuste pedido tras ver el diseño).
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: destructive.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                _holding
                                    ? 'sos_holdingLabel'.tr()
                                    : 'sos_holdToActivateShort'.tr(),
                                style: TextStyle(
                                  fontSize: simpleMode ? 14 : 12,
                                  fontWeight: FontWeight.w500,
                                  color: destructive,
                                ),
                              ),
                            ),
                          ),
                        ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Botón secundario visible en iOS: mismo gesto de mantener presionado 1s que
// el botón SOS principal, en un ícono discreto de esquina superior — no hay
// confirmación intermedia porque el mismo hold ya evita activaciones por
// toques accidentales.
class _IosSecondaryButton extends ConsumerStatefulWidget {
  const _IosSecondaryButton();

  @override
  ConsumerState<_IosSecondaryButton> createState() =>
      _IosSecondaryButtonState();
}

class _IosSecondaryButtonState extends ConsumerState<_IosSecondaryButton> {
  double _holdProgress = 0;
  Timer? _progressTimer;

  void _startHold() {
    if (ref.read(sosProvider).active) return;
    final start = DateTime.now();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      final elapsed = DateTime.now().difference(start);
      setState(() {
        _holdProgress = (elapsed.inMilliseconds / _holdDuration.inMilliseconds)
            .clamp(0, 1)
            .toDouble();
      });
      if (elapsed >= _holdDuration) {
        timer.cancel();
        setState(() => _holdProgress = 0);
        ref.read(sosProvider.notifier).activate();
      }
    });
  }

  void _endHold() {
    _progressTimer?.cancel();
    setState(() => _holdProgress = 0);
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final destructive = Theme.of(context).colorScheme.error;
    return Positioned(
      top: 12,
      right: 12,
      child: GestureDetector(
        onLongPressStart: (_) => _startHold(),
        onLongPressEnd: (_) => _endHold(),
        onLongPressCancel: _endHold,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_holdProgress > 0)
                CircularProgressIndicator(
                  value: _holdProgress,
                  strokeWidth: 3,
                  color: destructive.withValues(alpha: 0.7),
                  backgroundColor: Colors.transparent,
                ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: destructive.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: destructive.withValues(alpha: 0.4)),
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: destructive,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Puerto del toggle de transmisión en vivo (Fase 6b) — ver
// live_broadcast_provider.dart para la implementación (clips segmentados en
// vez de chunks WebM, por limitaciones del paquete `camera`). Solo aparece
// si la grabación ya está activa, ya que reutiliza su CameraController.
class _LiveBroadcastToggle extends ConsumerWidget {
  final String? alertId;
  const _LiveBroadcastToggle({required this.alertId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(liveBroadcastProvider);
    final recorder = ref.watch(recorderProvider);
    final canGoLive =
        alertId != null && recorder.status == RecorderStatus.recording;
    final destructive = Theme.of(context).colorScheme.error;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: live.live ? Colors.white : destructive,
              backgroundColor: live.live ? destructive : null,
              side: BorderSide(color: destructive),
            ),
            onPressed: !canGoLive
                ? null
                : () {
                    if (live.live) {
                      ref.read(liveBroadcastProvider.notifier).stop();
                    } else {
                      ref.read(liveBroadcastProvider.notifier).start(alertId!);
                    }
                  },
            icon: Icon(
              live.live ? Icons.stop_circle_outlined : Icons.podcasts,
              size: 18,
            ),
            label: Text(
              live.live
                  ? 'sos_liveBroadcasting'.tr(
                      namedArgs: {'n': '${live.segmentsSent}'},
                    )
                  : 'sos_liveBroadcastStart'.tr(),
            ),
          ),
        ),
        if (live.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              live.error!,
              style: TextStyle(color: destructive, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

class _SosActivePanel extends ConsumerWidget {
  final SosState sos;
  const _SosActivePanel({required this.sos});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destructive = Theme.of(context).colorScheme.error;
    final surface = Theme.of(context).colorScheme.surface;
    final location = ref.watch(locationWatcherProvider);
    final recorder = ref.watch(recorderProvider);

    return Positioned.fill(
      child: Stack(
        children: [
          // Desenfoque del contenido de fondo (la tab que estaba activa antes del SOS)
          // en vez de un simple tinte semitransparente — evita que el panel se
          // confunda visualmente con lo que hay detrás.
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(color: destructive.withValues(alpha: 0.15)),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                // Todo el contenido va dentro de una sola tarjeta opaca con borde
                // destacado, en vez de flotar directo sobre el fondo desenfocado.
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: destructive.withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: destructive,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'sos_active'.tr(),
                            style: TextStyle(
                              color: destructive,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black,
                              border: Border.all(color: destructive, width: 2),
                            ),
                            child: _CameraPreview(recorder: recorder),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (location.hasCoordinates)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'sos_locationLabel'.tr(),
                                style: const TextStyle(fontSize: 12),
                              ),
                              Text(
                                '${location.latitude!.toStringAsFixed(6)}, ${location.longitude!.toStringAsFixed(6)}',
                                style: const TextStyle(fontFamily: 'monospace'),
                              ),
                            ],
                          ),
                        ),
                      // Sin coordenadas todavía no se puede registrar la alerta
                      // (lat/long son NOT NULL). Se sigue reintentando solo, pero
                      // se avisa para que nadie asuma que sus contactos ya fueron
                      // notificados mientras tanto.
                      if (sos.locationPending)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: destructive.withValues(alpha: 0.15),
                            border: Border.all(color: destructive),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: destructive,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'sos_locationPending'.tr(),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: destructive,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 12),
                      if (sos.contactsNotified.isNotEmpty)
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          alignment: WrapAlignment.center,
                          children: sos.contactsNotified
                              .map(
                                (name) => Chip(
                                  label: Text(
                                    name,
                                    style: TextStyle(color: destructive),
                                  ),
                                  backgroundColor: destructive.withValues(
                                    alpha: 0.15,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      const SizedBox(height: 12),
                      _LiveBroadcastToggle(alertId: sos.alert?.id),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: sos.saving
                              ? null
                              : () => ref
                                    .read(sosProvider.notifier)
                                    .saveAndClose(),
                          icon: sos.saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check),
                          label: Text(
                            sos.saving ? 'sos_saving'.tr() : 'sos_save'.tr(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: destructive,
                            side: BorderSide(color: destructive),
                          ),
                          onPressed: sos.saving
                              ? null
                              : () => _confirmCancel(context, ref),
                          icon: const Icon(Icons.close),
                          label: Text('sos_falseAlarm'.tr()),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmCancel(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('sos_falseAlarmTitle'.tr()),
        content: Text('sos_stopRecordingDesc'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('sos_keepActive'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(sosProvider.notifier).cancel();
            },
            child: Text('sos_confirmFalse'.tr()),
          ),
        ],
      ),
    );
  }
}

// Vista previa real de la cámara mientras graba — antes mostraba solo un ícono
// estático de placeholder. `CameraController.buildPreview()` da el feed en vivo;
// se recorta a como si fuera `object-fit: cover` (igual que el <video> de la web)
// porque el aspect ratio nativo de la cámara casi nunca coincide con 16:9 exacto.
class _CameraPreview extends StatelessWidget {
  final RecorderState recorder;
  const _CameraPreview({required this.recorder});

  @override
  Widget build(BuildContext context) {
    final controller = recorder.controller;
    if (recorder.status == RecorderStatus.error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            recorder.errorMessage ?? 'sos_recordingUnavailable'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: controller.value.previewSize?.height ?? 1,
        height: controller.value.previewSize?.width ?? 1,
        child: CameraPreview(controller),
      ),
    );
  }
}
