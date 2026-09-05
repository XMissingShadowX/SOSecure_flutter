import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/brand.dart';
import '../../../core/glass.dart';
import '../widgets/tutorial_step_frame.dart';

// Primer paso del tutorial — apertura de marca con una entrada fade/scale (no un
// texto estático) y el mismo logo que reaparece en DoneStep vía Hero(tag:
// 'sosecure-logo'), para que el carrusel abra y cierre con la misma pieza visual.
class WelcomeStep extends StatefulWidget {
  const WelcomeStep({super.key});

  @override
  State<WelcomeStep> createState() => _WelcomeStepState();
}

class _WelcomeStepState extends State<WelcomeStep> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scale = Tween<double>(
      begin: 0.85,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: AppGlass.easeSpring));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TutorialStepFrame(
      title: 'tutorial_welcomeTitle'.tr(),
      subtitle: 'tutorial_welcomeSubtitle'.tr(),
      child: Column(
        children: [
          FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: const Hero(
                tag: 'sosecure-logo',
                child: SosecureLogo(size: 96),
              ),
            ),
          ),
          const SizedBox(height: 24),
          FadeTransition(
            opacity: _fade,
            child: Text(
              'tutorial_welcomeBody'.tr(),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
