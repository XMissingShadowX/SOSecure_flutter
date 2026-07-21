import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/pin_api.dart';
import '../../data/supabase_client.dart';
import '../../state/settings_provider.dart';

// Puerto del diálogo de Ajustes de components/app-shell.tsx: tema, idioma, PIN, modo
// simple. El toggle de configuración del botón de volumen se agrega en la Fase 4, cuando
// exista volume_sos_provider.dart — por ahora hay un espacio reservado, sin bloquear el resto.
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
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
          decoration: const InputDecoration(hintText: 'Nuevo PIN (mínimo 4 dígitos)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (pin == null || pin.length < 4) return;
    try {
      await _pinApi.savePin(pin: pin, pinEnabled: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo guardar el PIN: $e')));
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
            subtitle: const Text('Interfaz simplificada, textos e íconos más grandes'),
            value: simpleMode,
            onChanged: (value) => ref.read(simpleModeProvider.notifier).set(value),
          ),
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
              subtitle: Text(_pinConfigured
                  ? 'Protege contactos, ubicación e historial'
                  : 'Configura un PIN para activarlo'),
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
          const ListTile(
            title: Text('Disponible en la Fase 4'),
            subtitle: Text('Activación de SOS con el botón físico de volumen'),
            enabled: false,
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
            title: Text('Cerrar sesión',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
              .map((l) => ListTile(
                    title: Text(l.languageCode.toUpperCase()),
                    onTap: () => Navigator.pop(context, l),
                  ))
              .toList(),
        ),
      ),
    );
    if (selected != null && context.mounted) {
      await context.setLocale(selected);
    }
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
