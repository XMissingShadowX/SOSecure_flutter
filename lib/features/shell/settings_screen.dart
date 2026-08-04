import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/env.dart';
import '../../data/api/pin_api.dart';
import '../../data/api/plan_api.dart';
import '../../data/repositories/plan_repository.dart';
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
  final _planApi = PlanApi();
  final _planRepo = PlanRepository();
  bool _loadingPin = true;
  bool _pinConfigured = false;
  bool _pinEnabled = false;

  bool _loadingPlans = true;
  PremiumSubscription? _premium;
  FamilyGroup? _family;
  bool _cancellingPremium = false;
  bool _cancellingFamily = false;
  bool _deletingAccount = false;

  @override
  void initState() {
    super.initState();
    _loadPinConfig();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    try {
      final results = await Future.wait([
        _planRepo.getPremiumSubscription(),
        _planRepo.getFamilyGroup(),
      ]);
      if (!mounted) return;
      setState(() {
        _premium = results[0] as PremiumSubscription?;
        _family = results[1] as FamilyGroup?;
        _loadingPlans = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingPlans = false);
    }
  }

  Future<void> _openWebPayment(String path) async {
    final uri = Uri.parse('${Env.apiBaseUrl}$path');
    // El pago (Mercado Pago/PayPal) siempre es un flujo de navegador, igual
    // que en la web — pero esta app usa el cliente Supabase nativo, no
    // cookies, así que el navegador externo NO comparte sesión: el usuario
    // deberá iniciar sesión ahí de nuevo con la misma cuenta.
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _cancelPremium() async {
    setState(() => _cancellingPremium = true);
    try {
      await _planApi.cancelPremium();
      await _loadPlans();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo cancelar: $e')));
    } finally {
      if (mounted) setState(() => _cancellingPremium = false);
    }
  }

  Future<void> _cancelFamily() async {
    setState(() => _cancellingFamily = true);
    try {
      await _planApi.cancelFamily();
      await _loadPlans();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo cancelar: $e')));
    } finally {
      if (mounted) setState(() => _cancellingFamily = false);
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('settings_deleteAccountTitle'.tr()),
        content: Text('settings_deleteAccountDesc'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text('settings_deleteAccountConfirm'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _deletingAccount = true);
    try {
      await _planApi.deleteAccount();
      await supabase.auth.signOut();
      if (mounted) context.go('/login');
    } catch (e) {
      if (!mounted) return;
      setState(() => _deletingAccount = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo eliminar la cuenta: $e')),
      );
    }
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
            child: Text('cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text('save'.tr()),
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
      appBar: AppBar(title: Text('settings_title'.tr())),
      body: ListView(
        children: [
          _SectionLabel('settings_appearance'.tr()),
          SwitchListTile(
            title: Text('settings_darkTheme'.tr()),
            value: themeMode == ThemeMode.dark,
            onChanged: (value) => ref
                .read(appThemeModeProvider.notifier)
                .set(value ? ThemeMode.dark : ThemeMode.light),
          ),
          ListTile(
            title: Text('settings_language'.tr()),
            subtitle: Text(context.locale.languageCode.toUpperCase()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickLanguage(context),
          ),
          SwitchListTile(
            title: Text('settings_simpleMode'.tr()),
            subtitle: Text(
              'settings_simpleModeDesc'.tr(),
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
              title: Text(
                _pinConfigured ? 'settings_pinChange'.tr() : 'Configurar PIN',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _setPin,
            ),
          ],
          const Divider(),
          const _SectionLabel('Botón de volumen (SOS)'),
          const _VolumeSosCard(),
          const Divider(),
          _SectionLabel('plan_premiumNameLabel'.tr()),
          if (_loadingPlans)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            _PlanCard(
              active: _premium?.isActive ?? false,
              activeLabel: 'family_active'.tr(),
              inactiveLabel: 'family_inactive'.tr(),
              onActivate: () => _openWebPayment('/plan-premium/pago'),
              onCancel: _cancelPremium,
              cancelling: _cancellingPremium,
            ),
          const Divider(),
          _SectionLabel('plan_familiarNameLabel'.tr()),
          if (_loadingPlans)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            _PlanCard(
              active: _family?.isActive ?? false,
              activeLabel: _family?.role == 'owner'
                  ? 'family_owner'.tr()
                  : 'family_active'.tr(),
              inactiveLabel: 'family_inactive'.tr(),
              onActivate: () => _openWebPayment('/plan-familiar'),
              // Solo el dueño puede cancelar el plan familiar — un miembro
              // invitado no tiene esa opción (misma regla que la web, ver
              // CLAUDE.md: "la gestión de miembros solo se muestra al dueño").
              onCancel: _family?.role == 'owner' ? _cancelFamily : null,
              cancelling: _cancellingFamily,
            ),
          const Divider(),
          _SectionLabel('settings_account'.tr()),
          ListTile(
            leading: Icon(
              Icons.delete_forever,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              _deletingAccount
                  ? 'settings_deleteAccountDeleting'.tr()
                  : 'settings_deleteAccount'.tr(),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            subtitle: Text('settings_deleteAccountNote'.tr()),
            onTap: _deletingAccount ? null : _confirmDeleteAccount,
          ),
          ListTile(
            leading: Icon(
              Icons.logout,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'header_signout'.tr(),
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
              Text(
                'settings_volumeWindow'.tr(),
                style: const TextStyle(color: Colors.grey),
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
            'settings_volumeHint'.tr(
              namedArgs: {
                'n': '${volume.pressesRequired}',
                's': '${volume.windowMs / 1000}',
              },
            ),
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

// Tarjeta compacta de estado de un plan (Premium o Familiar) — versión
// simplificada de PremiumPlanSection/FamilyPlanSection de la web: solo
// muestra estado + botón de activar (abre el pago en el navegador, ya que
// Mercado Pago/PayPal son flujos web) o cancelar (vía plan_api.dart, que sí
// puede llamarse directo con el access token de Supabase).
class _PlanCard extends StatelessWidget {
  final bool active;
  final String activeLabel;
  final String inactiveLabel;
  final VoidCallback onActivate;
  final VoidCallback? onCancel;
  final bool cancelling;

  const _PlanCard({
    required this.active,
    required this.activeLabel,
    required this.inactiveLabel,
    required this.onActivate,
    required this.onCancel,
    required this.cancelling,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            active ? Icons.check_circle : Icons.circle_outlined,
            color: active ? primary : Colors.grey,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              active ? activeLabel : inactiveLabel,
              style: TextStyle(
                color: active ? primary : Colors.grey,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (!active)
            OutlinedButton(onPressed: onActivate, child: const Text('Activar'))
          else if (onCancel != null)
            TextButton(
              onPressed: cancelling ? null : onCancel,
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text(cancelling ? 'Cancelando...' : 'Cancelar'),
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
