import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/pin_api.dart';

// Puerto de components/pin-lock.tsx. Verificación 100% server-side vía PinApi — este
// widget nunca calcula ni compara hashes localmente.
class PinLockScreen extends StatefulWidget {
  const PinLockScreen({super.key});

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen> {
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
        _error = 'No se pudo verificar el estado del PIN: $e';
        _loading = false;
      });
    }
  }

  void _goToShell() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go('/');
    });
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
        setState(() => _error = 'PIN incorrecto');
      }
      _pinController.clear();
    } catch (e) {
      setState(() => _error = 'Error al verificar: $e');
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
    // Fail-closed: mientras no sepamos el estado del PIN, no renderizar nada del shell.
    if (_loading) {
      return const Scaffold(body: SizedBox.shrink());
    }
    if (_config == null || !_config!.pinEnabled || !_config!.pinConfigured) {
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
                  const Text(
                    'Te enviamos un enlace a tu correo para confirmar el reseteo del PIN.',
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
                Icon(Icons.lock, size: 48, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 12),
                const Text('Ingresa tu PIN',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
                      'Demasiados intentos. Espera ${_lockedOutSeconds}s.',
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  )
                else if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: (locked || _verifying) ? null : _submit,
                  child: _verifying
                      ? const SizedBox(
                          height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Desbloquear'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _verifying ? null : _forgotPin,
                  child: const Text('Olvidé mi PIN'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
