import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/pin_api.dart';
import '../../data/supabase_client.dart';
import '../../state/settings_provider.dart';
import '../../state/volume_sos_provider.dart';

// Puerto del diálogo de Ajustes de components/app-shell.tsx: tema, idioma, PIN, modo
// simple, y el ajuste de pulsaciones/ventana de tiempo del botón de volumen (Fase 4).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _pinApi = PinApi();
  bool _loadingPin = true;
  bool _pinConfigured = false;
  bool _pinEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadPinConfig();
  }

  Future<void> _loadPinConfig() async {
    try {
      final config = await _pinApi.getConfig();
      if (!mounted) return;
      setState(() {
        _pinConfigured = config.pinConfigured;
        _pinEnabled = config.pinEnabled;
        _loadingPin = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingPin = false);
    }
  }

  Future<void> _togglePinEnabled(bool value) async {
    final previous = _pinEnabled;
    setState(() => _pinEnabled = value);
    try {
      await _pinApi.savePin(pinEnabled: value);
    } catch (e) {
      if (!mounted) return;
      setState(() => _pinEnabled = previous);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    }
  }

  Future<void> _setPin() async {
    final controller = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Configurar PIN'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 8,
          decoration: const InputDecoration(
            hintText: 'Nuevo PIN (mínimo 4 dígitos)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (pin == null || pin.length < 4) return;
    try {
      await _pinApi.savePin(pin: pin, pinEnabled: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo guardar el PIN: $e')));
      return;
    }
    if (!mounted) return;
    setState(() {
      _pinConfigured = true;
      _pinEnabled = true;
    });
  }

  Future<void> _signOut() async {
    await supabase.auth.signOut();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final simpleMode = ref.watch(simpleModeProvider);
    final themeMode = ref.watch(appThemeModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        children: [
          const _SectionLabel('Apariencia'),
          SwitchListTile(
            title: const Text('Tema oscuro'),
            value: themeMode == ThemeMode.dark,
            onChanged: (value) => ref
                .read(appThemeModeProvider.notifier)
                .set(value ? ThemeMode.dark : ThemeMode.light),
          ),
          ListTile(
            title: const Text('Idioma'),
            subtitle: Text(context.locale.languageCode.toUpperCase()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickLanguage(context),
          ),
          SwitchListTile(
            title: const Text('Modo simple'),
            subtitle: const Text(
              'Interfaz simplificada, textos e íconos más grandes',
            ),
            value: simpleMode,
            onChanged: (value) =>
                ref.read(simpleModeProvider.notifier).set(value),
          ),
          const _ChatFontSizeTile(),
          const Divider(),
          const _SectionLabel('Seguridad'),
          if (_loadingPin)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            SwitchListTile(
              title: const Text('Bloqueo por PIN'),
              subtitle: Text(
                _pinConfigured
                    ? 'Protege contactos, ubicación e historial'
                    : 'Configura un PIN para activarlo',
              ),
              value: _pinEnabled && _pinConfigured,
              onChanged: _pinConfigured ? _togglePinEnabled : null,
            ),
            ListTile(
              title: Text(_pinConfigured ? 'Cambiar PIN' : 'Configurar PIN'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _setPin,
            ),
          ],
          const Divider(),
          const _SectionLabel('Botón de volumen (SOS)'),
          const _VolumeSosCard(),
          const Divider(),
          ListTile(
            leading: Icon(
              Icons.logout,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Cerrar sesión',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: _signOut,
          ),
        ],
      ),
    );
  }

  Future<void> _pickLanguage(BuildContext context) async {
    final locales = context.supportedLocales;
    final selected = await showModalBottomSheet<Locale>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: locales
              .map(
                (l) => ListTile(
                  title: Text(l.languageCode.toUpperCase()),
                  onTap: () => Navigator.pop(context, l),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (selected != null && context.mounted) {
      await context.setLocale(selected);
    }
  }
}

// No existe en la web (ahí el tamaño del chat es fijo) — agregado a pedido
// para accesibilidad, con presets discretos en vez de un slider libre para
// que la fuente resultante sea predecible.
class _ChatFontSizeTile extends ConsumerWidget {
  const _ChatFontSizeTile();

  static const _sizes = [14.0, 16.0, 18.0, 20.0, 24.0];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fontSize = ref.watch(chatFontSizeProvider);
    final primary = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Tamaño de letra en Apoyo',
                style: TextStyle(color: Colors.grey),
              ),
              Text(
                '${fontSize.toInt()}pt',
                style: TextStyle(fontWeight: FontWeight.bold, color: primary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: _sizes.map((size) {
              final selected = fontSize == size;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: selected ? primary : null,
                      foregroundColor: selected ? Colors.white : null,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onPressed: () =>
                        ref.read(chatFontSizeProvider.notifier).set(size),
                    child: Text(
                      'A',
                      style: TextStyle(fontSize: size.clamp(14, 20)),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// Puerto de la tarjeta "Botón de volumen" de app-shell.tsx: presets de
// pulsaciones ([3,4,5,7,10]) y ventana de tiempo ([2,3,4,5]s), idénticos a
// los de la web, en vez de un slider libre.
class _VolumeSosCard extends ConsumerWidget {
  const _VolumeSosCard();

  static const _pressOptions = [3, 4, 5, 7, 10];
  static const _windowOptionsMs = [2000, 3000, 4000, 5000];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final volume = ref.watch(volumeSosProvider);
    final notifier = ref.read(volumeSosProvider.notifier);
    final primary = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Pulsaciones necesarias',
                style: TextStyle(color: Colors.grey),
              ),
              Text(
                '${volume.pressesRequired}×',
                style: TextStyle(fontWeight: FontWeight.bold, color: primary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: _pressOptions.map((n) {
              final selected = volume.pressesRequired == n;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: selected ? primary : null,
                      foregroundColor: selected ? Colors.white : null,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onPressed: () => notifier.setPressesRequired(n),
                    child: Text('$n×'),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Ventana de tiempo',
                style: TextStyle(color: Colors.grey),
              ),
              Text(
                '${volume.windowMs / 1000}s',
                style: TextStyle(fontWeight: FontWeight.bold, color: primary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: _windowOptionsMs.map((ms) {
              final selected = volume.windowMs == ms;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: selected ? primary : null,
                      foregroundColor: selected ? Colors.white : null,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onPressed: () => notifier.setWindowMs(ms),
                    child: Text('${ms / 1000}s'),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Text(
            'Presiona el botón de volumen ${volume.pressesRequired} veces en ${volume.windowMs / 1000} segundos para activar el SOS.',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
