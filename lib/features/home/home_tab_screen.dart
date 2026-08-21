import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../core/glass.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../domain/models/emergency_contact.dart';
import '../../domain/models/frequent_place.dart';
import '../../state/contacts_provider.dart';
import '../../state/location_provider.dart';
import '../../state/places_provider.dart';
import '../../state/settings_provider.dart';

const _placeIcons = {
  'home': Icons.home,
  'work': Icons.work,
  'school': Icons.school,
  'gym': Icons.favorite,
  'other': Icons.star,
};

Map<String, String> get _placeTypeLabels => {
  'home': 'home_placeHome'.tr(),
  'work': 'home_placeWork'.tr(),
  'school': 'home_placeSchool'.tr(),
  'gym': 'home_placeGym'.tr(),
  'other': 'home_placeOther'.tr(),
};

Map<String, String> get _importanceLabels => {
  'primary': 'map_sevHigh'.tr(),
  'secondary': 'map_sevMedium'.tr(),
  'tertiary': 'map_sevLow'.tr(),
};

Map<String, String> get _relationshipLabels => {
  'parent': 'home_relation_parent'.tr(),
  'spouse': 'home_relation_spouse'.tr(),
  'sibling': 'home_relation_sibling'.tr(),
  'friend': 'home_relation_friend'.tr(),
  'partner': 'home_relation_partner'.tr(),
  'other': 'home_relation_other'.tr(),
};

// Puerto de components/tabs/home-tab.tsx: ubicación actual, contactos de emergencia
// (CRUD vía RPCs cifradas) y lugares frecuentes (locales, sin Supabase).
class HomeTabScreen extends ConsumerWidget {
  const HomeTabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(locationWatcherProvider);
    final contactsAsync = ref.watch(contactsProvider);
    final places = ref.watch(frequentPlacesProvider);
    final simpleMode = ref.watch(simpleModeProvider);
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: () => ref.refresh(contactsProvider.future),
      child: ListView(
        // Bottom extra para que la última tarjeta no quede tapada por el
        // botón flotante SOS (fixed sobre todas las tabs) — mismo ajuste que
        // en before_tab_screen.dart.
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          _StatusBanner(location: location),
          const SizedBox(height: 16),
          if (!simpleMode) ...[
            _SafetyTipsCard(),
            const SizedBox(height: 16),
          ],
          _LocationCard(location: location, simpleMode: simpleMode),
          const SizedBox(height: 16),
          _FrequentPlacesCard(places: places, location: location),
          const SizedBox(height: 16),
          _ContactsCard(
            contactsAsync: contactsAsync,
            simpleMode: simpleMode,
            theme: theme,
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final LocationState location;
  const _StatusBanner({required this.location});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasLocation = location.hasCoordinates;
    final color = !hasLocation
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.tertiary;
    // Color.alphaBlend en vez de withValues(alpha:) — un Card con color semitransparente
    // no compone de forma confiable contra el fondo del Scaffold en Material 3 (terminaba
    // viéndose gris apagado en vez del verde pálido esperado); mezclarlo a mano contra el
    // fondo real da un resultado sólido y predecible.
    final tint = hasLocation
        ? Color.alphaBlend(
            color.withValues(alpha: 0.12),
            theme.scaffoldBackgroundColor,
          )
        : null;
    return GlassCard(
      color: tint,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield, color: color),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    hasLocation
                        ? 'home_noAlertsZone'.tr()
                        : 'home_gettingLocation'.tr(),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w600, color: color),
                  ),
                  Text(
                    location.loading
                        ? 'home_acquiringGps'.tr()
                        : location.error ??
                              (hasLocation
                                  ? '${location.latitude!.toStringAsFixed(4)}, ${location.longitude!.toStringAsFixed(4)}'
                                  : 'activate_location'.tr()),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Puerto de la tarjeta "Consejos de Seguridad" de home-tab.tsx (home_tip1/2/3)
// — se ocultaba por completo en el port original, faltaba entre el banner de
// estado y la tarjeta de ubicación, igual que en la web.
class _SafetyTipsCard extends StatelessWidget {
  const _SafetyTipsCard();

  List<String> get _tips => [
    'home_tip1'.tr(),
    'home_tip2'.tr(),
    'home_tip3'.tr(),
  ];

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'home_tips_title'.tr(),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < _tips.length; i++)
              Padding(
                padding: EdgeInsets.only(bottom: i < _tips.length - 1 ? 10 : 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _tips[i],
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  final LocationState location;
  final bool simpleMode;
  const _LocationCard({required this.location, required this.simpleMode});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.location_on,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'home_currentLocation'.tr(),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (location.loading)
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text('home_acquiringGps'.tr()),
                ],
              )
            else if (location.error != null)
              Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Theme.of(context).colorScheme.error,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      location.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              )
            else if (location.hasCoordinates)
              simpleMode
                  ? Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.tertiary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Text(
                            '✓ ${'home_locationActive'.tr()}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    )
                  : Text(
                      '${location.latitude!.toStringAsFixed(6)}, ${location.longitude!.toStringAsFixed(6)}',
                      style: const TextStyle(fontFamily: 'monospace'),
                    )
            else
              Text('home_noLocationYet'.tr()),
          ],
        ),
      ),
    );
  }
}

class _FrequentPlacesCard extends ConsumerWidget {
  final List<FrequentPlace> places;
  final LocationState location;
  const _FrequentPlacesCard({required this.places, required this.location});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.navigation_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'home_frequentPlaces'.tr(),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  'home_frequentPlacesSaved'.tr(
                    namedArgs: {'n': '${places.length}'},
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (places.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(child: Text('home_noPlacesYet'.tr())),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: places
                    .map(
                      (p) => _PlaceChip(
                        place: p,
                        onDelete: () => ref
                            .read(frequentPlacesProvider.notifier)
                            .remove(p.id),
                      ),
                    )
                    .toList(),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _showAddPlaceDialog(context, ref, location),
              icon: const Icon(Icons.add),
              label: Text('home_addFrequentPlace'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddPlaceDialog(
    BuildContext context,
    WidgetRef ref,
    LocationState location,
  ) async {
    final labelController = TextEditingController();
    final addressController = TextEditingController();
    String type = 'home';
    // null mientras no se elige una sugerencia -> se usa la ubicación actual al guardar,
    // igual que home-tab.tsx.addPlace en la web.
    double? geocodedLat;
    double? geocodedLon;
    List<_PlaceSuggestion> suggestions = [];
    Timer? debounce;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('home_addFrequentPlace'.tr()),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.8,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownMenu<String>(
                    initialSelection: type,
                    label: Text('home_type'.tr()),
                    expandedInsets: EdgeInsets.zero,
                    dropdownMenuEntries: _placeTypeLabels.entries
                        .map(
                          (e) =>
                              DropdownMenuEntry(value: e.key, label: e.value),
                        )
                        .toList(),
                    onSelected: (v) => setState(() => type = v ?? 'home'),
                  ),
                  TextField(
                    controller: labelController,
                    decoration: InputDecoration(
                      labelText: 'home_addPlace_name'.tr(),
                    ),
                  ),
                  TextField(
                    controller: addressController,
                    decoration: InputDecoration(
                      labelText: 'home_addPlace_address'.tr(),
                    ),
                    onChanged: (value) {
                      geocodedLat = null;
                      geocodedLon = null;
                      debounce?.cancel();
                      if (value.trim().length < 3) {
                        setState(() => suggestions = []);
                        return;
                      }
                      // Mismo debounce (500ms) y API (Photon) que routes-tab/home-tab en
                      // la web — solo el resultado más parecido a lo que se va escribiendo.
                      debounce = Timer(
                        const Duration(milliseconds: 500),
                        () async {
                          final results = await _searchPhoton(value);
                          if (context.mounted)
                            setState(() => suggestions = results);
                        },
                      );
                    },
                  ),
                  if (suggestions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      constraints: const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: suggestions.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final s = suggestions[i];
                          return ListTile(
                            dense: true,
                            title: Text(
                              s.displayName,
                              style: const TextStyle(fontSize: 13),
                            ),
                            onTap: () => setState(() {
                              addressController.text = s.displayName;
                              geocodedLat = s.lat;
                              geocodedLon = s.lon;
                              suggestions = [];
                            }),
                          );
                        },
                      ),
                    ),
                  if (geocodedLat != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '✓ ${'home_addressGeocoded'.tr()}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    )
                  else if (location.hasCoordinates)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'home_noAddressUseCurrent'.tr(
                          namedArgs: {
                            'coords':
                                '${location.latitude!.toStringAsFixed(5)}, ${location.longitude!.toStringAsFixed(5)}',
                          },
                        ),
                        style: const TextStyle(fontSize: 12),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'home_noLocationWaitGps'.tr(),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('cancel'.tr()),
            ),
            FilledButton(
              onPressed:
                  (labelController.text.isEmpty ||
                      (geocodedLat == null && !location.hasCoordinates))
                  ? null
                  : () {
                      final lat = geocodedLat ?? location.latitude!;
                      final lon = geocodedLon ?? location.longitude!;
                      ref
                          .read(frequentPlacesProvider.notifier)
                          .add(
                            FrequentPlace(
                              id: DateTime.now().millisecondsSinceEpoch
                                  .toString(),
                              label: labelController.text,
                              icon: type,
                              address: addressController.text.isNotEmpty
                                  ? addressController.text
                                  : '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}',
                              latitude: lat,
                              longitude: lon,
                            ),
                          );
                      Navigator.pop(context);
                    },
              child: Text('save'.tr()),
            ),
          ],
        ),
      ),
    );
    debounce?.cancel();
    labelController.dispose();
    addressController.dispose();
  }
}

class _PlaceSuggestion {
  final String displayName;
  final double lat;
  final double lon;
  _PlaceSuggestion({
    required this.displayName,
    required this.lat,
    required this.lon,
  });
}

// Espeja el fetch de Photon en home-tab.tsx: mismo endpoint, mismo límite de 5 resultados.
Future<List<_PlaceSuggestion>> _searchPhoton(String query) async {
  try {
    final uri = Uri.parse(
      'https://photon.komoot.io/api/',
    ).replace(queryParameters: {'q': query, 'limit': '5'});
    final res = await http.get(
      uri,
      headers: {
        'Accept': 'application/json',
        // Photon/Komoot responde 403 a requests sin un User-Agent de navegador —
        // el default del cliente http de Dart ("Dart/3.x (dart:io)") lo dispara.
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
      },
    );
    if (res.statusCode != 200) return [];
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final features = data['features'] as List? ?? [];
    return features.map((f) {
      final props = f['properties'] as Map<String, dynamic>? ?? {};
      final coords =
          (f['geometry'] as Map<String, dynamic>)['coordinates'] as List;
      final parts = [
        props['name'],
        props['street'],
        props['city'],
        props['country'],
      ].where((p) => p != null && (p as String).isNotEmpty).join(', ');
      return _PlaceSuggestion(
        displayName: parts.isNotEmpty ? parts : query,
        lat: (coords[1] as num).toDouble(),
        lon: (coords[0] as num).toDouble(),
      );
    }).toList();
  } catch (e, st) {
    debugPrint('[Photon] error: $e\n$st');
    return [];
  }
}

class _PlaceChip extends StatelessWidget {
  final FrequentPlace place;
  final VoidCallback onDelete;
  const _PlaceChip({required this.place, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(_placeIcons[place.icon] ?? Icons.star, size: 18),
      label: Text(place.label),
      onDeleted: onDelete,
      deleteIcon: const Icon(Icons.close, size: 16),
    );
  }
}

class _ContactsCard extends ConsumerWidget {
  final AsyncValue<List<EmergencyContact>> contactsAsync;
  final bool simpleMode;
  final ThemeData theme;
  const _ContactsCard({
    required this.contactsAsync,
    required this.simpleMode,
    required this.theme,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.people_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'home_contacts'.tr(),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            contactsAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (err, _) => Text(
                'home_contactsLoadError'.tr(namedArgs: {'err': '$err'}),
                style: TextStyle(color: theme.colorScheme.error),
              ),
              data: (contacts) => Column(
                children: [
                  if (contacts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: Text('home_noContactsAdded'.tr()),
                      ),
                    )
                  else
                    ...contacts.asMap().entries.map(
                      (entry) => _ContactTile(
                        index: entry.key + 1,
                        contact: entry.value,
                        simpleMode: simpleMode,
                        onEdit: () => _showContactDialog(
                          context,
                          ref,
                          editing: entry.value,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _showContactDialog(context, ref),
                    icon: const Icon(Icons.person_add_alt),
                    label: Text('home_addContact'.tr()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showContactDialog(
    BuildContext context,
    WidgetRef ref, {
    EmergencyContact? editing,
  }) async {
    final nameController = TextEditingController(text: editing?.name ?? '');
    final phoneController = TextEditingController(text: editing?.phone ?? '');
    final emailController = TextEditingController(text: editing?.email ?? '');
    // Si el contacto trae un valor de relación que no está en el catálogo (ej. texto libre
    // de antes de que esto fuera un dropdown), no lo preseleccionamos — el
    // DropdownButtonFormField exige que initialValue coincida con alguno de los items.
    String? relationship =
        _relationshipLabels.containsKey(editing?.relationship)
        ? editing?.relationship
        : null;
    String importance = editing?.importance ?? 'secondary';

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(editing == null ? 'home_addContact'.tr() : 'home_editContact'.tr()),
          content: SizedBox(
            // Ancho fijo — sin esto el diálogo se ajusta al contenido más angosto
            // (ej. solo nombre+teléfono en modo simple) y los botones de prioridad
            // quedan apretados cuando sí se muestran.
            width: MediaQuery.of(context).size.width * 0.8,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(labelText: 'home_addPlace_name'.tr()),
                  ),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(labelText: 'home_phone'.tr()),
                  ),
                  if (!simpleMode) ...[
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'home_emailOptional'.tr(),
                      ),
                    ),
                    DropdownMenu<String>(
                      initialSelection: relationship,
                      label: Text('home_addContact_relation'.tr()),
                      expandedInsets: EdgeInsets.zero,
                      dropdownMenuEntries: _relationshipLabels.entries
                          .map(
                            (e) =>
                                DropdownMenuEntry(value: e.key, label: e.value),
                          )
                          .toList(),
                      onSelected: (v) => setState(() => relationship = v),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'home_priorityLabel'.tr(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: _importanceLabels.entries.map((e) {
                        final selected = importance == e.key;
                        final selectedColor = switch (e.key) {
                          'primary' => Theme.of(context).colorScheme.error,
                          'secondary' => const Color(0xFFEF9900), // --warning
                          _ => Theme.of(context).colorScheme.primary,
                        };
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: OutlinedButton(
                              onPressed: () =>
                                  setState(() => importance = e.key),
                              style: OutlinedButton.styleFrom(
                                backgroundColor: selected
                                    ? selectedColor
                                    : null,
                                foregroundColor: selected ? Colors.white : null,
                                side: selected
                                    ? BorderSide.none
                                    : BorderSide(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.outline,
                                      ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                minimumSize: const Size(0, 36),
                              ),
                              child: Text(
                                e.value,
                                style: const TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('cancel'.tr()),
            ),
            FilledButton(
              onPressed:
                  (nameController.text.isEmpty || phoneController.text.isEmpty)
                  ? null
                  : () async {
                      final notifier = ref.read(contactsProvider.notifier);
                      if (editing == null) {
                        await notifier.addContact(
                          name: nameController.text,
                          phone: phoneController.text,
                          email: emailController.text.isEmpty
                              ? null
                              : emailController.text,
                          relationship: relationship,
                          importance: importance,
                        );
                      } else {
                        await notifier.updateContact(
                          id: editing.id,
                          name: nameController.text,
                          phone: phoneController.text,
                          email: emailController.text.isEmpty
                              ? null
                              : emailController.text,
                          relationship: relationship,
                          importance: importance,
                        );
                      }
                      if (context.mounted) Navigator.pop(context);
                    },
              child: Text('save'.tr()),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
  }
}

class _ContactTile extends ConsumerWidget {
  final int index;
  final EmergencyContact contact;
  final bool simpleMode;
  final VoidCallback onEdit;
  const _ContactTile({
    required this.index,
    required this.contact,
    required this.simpleMode,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
        foregroundColor: theme.colorScheme.primary,
        child: Text('$index'),
      ),
      title: Row(
        children: [
          Flexible(child: Text(contact.name, overflow: TextOverflow.ellipsis)),
          if (!simpleMode) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondary,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _importanceLabels[contact.importance] ?? '',
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(contact.phone),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: onEdit,
          ),
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              size: 20,
              color: theme.colorScheme.error,
            ),
            onPressed: () =>
                ref.read(contactsProvider.notifier).removeContact(contact.id),
          ),
        ],
      ),
    );
  }
}
