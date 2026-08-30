import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/settings_provider.dart';
import '../widgets/tutorial_step_frame.dart';

const _holdDuration = Duration(milliseconds: 1000);

// Réplica visual fiel del botón SOS real (lib/features/during/sos_button.dart), misma
// duración de gesto (1000ms) y mismo anillo de progreso — pero maneja el hold con un
// AnimationController local en vez del Timer.periodic del original, por la decisión
// tomada de usar únicamente primitivas de animación nativas de Flutter en el tutorial.
//
// LÍMITE DE SEGURIDAD: este widget nunca debe leer/llamar sosProvider, RecorderController,
// ni ninguna API real — es una maqueta interactiva pura, para que completar la práctica
// jamás dispare una alerta SOS real ni grabación real.
class SosPracticeStep extends ConsumerStatefulWidget {
  const SosPracticeStep({super.key});

  @override
  ConsumerState<SosPracticeStep> createState() => _SosPracticeStepState();
}

class _SosPracticeStepState extends ConsumerState<SosPracticeStep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _holdController;
  bool _holding = false;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _holdController = AnimationController(vsync: this, duration: _holdDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() {
            _holding = false;
            _completed = true;
          });
        }
      });
  }

  @override
  void dispose() {
    _holdController.dispose();
    super.dispose();
  }

  void _startHold() {
    if (_completed) return;
    setState(() => _holding = true);
    _holdController.forward(from: 0);
  }

  void _endHold() {
    if (_completed) return;
    _holdController.stop();
    _holdController.value = 0;
    setState(() => _holding = false);
  }

  @override
  Widget build(BuildContext context) {
    final simpleMode = ref.watch(simpleModeProvider);
    final destructive = Theme.of(context).colorScheme.error;
    final outerSize = simpleMode ? 112.0 : 80.0;
    final innerSize = simpleMode ? 100.0 : 72.0;
    final iconSize = simpleMode ? 44.0 : 28.0;
    final labelFontSize = simpleMode ? 15.0 : 11.0;

    return TutorialStepFrame(
      title: 'tutorial_sosTitle'.tr(),
      subtitle: 'tutorial_sosSubtitle'.tr(),
      child: Column(
        children: [
          Semantics(
            button: true,
            label: 'tutorial_sosTitle'.tr(),
            hint: 'tutorial_sosHoldHint'.tr(),
            child: GestureDetector(
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
                      AnimatedBuilder(
                        animation: _holdController,
                        builder: (context, _) => SizedBox(
                          width: outerSize,
                          height: outerSize,
                          child: CircularProgressIndicator(
                            value: _holdController.value,
                            strokeWidth: 4,
                            color: Colors.white.withValues(alpha: 0.6),
                            backgroundColor: Colors.transparent,
                          ),
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
                            _completed ? Icons.check_rounded : Icons.warning_amber_rounded,
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
          ),
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Text(
              _completed
                  ? 'tutorial_sosPracticeCompleteLabel'.tr()
                  : (_holding
                        ? 'sos_holdingLabel'.tr()
                        : 'tutorial_sosHoldHint'.tr()),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: _completed ? Theme.of(context).colorScheme.primary : null,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'tutorial_sosSecretTapHint'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
