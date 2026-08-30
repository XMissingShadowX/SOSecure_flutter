import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/glass.dart';
import '../widgets/tutorial_step_frame.dart';

// Réplica visual de _LiveSharingCard (before_tab_screen.dart) sin sus dependencias
// reales: el switch aquí es estado local puro (no liveSharingProvider) y el mapa es
// un CustomPainter estático — nada de flutter_map, red, ni permiso de ubicación.
class LiveLocationStep extends StatefulWidget {
  const LiveLocationStep({super.key});

  @override
  State<LiveLocationStep> createState() => _LiveLocationStepState();
}

class _LiveLocationStepState extends State<LiveLocationStep> {
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TutorialStepFrame(
      title: 'tutorial_locationTitle'.tr(),
      subtitle: 'tutorial_locationSubtitle'.tr(),
      child: GlassCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.share_location, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'tutorial_locationToggleLabel'.tr(),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Switch(
                    value: _sharing,
                    onChanged: (v) => setState(() => _sharing = v),
                  ),
                ],
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _sharing
                    ? Padding(
                        key: const ValueKey('map'),
                        padding: const EdgeInsets.only(top: 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppGlass.radius),
                          child: SizedBox(
                            height: 160,
                            width: double.infinity,
                            child: CustomPaint(
                              painter: _StaticMapPainter(
                                lineColor: theme.colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.25,
                                ),
                                pinColor: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey('empty')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Ilustración estática (una cuadrícula de calles estilizada + un pin "Tú") — no es
// un mapa real, solo transmite la idea visual sin ninguna dependencia de red.
class _StaticMapPainter extends CustomPainter {
  _StaticMapPainter({required this.lineColor, required this.pinColor});

  final Color lineColor;
  final Color pinColor;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2;
    for (var x = 0.0; x < size.width; x += size.width / 6) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
    for (var y = 0.0; y < size.height; y += size.height / 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    final center = Offset(size.width / 2, size.height / 2);
    final pinPaint = Paint()..color = pinColor;
    canvas.drawCircle(center, 8, pinPaint);
    canvas.drawCircle(
      center,
      16,
      Paint()..color = pinColor.withValues(alpha: 0.25),
    );
  }

  @override
  bool shouldRepaint(covariant _StaticMapPainter oldDelegate) =>
      oldDelegate.lineColor != lineColor || oldDelegate.pinColor != pinColor;
}
