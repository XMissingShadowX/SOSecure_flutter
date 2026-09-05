import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/pin_api.dart';
import '../../state/sos_provider.dart';
import '../../state/tutorial_provider.dart';
import '../during/sos_button.dart';

// Puerto de components/pin-lock.tsx. Verificación 100% server-side vía PinApi — este
// widget nunca calcula ni compara hashes localmente.
class PinLockScreen extends ConsumerStatefulWidget {
  const PinLockScreen({super.key});

  @override
  ConsumerState<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends ConsumerState<PinLockScreen> {
  final _api = PinApi();
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _loading = true;
  PinConfig? _config;
  String? _error;
  bool _verifying = false;
  int? _lockedOutSeconds;
  bool _resetRequested = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final config = await _api.getConfig();
      if (!mounted) return;
      setState(() {
        _config = config;
        _loading = false;
      });
      // Sin PIN configurado o deshabilitado -> no hay nada que bloquear, pasar directo.
      if (!config.pinEnabled || !config.pinConfigured) {
        _goToShell();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '${'pin_statusError'.tr()} $e';
        _loading = false;
      });
    }
  }

  void _goToShell() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final seen = await ref.read(tutorialSeenProvider.notifier).refresh();
      if (!mounted) return;
      context.go(seen ? '/' : '/tutorial');
    });
  }

  Future<bool> _isOffline() async {
    final results = await Connectivity().checkConnectivity();
    return results.contains(ConnectivityResult.none);
  }

  Future<void> _submit() async {
    if (_pinController.text.length < 4) return;
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      final result = await _api.verify(_pinController.text);
      if (!mounted) return;
      if (result.ok) {
        _goToShell();
        return;
      }
      if (result.lockedOutSeconds != null) {
        setState(() => _lockedOutSeconds = result.lockedOutSeconds);
      } else {
        setState(() => _error = 'pin_incorrectSimple'.tr());
      }
      _pinController.clear();
    } catch (e) {
      // La verificación del PIN (bcrypt.compare) vive solo en el servidor —
      // sin red, verify() siempre falla acá. Mostrar la excepción cruda
      // ("ClientException: Failed to fetch...") no le dice nada útil a
      // alguien en una situación de estrés; si de verdad no hay conexión, se
      // prefiere el mensaje claro sobre el genérico de "error al verificar".
      final offline = await _isOffline();
      setState(() {
        _error = offline
            ? 'pin_offlineNeedsConnection'.tr()
            : '${'pin_verifyError'.tr()}$e';
      });
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _forgotPin() async {
    setState(() => _verifying = true);
    try {
      await _api.requestReset();
      if (mounted) setState(() => _resetRequested = true);
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // El SOS por botón de volumen (VolumeSosDetector.kt) y el tile de Ajustes
    // Rápidos (SosTileService.kt) ya activan sosProvider directamente, sin
    // pasar por ninguna pantalla — este mismo SosButton reutilizado aquí les
    // da paridad al botón visible: alguien sin conexión (offline, el PIN no
    // se puede verificar sin red — ver PinApi.getConfig()) igual puede pedir
    // ayuda sin necesitar desbloquear. Contactos/historial/chat, lo único que
    // el PIN protege de verdad, siguen fuera de alcance hasta desbloquear.
    // Bug real encontrado en pruebas: SosButton se dibuja ENCIMA de esta
    // pantalla (no la reemplaza), así que el TextField del PIN sigue montado
    // y con el teclado enfocado por debajo aunque el panel de "SOS activo" lo
    // tape por completo. Android seguía mostrando la decoración de
    // composición del teclado (un subrayado punteado) sobre lo que fuera que
    // estuviera pintado encima en ese momento. Soltar el foco apenas se
    // activa el SOS evita que el teclado siga "opinando" sobre un campo que
    // ya no se ve — buena práctica igual, aunque no era la causa real del
    // texto amarillo/subrayado/gigante reportado en pruebas (ver abajo).
    ref.listen(sosProvider, (previous, next) {
      if (next.active && !(previous?.active ?? false)) {
        FocusScope.of(context).unfocus();
      }
    });
    // Causa real de ese bug: SosButton quedaba como HERMANO del Scaffold de
    // _buildScaffold() dentro del Stack, no como su hijo — sin un ancestro
    // Material, sus Text sin `decoration`/`fontSize` explícitos caían al
    // estilo de repuesto de Flutter para texto sin contexto de estilo válido
    // (amarillo, subrayado, tamaño crudo de plataforma). Envolver todo en un
    // Material transparente le da ese ancestro sin pintar nada por su cuenta
    // (el Scaffold de adentro ya pinta el fondo real).
    return Material(
      color: Colors.transparent,
      child: Stack(children: [_buildScaffold(context), const SosButton()]),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    // Fail-closed: mientras no sepamos el estado del PIN, no renderizar nada del shell.
    if (_loading) {
      return const Scaffold(body: SizedBox.shrink());
    }
    // Si _config sigue null tras el fetch fue porque _loadConfig() cayó en el catch —
    // hay que mostrar el error, no quedarse en blanco (bug real: antes esto devolvía
    // el mismo SizedBox.shrink() de "no hay PIN configurado", dejando la app
    // silenciosamente en blanco para siempre ante cualquier falla de red/API).
    if (_config == null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _error ?? 'pin_statusError'.tr(),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => setState(() {
                      _loading = true;
                      _error = null;
                      _loadConfig();
                    }),
                    child: Text('retry'.tr()),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (!_config!.pinEnabled || !_config!.pinConfigured) {
      return const Scaffold(body: SizedBox.shrink());
    }

    if (_resetRequested) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.mark_email_read_outlined, size: 56),
                  const SizedBox(height: 16),
                  Text(
                    'pin_resetLinkSent'.tr(),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final locked = _lockedOutSeconds != null;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock,
                  size: 48,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  'pin_enter'.tr(),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                // El estado "PIN activado" es el último conocido (sin red no
                // se pudo confirmar ahora) — la verificación en sí sigue
                // exigiendo conexión porque el bcrypt.compare vive solo en el
                // servidor, así que esto es solo para que el usuario entienda
                // por qué no puede desbloquear en vez de ver un error genérico.
                if (_config?.fromCache == true) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.cloud_off,
                        size: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'pin_offlineNeedsConnection'.tr(),
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: _pinController,
                    enabled: !locked && !_verifying,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    textAlign: TextAlign.center,
                    maxLength: 8,
                    style: const TextStyle(fontSize: 24, letterSpacing: 8),
                    decoration: const InputDecoration(counterText: ''),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                if (locked)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'pin_lockedOutFor'.tr(
                        namedArgs: {'seconds': '$_lockedOutSeconds'},
                      ),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  )
                else if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: (locked || _verifying) ? null : _submit,
                  child: _verifying
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text('unlock'.tr()),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _verifying ? null : _forgotPin,
                  child: Text('pin_forgot'.tr()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
