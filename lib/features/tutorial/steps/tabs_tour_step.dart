import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/glass.dart';
import '../widgets/tutorial_step_frame.dart';

// Mismos íconos y orden que el NavigationBar real (app_shell_screen.dart:274-300):
// Home/Before/During/After/Support, cada uno con una línea explicando qué vive ahí.
class TabsTourStep extends StatefulWidget {
  const TabsTourStep({super.key});

  @override
  State<TabsTourStep> createState() => _TabsTourStepState();
}

class _TabsTourStepState extends State<TabsTourStep>
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tabs = [
      (Icons.home, 'nav_home'.tr(), 'tutorial_tabHomeDesc'.tr()),
      (Icons.route, 'nav_before'.tr(), 'tutorial_tabBeforeDesc'.tr()),
      (Icons.videocam, 'nav_during'.tr(), 'tutorial_tabDuringDesc'.tr()),
      (Icons.history, 'nav_after'.tr(), 'tutorial_tabAfterDesc'.tr()),
      (Icons.favorite, 'nav_support'.tr(), 'tutorial_tabSupportDesc'.tr()),
    ];

    return TutorialStepFrame(
      title: 'tutorial_tabsTitle'.tr(),
      subtitle: 'tutorial_tabsSubtitle'.tr(),
      child: Column(
        children: List.generate(tabs.length, (i) {
          final start = i * 0.14;
          final anim = CurvedAnimation(
            parent: _controller,
            curve: Interval(start, (start + 0.4).clamp(0, 1), curve: Curves.easeOut),
          );
          final (icon, label, desc) = tabs[i];
          return FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.08, 0),
                end: Offset.zero,
              ).animate(anim),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GlassCard(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(icon, color: theme.colorScheme.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text(
                                desc,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant,
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
            ),
          );
        }),
      ),
    );
  }
}
