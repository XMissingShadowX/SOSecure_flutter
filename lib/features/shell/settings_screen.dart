import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/api/pin_api.dart';
import '../../data/api/plan_api.dart';
import '../../data/repositories/plan_repository.dart';
import '../../data/supabase_client.dart';
import '../../platform/volume_button_channel.dart';
import '../../state/settings_provider.dart';
import '../../state/volume_sos_provider.dart';
import '../premium/upgrade_cta.dart';

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
    controller.dispose();
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
          _ChatFontSizeTile(),
          const Divider(),
          _SectionLabel('settings_security'.tr()),
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
          const Divider(),
          _SectionLabel('settings_volumeSos'.tr()),
          _VolumeSosCard(),
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
              onActivate: () => openCheckout(context, '/plan-premium/pago'),
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
              onActivate: () => openCheckout(context, '/plan-familiar'),
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
            if (volume.backgroundEnabled) ...[
              const _BatteryOptimizationTile(),
              const _FullScreenIntentTile(),
              const _ServiceLivenessTile(),
            ],
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

// Android 14+ dejó de conceder USE_FULL_SCREEN_INTENT por defecto (ver
// MainActivity.kt): sin este permiso, el gesto con el teléfono cerrado y
// bloqueado degrada a una notificación normal en vez de abrir la app sobre la
// pantalla de bloqueo. En versiones previas siempre viene concedido, así que
// el tile ni se muestra. Mismo patrón que _BatteryOptimizationTile: se
// re-chequea al volver de Ajustes, vía didChangeAppLifecycleState.
class _FullScreenIntentTile extends StatefulWidget {
  const _FullScreenIntentTile();

  @override
  State<_FullScreenIntentTile> createState() => _FullScreenIntentTileState();
}

class _FullScreenIntentTileState extends State<_FullScreenIntentTile>
    with WidgetsBindingObserver {
  bool? _granted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final granted = await VolumeButtonChannel.canUseFullScreenIntent();
    if (!mounted) return;
    setState(() => _granted = granted);
  }

  Future<void> _request() async {
    await VolumeButtonChannel.requestFullScreenIntentPermission();
    // El usuario vuelve de Ajustes del sistema y dispara didChangeAppLifecycleState
    // (resumed), que re-chequea; esto solo cubre el caso en que ya estaba
    // concedido y el sistema no llegó a pausar la app.
    await _check();
  }

  @override
  Widget build(BuildContext context) {
    if (_granted == null || _granted == true) return const SizedBox.shrink();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.lock_open_outlined,
        color: Theme.of(context).colorScheme.error,
      ),
      title: Text('settings_volumeFullscreenTitle'.tr()),
      subtitle: Text(
        'settings_volumeFullscreenDesc'.tr(),
        style: const TextStyle(fontSize: 12),
      ),
      trailing: TextButton(
        onPressed: _request,
        child: Text('settings_volumeFullscreenAction'.tr()),
      ),
    );
  }
}

// Android puede matar el foreground service bajo presión de memoria (o algún
// fabricante agresivo con la batería lo congela pese a la exención) sin que
// nada se lo avise al usuario: los otros dos tiles de esta pantalla solo
// verifican permisos concedidos, no que el servicio siga vivo de verdad. Se
// re-chequea al abrir la pantalla y al volver a ella (igual que los otros
// tiles), y el botón simplemente reenvía la configuración actual, que ya
// reinicia el servicio del lado nativo (ver MainActivity.kt "configure").
class _ServiceLivenessTile extends ConsumerStatefulWidget {
  const _ServiceLivenessTile();

  @override
  ConsumerState<_ServiceLivenessTile> createState() =>
      _ServiceLivenessTileState();
}

class _ServiceLivenessTileState extends ConsumerState<_ServiceLivenessTile>
    with WidgetsBindingObserver {
  bool? _running;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final running = await VolumeButtonChannel.isBackgroundServiceRunning();
    if (!mounted) return;
    setState(() => _running = running);
  }

  // Este tile solo se muestra con volume.backgroundEnabled == true (ver el
  // condicional en _VolumeSosCard), así que reenviar `true` no cambia el
  // valor guardado — pero setBackgroundEnabled() igual reempuja la config al
  // lado nativo, y eso es lo que reinicia el servicio muerto.
  Future<void> _restart() async {
    await ref.read(volumeSosProvider.notifier).setBackgroundEnabled(true);
    await _check();
  }

  @override
  Widget build(BuildContext context) {
    if (_running == null || _running == true) return const SizedBox.shrink();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.error_outline,
        color: Theme.of(context).colorScheme.error,
      ),
      title: Text('settings_volumeServiceDownTitle'.tr()),
      subtitle: Text(
        'settings_volumeServiceDownDesc'.tr(),
        style: const TextStyle(fontSize: 12),
      ),
      trailing: TextButton(
        onPressed: _restart,
        child: Text('settings_volumeServiceDownAction'.tr()),
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
            OutlinedButton(onPressed: onActivate, child: Text('settings_activate'.tr()))
          else if (onCancel != null)
            TextButton(
              onPressed: cancelling ? null : onCancel,
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text(cancelling ? 'cancelling'.tr() : 'cancel'.tr()),
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
