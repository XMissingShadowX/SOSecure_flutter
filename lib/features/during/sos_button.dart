import 'dart:async';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/location_provider.dart';
import '../../state/recorder_controller.dart';
import '../../state/sos_provider.dart';

const _holdDuration = Duration(milliseconds: 1000);
const _secretTapCount = 5;
const _secretTapWindow = Duration(milliseconds: 3000);

// Puerto de components/sos-button.tsx (sin streaming en vivo, ver addendum de Fase 2).
// Botón flotante: mantener presionado 1s, o 5 toques rápidos en la franja invisible
// superior (gesto secreto), activan el SOS. Cuando sosActive, muestra el panel de
// alerta con el estado de RecorderController y opciones de finalizar/falsa alarma.
class SosButton extends ConsumerStatefulWidget {
  const SosButton({super.key});

  @override
  ConsumerState<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends ConsumerState<SosButton> {
  double _holdProgress = 0;
  bool _holding = false;
  Timer? _progressTimer;
  final List<DateTime> _tapTimes = [];

  void _startHold() {
    if (ref.read(sosProvider).active) return;
    setState(() {
      _holding = true;
      _holdProgress = 0;
    });
    final start = DateTime.now();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      final elapsed = DateTime.now().difference(start);
      setState(() {
        _holdProgress = (elapsed.inMilliseconds / _holdDuration.inMilliseconds).clamp(0, 1).toDouble();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sos = ref.watch(sosProvider);
    final destructive = Theme.of(context).colorScheme.error;

    if (sos.active) {
      return _SosActivePanel(sos: sos);
    }

    return Positioned(
      left: 0,
      right: 0,
      bottom: 24,
      child: Column(
        children: [
          // Franja invisible del gesto secreto (5 toques en 3s), equivalente al
          // <div onClick={handleSecretTap}> oculto encima del botón en la web.
          GestureDetector(
            onTap: _onSecretTap,
            child: Container(width: 80, height: 32, color: Colors.transparent),
          ),
          GestureDetector(
            onLongPressStart: (_) => _startHold(),
            onLongPressEnd: (_) => _endHold(),
            onLongPressCancel: _endHold,
            child: SizedBox(
              width: 80,
              height: 80,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_holding)
                    SizedBox(
                      width: 80,
                      height: 80,
                      child: CircularProgressIndicator(
                        value: _holdProgress,
                        strokeWidth: 4,
                        color: Colors.white.withValues(alpha: 0.6),
                        backgroundColor: Colors.transparent,
                      ),
                    ),
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: destructive,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: destructive.withValues(alpha: 0.5), blurRadius: 24, offset: const Offset(0, 8))],
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
                        Text('SOS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Solo la etiqueta de texto lleva el desenfoque de fondo — el botón
          // en sí queda tal cual, sin blur (ajuste pedido tras ver el diseño).
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: destructive.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(999)),
                child: Text(
                  _holding ? 'Manteniendo...' : 'Mantén presionado para SOS',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: destructive),
                ),
              ),
            ),
          ),
        ],
      ),
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
                    border: Border.all(color: destructive.withValues(alpha: 0.4), width: 1.5),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 12))],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(width: 10, height: 10, decoration: BoxDecoration(color: destructive, shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Text('SOS ACTIVO', style: TextStyle(color: destructive, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            decoration: BoxDecoration(color: Colors.black, border: Border.all(color: destructive, width: 2)),
                            child: _CameraPreview(recorder: recorder),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (location.hasCoordinates)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Ubicación', style: TextStyle(fontSize: 12)),
                              Text('${location.latitude!.toStringAsFixed(6)}, ${location.longitude!.toStringAsFixed(6)}', style: const TextStyle(fontFamily: 'monospace')),
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
                              .map((name) => Chip(label: Text(name, style: TextStyle(color: destructive)), backgroundColor: destructive.withValues(alpha: 0.15)))
                              .toList(),
                        ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: sos.saving ? null : () => ref.read(sosProvider.notifier).saveAndClose(),
                          icon: sos.saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
                          label: Text(sos.saving ? 'Guardando...' : 'Guardar y cerrar'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(foregroundColor: destructive, side: BorderSide(color: destructive)),
                          onPressed: sos.saving ? null : () => _confirmCancel(context, ref),
                          icon: const Icon(Icons.close),
                          label: const Text('Fue una falsa alarma'),
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
        title: const Text('¿Confirmar falsa alarma?'),
        content: const Text('Se detendrá la grabación y se eliminará la alerta.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Mantener activo')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(sosProvider.notifier).cancel();
            },
            child: const Text('Sí, cancelar'),
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
            recorder.errorMessage ?? 'Grabación no disponible',
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
