import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../widgets/tutorial_step_frame.dart';

// Ilustra la secuencia real de activación de sos_button.dart (grabación, GPS,
// notificación a contactos) con un reveal escalonado — puramente ilustrativo,
// sin cámara/ubicación reales ni llamadas a providers.
class SosActivationStep extends StatefulWidget {
  const SosActivationStep({super.key});

  @override
  State<SosActivationStep> createState() => _SosActivationStepState();
}

class _SosActivationStepState extends State<SosActivationStep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Animation<double> _reveal(double start, double end) {
    return CurvedAnimation(
      parent: _controller,
      curve: Interval(start, end, curve: Curves.easeOut),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = [
      (Icons.videocam, 'tutorial_activationRecordingLabel'.tr()),
      (Icons.location_on, 'tutorial_activationLocationLabel'.tr()),
      (Icons.people, 'tutorial_activationNotifyLabel'.tr()),
    ];

    return TutorialStepFrame(
      title: 'tutorial_activationTitle'.tr(),
      subtitle: 'tutorial_activationSubtitle'.tr(),
      child: Column(
        children: List.generate(items.length, (i) {
          final start = i * 0.25;
          final anim = _reveal(start, start + 0.5);
          final (icon, label) = items[i];
          return FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.15),
                end: Offset.zero,
              ).animate(anim),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: theme.colorScheme.error),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(label, style: const TextStyle(fontSize: 15)),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
