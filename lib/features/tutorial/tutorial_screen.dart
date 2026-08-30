import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/glass.dart';
import '../../state/tutorial_provider.dart';
import 'steps/add_contact_step.dart';
import 'steps/done_step.dart';
import 'steps/live_location_step.dart';
import 'steps/sos_activation_step.dart';
import 'steps/sos_practice_step.dart';
import 'steps/tabs_tour_step.dart';
import 'steps/welcome_step.dart';

// Carrusel de bienvenida mostrado una sola vez a cuentas recién registradas (ver
// tutorial_provider.dart), o bajo demanda desde Ajustes ("Reproducir tutorial de
// nuevo", replay: true). Andamiaje de navegación (PageView + puntos de progreso +
// Saltar/Atrás/Siguiente) — el contenido de cada paso vive en steps/*.dart.
const _stepCount = 7;

class TutorialScreen extends ConsumerStatefulWidget {
  const TutorialScreen({super.key, this.replay = false});

  final bool replay;

  @override
  ConsumerState<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends ConsumerState<TutorialScreen> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLast => _index == _stepCount - 1;

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: AppGlass.easeSpring,
    );
  }

  void _back() {
    _controller.previousPage(
      duration: const Duration(milliseconds: 320),
      curve: AppGlass.easeSpring,
    );
  }

  Future<void> _finish() async {
    await ref.read(tutorialSeenProvider.notifier).markSeen();
    if (!mounted) return;
    if (widget.replay) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: _isLast
                      ? const SizedBox(height: 48)
                      : TextButton(
                          onPressed: _finish,
                          child: Text('tutorial_skip'.tr()),
                        ),
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _controller,
                  onPageChanged: (i) => setState(() => _index = i),
                  children: const [
                    WelcomeStep(),
                    AddContactStep(),
                    SosPracticeStep(),
                    SosActivationStep(),
                    LiveLocationStep(),
                    TabsTourStep(),
                    DoneStep(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  children: [
                    _ProgressDots(index: _index, count: _stepCount),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        if (_index > 0)
                          TextButton(
                            onPressed: _back,
                            child: Text('tutorial_back'.tr()),
                          )
                        else
                          const SizedBox.shrink(),
                        const Spacer(),
                        FilledButton(
                          onPressed: _next,
                          child: Text(
                            _isLast
                                ? 'tutorial_startUsingApp'.tr()
                                : 'tutorial_next'.tr(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.index, required this.count});

  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Semantics(
      label: 'tutorial_stepIndicator'.tr(
        namedArgs: {'current': '${index + 1}', 'total': '$count'},
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(count, (i) {
          final active = i == index;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: active ? 20 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: active ? color : color.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(3),
            ),
          );
        }),
      ),
    );
  }
}
