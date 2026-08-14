import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/glass.dart';
import '../../data/api/pin_api.dart';
import '../../data/api/plan_api.dart';
import '../../data/repositories/plan_repository.dart';
import '../../data/supabase_client.dart';
import '../../state/settings_provider.dart';
import '../../state/volume_sos_provider.dart';
import '../premium/checkout_launcher.dart';

// Puerto del diálogo de Ajustes de components/app-shell.tsx: tema, idioma, PIN, modo
// simple, y el ajuste de pulsaciones/ventana de tiempo del botón de volumen (Fase 4).
//
// Rediseñado sobre AmbientBackground + GlassCard (el mismo sistema visual que
// app_shell_screen.dart y el resto de las tabs) en vez del ListView plano de
// Material que tenía antes — visualmente era la única pantalla de la app que
// no usaba vidrio sobre el fondo ambiental, lo que la hacía sentir de otra app.
// Los planes Premium/Familiar se expandieron para espejar
// premium-plan-section.tsx / family-plan-section.tsx de la web: precio,
// periodo y lista de beneficios, no solo el estado activo/inactivo.
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

  // Gestión de miembros del plan familiar — solo relevante cuando _family es
  // el grupo del que el usuario es dueño (role == 'owner').
  List<FamilyMember> _familyMembers = [];
  bool _loadingMembers = false;
  bool _invitingMember = false;

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
      if (_family?.role == 'owner') {
        await _loadFamilyMembers();
      } else if (mounted) {
        setState(() => _familyMembers = []);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingPlans = false);
    }
  }

  Future<void> _loadFamilyMembers() async {
    final group = _family;
    if (group == null) return;
    setState(() => _loadingMembers = true);
    try {
      final members = await _planRepo.listFamilyMembers(group.id);
      if (!mounted) return;
      setState(() {
        _familyMembers = members;
        _loadingMembers = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMembers = false);
    }
  }

  Future<void> _inviteFamilyMember() async {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('family_inviteSend'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(hintText: 'family_inviteName'.tr()),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(hintText: 'family_inviteEmail'.tr()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, emailController.text.trim()),
            child: Text('family_inviteSend'.tr()),
          ),
        ],
      ),
    );
    if (email == null || !email.contains('@')) {
      if (email != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('family_inviteInvalidEmail'.tr())),
        );
      }
      return;
    }
    setState(() => _invitingMember = true);
    try {
      await _planApi.inviteFamilyMember(
        email: email,
        name: nameController.text.trim(),
      );
      await _loadFamilyMembers();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('family_inviteSent'.tr())));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _invitingMember = false);
    }
  }

  Future<void> _confirmRemoveMember(FamilyMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'family_removeMemberTitle'.tr(
            namedArgs: {'name': member.name?.isNotEmpty == true ? member.name! : member.email},
          ),
        ),
        content: Text('family_removeMemberDesc'.tr()),
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
            child: Text('family_removeMemberConfirm'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final error = await _planRepo.removeFamilyMember(member.id);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('family_removeMemberError'.tr())));
      return;
    }
    await _loadFamilyMembers();
  }

  // Contraparte de app-shell.tsx (efecto "Auto-aceptar invitación pendiente")
  // pero disparada a mano: la app no puede interceptar el link del correo de
  // invitación (abre en el navegador del teléfono, no requiere Android App
  // Links/verificación de dominio configurada), así que en vez de eso el
  // usuario pega el enlace o el token aquí.
  Future<void> _joinWithInvite() async {
    final controller = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('family_joinDialogTitle'.tr()),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: 'family_joinDialogHint'.tr()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text('family_joinDialogAction'.tr()),
          ),
        ],
      ),
    );
    if (input == null || input.isEmpty) return;

    // El enlace tiene forma .../plan-familiar/aceptar/?token=XXXX — si lo que
    // pegaron es una URL válida, extraer el query param; si no, asumir que ya
    // es el token pelado.
    final uri = Uri.tryParse(input);
    final token = (uri != null && uri.hasQuery)
        ? (uri.queryParameters['token'] ?? input)
        : input;

    try {
      final groupName = await _planApi.acceptFamilyInvite(token);
      await _loadPlans();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('family_joinSuccess'.tr(namedArgs: {'group': groupName})),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  // El pago (Mercado Pago/PayPal) siempre es un flujo de navegador, igual que
  // en la web. openCheckout pide la URL de la pasarela a la API con el token
  // de la app, así el navegador externo abre directo el checkout del proveedor
  // en vez de una página de SOSecure que exigiría iniciar sesión de nuevo.
  Future<void> _openPayment({required bool family}) =>
      openCheckout(context, family: family);

  Future<void> _cancelPremium() async {
    setState(() => _cancellingPremium = true);
    try {
      await _planApi.cancelPremium();
      await _loadPlans();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${'settings_cancelError'.tr()}$e')));
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
      ).showSnackBar(SnackBar(content: Text('${'settings_cancelError'.tr()}$e')));
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
        SnackBar(content: Text('${'settings_deleteAccountError'.tr()}$e')),
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
      ).showSnackBar(SnackBar(content: Text('${'settings_saveError'.tr()}$e')));
    }
  }

  Future<void> _setPin() async {
    final controller = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('settings_pinDialogTitle'.tr()),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 8,
          decoration: InputDecoration(
            hintText: 'settings_pinEnterNew'.tr(),
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
      ).showSnackBar(SnackBar(content: Text('${'settings_savePinError'.tr()}$e')));
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
    final theme = Theme.of(context);

    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text('settings_title'.tr()),
          backgroundColor: AppGlass.bgStrong(theme.brightness),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          shape: Border(bottom: BorderSide(color: theme.colorScheme.outline)),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            _SettingsSection(
              icon: Icons.palette_outlined,
              title: 'settings_appearance'.tr(),
              children: [
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
                  subtitle: Text('settings_simpleModeDesc'.tr()),
                  value: simpleMode,
                  onChanged: (value) =>
                      ref.read(simpleModeProvider.notifier).set(value),
                ),
                _ChatFontSizeTile(),
              ],
            ),
            _SettingsSection(
              icon: Icons.lock_outline,
              title: 'settings_security'.tr(),
              children: [
                if (_loadingPin)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  SwitchListTile(
                    title: Text('settings_pinLockSwitch'.tr()),
                    subtitle: Text(
                      _pinConfigured
                          ? 'settings_pinProtects'.tr()
                          : 'settings_pinSetupHint'.tr(),
                    ),
                    value: _pinEnabled && _pinConfigured,
                    onChanged: _pinConfigured ? _togglePinEnabled : null,
                  ),
                  ListTile(
                    title: Text(
                      _pinConfigured
                          ? 'settings_pinChange'.tr()
                          : 'settings_pinDialogTitle'.tr(),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _setPin,
                  ),
                ],
              ],
            ),
            _SettingsSection(
              icon: Icons.volume_up_outlined,
              title: 'settings_volumeSos'.tr(),
              children: [_VolumeSosCard()],
            ),
            if (_loadingPlans)
              const GlassCard(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else ...[
              _PlanCard(
                icon: Icons.star_rounded,
                nameLabel: 'plan_premiumNameLabel'.tr(),
                priceLabel: '\$59',
                periodLabel: 'plan_premiumPeriod'.tr(),
                taglineLabel: 'plan_premiumTagline'.tr(),
                benefits: [
                  'plan_premiumBenefit1'.tr(),
                  'plan_premiumBenefit2'.tr(),
                  'plan_premiumBenefit3'.tr(),
                  'plan_premiumBenefit4'.tr(),
                ],
                active: _premium?.isActive ?? false,
                activeLabel: 'family_active'.tr(),
                inactiveLabel: 'family_inactive'.tr(),
                onActivate: () => _openPayment(family: false),
                onCancel: _cancelPremium,
                cancelling: _cancellingPremium,
              ),
              _PlanCard(
                icon: Icons.family_restroom_rounded,
                nameLabel: 'plan_familiarNameLabel'.tr(),
                priceLabel: '\$295',
                periodLabel: 'plan_familiarPeriod'.tr(),
                taglineLabel: 'plan_familiarTagline'.tr(),
                benefits: [
                  'plan_familiarBenefit1'.tr(),
                  'plan_familiarBenefit2'.tr(),
                  'plan_familiarBenefit3'.tr(),
                  'plan_familiarBenefit4'.tr(),
                ],
                active: _family?.isActive ?? false,
                activeLabel: _family?.role == 'owner'
                    ? 'family_owner'.tr()
                    : 'family_active'.tr(),
                inactiveLabel: 'family_inactive'.tr(),
                onActivate: () => _openPayment(family: true),
                // Solo el dueño puede cancelar el plan familiar — un miembro
                // invitado no tiene esa opción (misma regla que la web, ver
                // CLAUDE.md: "la gestión de miembros solo se muestra al dueño").
                onCancel: _family?.role == 'owner' ? _cancelFamily : null,
                cancelling: _cancellingFamily,
              ),
              // Gestión de miembros — solo el dueño la ve, igual que en la web
              // (family-plan-section.tsx: la sección de invitar/quitar solo se
              // renderiza cuando `group?.status === 'active'`, o sea el dueño).
              if (_family?.isActive == true && _family?.role == 'owner')
                _FamilyMembersCard(
                  members: _familyMembers,
                  loading: _loadingMembers,
                  inviting: _invitingMember,
                  onInvite: _inviteFamilyMember,
                  onRemove: _confirmRemoveMember,
                )
              // Punto de entrada del lado del invitado: sin esto, alguien sin
              // plan propio no tiene cómo canjear el correo de invitación
              // dentro de la app (a diferencia de la web, la app no intercepta
              // el link — ver el comentario en _joinWithInvite).
              else if (_family == null)
                GlassCard(
                  child: ListTile(
                    leading: Icon(
                      Icons.mail_outline,
                      color: theme.colorScheme.primary,
                    ),
                    title: Text('family_joinWithInvite'.tr()),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _joinWithInvite,
                  ),
                ),
            ],
            GlassCard(
              color: Color.alphaBlend(
                theme.colorScheme.error.withValues(alpha: 0.06),
                theme.colorScheme.surface,
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(
                      Icons.delete_forever,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(
                      _deletingAccount
                          ? 'settings_deleteAccountDeleting'.tr()
                          : 'settings_deleteAccount'.tr(),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    subtitle: Text('settings_deleteAccountNote'.tr()),
                    onTap: _deletingAccount ? null : _confirmDeleteAccount,
                  ),
                  ListTile(
                    leading: Icon(Icons.logout, color: theme.colorScheme.error),
                    title: Text(
                      'header_signout'.tr(),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    onTap: _signOut,
                  ),
                ],
              ),
            ),
          ],
        ),
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
                  // El nombre nativo, no el código: "MYN" no le dice nada a
                  // alguien que habla maya. Cada nombre se escribe igual en
                  // los 5 archivos de traducción, así que la lista se lee
                  // igual sin importar el idioma activo.
                  title: Text('lang_${l.languageCode}'.tr()),
                  trailing: l.languageCode == context.locale.languageCode
                      ? const Icon(Icons.check)
                      : null,
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

// Envoltorio de sección: título con ícono + una sola GlassCard agrupando sus
// filas, en vez del `_SectionLabel` + `Divider()` sueltos de antes — mismo
// patrón de "tarjetas flotando sobre el fondo ambiental" que usa el resto de
// la app (ver after_tab_screen.dart, before_tab_screen.dart).
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    title.toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            ...children,
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
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
              Text(
                'settings_chatFontSize'.tr(),
                style: const TextStyle(color: Colors.grey),
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
              Text(
                'settings_volumePresses'.tr(),
                style: const TextStyle(color: Colors.grey),
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
          // El gesto solo sirve si funciona con el teléfono en el bolsillo:
          // esto enciende el servicio nativo que lo detecta con la pantalla
          // apagada, bloqueada o con la app cerrada (Android; en iOS no hay
          // API pública de botones de volumen).
          if (Platform.isAndroid) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('settings_volumeBackground'.tr()),
              subtitle: Text(
                'settings_volumeBackgroundDesc'.tr(),
                style: const TextStyle(fontSize: 12),
              ),
              value: volume.backgroundEnabled,
              onChanged: notifier.setBackgroundEnabled,
            ),
            if (volume.backgroundEnabled)
              const _BatteryOptimizationTile(),
          ],
        ],
      ),
    );
  }
}

// Con la optimización de batería activa, Android congela el proceso al rato de
// apagar la pantalla y el gesto deja de responder justo cuando más falta hace.
// No se pide sola al arrancar (es intrusiva): se ofrece aquí, junto al ajuste
// que la necesita, y se oculta cuando ya está concedida.
class _BatteryOptimizationTile extends StatefulWidget {
  const _BatteryOptimizationTile();

  @override
  State<_BatteryOptimizationTile> createState() =>
      _BatteryOptimizationTileState();
}

class _BatteryOptimizationTileState extends State<_BatteryOptimizationTile> {
  bool? _exempt;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final status = await Permission.ignoreBatteryOptimizations.status;
    if (!mounted) return;
    setState(() => _exempt = status.isGranted);
  }

  Future<void> _request() async {
    await Permission.ignoreBatteryOptimizations.request();
    await _check();
  }

  @override
  Widget build(BuildContext context) {
    if (_exempt == null || _exempt == true) return const SizedBox.shrink();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.battery_alert_outlined,
        color: Theme.of(context).colorScheme.error,
      ),
      title: Text('settings_volumeBatteryTitle'.tr()),
      subtitle: Text(
        'settings_volumeBatteryDesc'.tr(),
        style: const TextStyle(fontSize: 12),
      ),
      trailing: TextButton(
        onPressed: _request,
        child: Text('settings_volumeBatteryAction'.tr()),
      ),
    );
  }
}

// Gestión de miembros del plan familiar, visible solo para el dueño con el
// plan activo — espeja el bloque de miembros de family-plan-section.tsx
// (lista con corona para el dueño / sobre para invitados, botón de quitar, y
// el formulario de invitar cuando quedan cupos libres).
class _FamilyMembersCard extends StatelessWidget {
  const _FamilyMembersCard({
    required this.members,
    required this.loading,
    required this.inviting,
    required this.onInvite,
    required this.onRemove,
  });

  static const _maxMembers = 5; // FAMILY_PLAN.maxMembers en plan-config.ts

  final List<FamilyMember> members;
  final bool loading;
  final bool inviting;
  final VoidCallback onInvite;
  final ValueChanged<FamilyMember> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final free = (_maxMembers - members.length).clamp(0, _maxMembers);

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'family_membersCount'.tr(
                namedArgs: {'used': '${members.length}', 'max': '$_maxMembers'},
              ),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 10),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              ...members.map(
                (m) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          m.isOwner ? Icons.workspace_premium : Icons.mail_outline,
                          size: 16,
                          color: m.isOwner
                              ? primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (m.name?.isNotEmpty == true) ? m.name! : m.email,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                m.isOwner
                                    ? 'family_owner'.tr()
                                    : (m.status == 'active'
                                        ? 'family_active'.tr()
                                        : 'family_invited'.tr()),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!m.isOwner)
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            visualDensity: VisualDensity.compact,
                            color: theme.colorScheme.onSurfaceVariant,
                            onPressed: () => onRemove(m),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 4),
            if (free > 0)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: inviting ? null : onInvite,
                  icon: const Icon(Icons.person_add_alt_1, size: 16),
                  label: Text(
                    inviting
                        ? 'family_inviteSending'.tr()
                        : 'family_inviteSlots'.tr(
                            namedArgs: {
                              'n': '$free',
                              'slot': free == 1
                                  ? 'family_inviteSlot1'.tr()
                                  : 'family_inviteSlotsN'.tr(),
                            },
                          ),
                  ),
                ),
              )
            else
              Text(
                'family_full'.tr(),
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Tarjeta de un plan (Premium o Familiar) — espeja PremiumPlanSection /
// FamilyPlanSection de la web: nombre + precio/periodo, estado activo/inactivo,
// lista de beneficios con check, y el botón de activar (abre el pago en el
// navegador) o cancelar (vía plan_api.dart con el access token de Supabase).
// Antes solo mostraba una fila de estado sin precio ni beneficios.
class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.icon,
    required this.nameLabel,
    required this.priceLabel,
    required this.periodLabel,
    required this.taglineLabel,
    required this.benefits,
    required this.active,
    required this.activeLabel,
    required this.inactiveLabel,
    required this.onActivate,
    required this.onCancel,
    required this.cancelling,
  });

  final IconData icon;
  final String nameLabel;
  final String priceLabel;
  final String periodLabel;
  final String taglineLabel;
  final List<String> benefits;

  final bool active;
  final String activeLabel;
  final String inactiveLabel;
  final VoidCallback onActivate;
  final VoidCallback? onCancel;
  final bool cancelling;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return GlassCard(
      // Tinte sutil de marca cuando el plan está activo, igual que el borde
      // `border-primary/40` de la card en premium-plan-section.tsx — así se
      // distingue de un vistazo cuál plan ya está contratado.
      color: active
          ? Color.alphaBlend(primary.withValues(alpha: 0.08), theme.colorScheme.surface)
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nameLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        taglineLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _StatusPill(
                  active: active,
                  activeLabel: activeLabel,
                  inactiveLabel: inactiveLabel,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  priceLabel,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: primary,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '/ $periodLabel MXN',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...benefits.map(
              (b) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_outline, size: 16, color: primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(b, style: const TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (!active)
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onActivate,
                  child: Text('settings_activate'.tr()),
                ),
              )
            else if (onCancel != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: cancelling ? null : onCancel,
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  child: Text(cancelling ? 'cancelling'.tr() : 'cancel'.tr()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.active,
    required this.activeLabel,
    required this.inactiveLabel,
  });

  final bool active;
  final String activeLabel;
  final String inactiveLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = active ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: active ? 0.15 : 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? Icons.check_circle : Icons.schedule,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            active ? activeLabel : inactiveLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
