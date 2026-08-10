import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../core/brand.dart';
import '../../core/glass.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

// Puerto de components/permission-gate.tsx. Solo geolocalización y notificaciones se piden
// aquí (requeridas); cámara/mic se piden bajo demanda al activar la grabación SOS (Fase 2).
class PermissionGateScreen extends StatefulWidget {
  const PermissionGateScreen({super.key});

  @override
  State<PermissionGateScreen> createState() => _PermissionGateScreenState();
}

class _PermissionGateScreenState extends State<PermissionGateScreen> {
  PermissionStatus _location = PermissionStatus.denied;
  PermissionStatus _notifications = PermissionStatus.denied;
  bool _requesting = false;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _refreshStatuses();
  }

  Future<void> _refreshStatuses() async {
    final location = await Permission.locationWhenInUse.status;
    final notifications = await Permission.notification.status;
    if (!mounted) return;
    setState(() {
      _location = location;
      _notifications = notifications;
      _checked = true;
    });
  }

  bool get _hasRequired => _location.isGranted && _notifications.isGranted;
  bool get _hardDenied =>
      _location.isPermanentlyDenied || _notifications.isPermanentlyDenied;

  Future<void> _requestAll() async {
    setState(() => _requesting = true);
    await [Permission.locationWhenInUse, Permission.notification].request();
    await _refreshStatuses();
    if (mounted) setState(() => _requesting = false);
  }

  void _continueAnyway() => context.go('/pin-lock');

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_hasRequired) {
      // Micro-delay para evitar navegar en medio del build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/pin-lock');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SosecureLogo(size: 72),
                  const SizedBox(height: 8),
                  Text(
                    'perm_gateTitle'.tr(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'perm_gateSubtitle'.tr(),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  _PermissionTile(
                    icon: Icons.location_on,
                    label: 'perm_locationLabel'.tr(),
                    desc: 'perm_locationDesc'.tr(),
                    granted: _location.isGranted,
                  ),
                  const SizedBox(height: 8),
                  _PermissionTile(
                    icon: Icons.notifications,
                    label: 'perm_notificationsLabel'.tr(),
                    desc: 'perm_notificationsDesc'.tr(),
                    granted: _notifications.isGranted,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'perm_askedLater'.tr(),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.camera_alt, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'perm_cameraDesc'.tr(),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.mic, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'perm_micDesc'.tr(),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_hardDenied) ...[
                    Text(
                      'perm_blockedMessage'.tr(),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => openAppSettings(),
                      child: Text('perm_openSettings'.tr()),
                    ),
                  ] else
                    FilledButton(
                      onPressed: _requesting ? null : _requestAll,
                      child: _requesting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text('perm_grantBtn'.tr()),
                    ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _continueAnyway,
                    child: Text('perm_continueWithout'.tr()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String desc;
  final bool granted;

  const _PermissionTile({
    required this.icon,
    required this.label,
    required this.desc,
    required this.granted,
  });

  @override
  Widget build(BuildContext context) {
    final safe = Theme.of(context).colorScheme.tertiary;
    // Color.alphaBlend contra la superficie real — un color translúcido
    // directo en `color:` de Card se compone mal con el tinte/sombra de
    // Material 3 y se ve oscuro en modo claro en vez de un tinte suave.
    return GlassCard(
      color: granted
          ? Color.alphaBlend(
              safe.withValues(alpha: 0.08),
              Theme.of(context).colorScheme.surface,
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: granted ? safe : Colors.grey),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 6),
                      if (!granted)
                        Text(
                          'perm_required'.tr(),
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                  Text(
                    desc,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            Icon(
              granted ? Icons.check_circle : Icons.error_outline,
              color: granted ? safe : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}
