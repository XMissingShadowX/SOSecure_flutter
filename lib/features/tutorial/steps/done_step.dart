import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/brand.dart';
import '../widgets/tutorial_step_frame.dart';

// Cierre del carrusel — Hero(tag: 'sosecure-logo') hace bookend con WelcomeStep para
// una transición de marca al pasar del primer al último paso. El CTA real ("empezar a
// usar la app") vive en la barra inferior compartida de TutorialScreen, no aquí.
class DoneStep extends StatelessWidget {
  const DoneStep({super.key});

  @override
  Widget build(BuildContext context) {
    return TutorialStepFrame(
      title: 'tutorial_doneTitle'.tr(),
      subtitle: 'tutorial_doneSubtitle'.tr(),
      child: const Hero(
        tag: 'sosecure-logo',
        child: SosecureLogo(size: 96),
      ),
    );
  }
}
