import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/glass.dart';
import '../../../state/contacts_provider.dart';
import '../widgets/tutorial_step_frame.dart';

// Mismos valores de 'importance' que domain/models/emergency_contact.dart
// ('primary'|'secondary'|'tertiary') y mismos colores que la fila de prioridad de
// _ContactsCard en home_tab_screen.dart, para que el paso se sienta como el
// formulario real y no una maqueta con otra paleta.
const _importanceOrder = ['primary', 'secondary', 'tertiary'];

// Escribe un contacto real vía contactsProvider (RPC autenticada, sin depender de
// permisos del SO) — decisión de diseño resuelta en el plan: "cuántos usuarios nuevos
// terminan con al menos un contacto real" es la métrica de mayor impacto que este paso
// puede mover, así que no es una maqueta.
class AddContactStep extends ConsumerStatefulWidget {
  const AddContactStep({super.key});

  @override
  ConsumerState<AddContactStep> createState() => _AddContactStepState();
}

class _AddContactStepState extends ConsumerState<AddContactStep> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  String _importance = 'primary';
  bool _saving = false;
  bool _saved = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(contactsProvider.notifier)
          .addContact(
            name: _nameController.text,
            phone: _phoneController.text,
            importance: _importance,
          );
      if (mounted) setState(() => _saved = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Color _importanceColor(BuildContext context, String key) {
    return switch (key) {
      'primary' => Theme.of(context).colorScheme.error,
      'secondary' => const Color(0xFFEF9900),
      _ => Theme.of(context).colorScheme.primary,
    };
  }

  String _importanceLabel(String key) => switch (key) {
    'primary' => 'map_sevHigh'.tr(),
    'secondary' => 'map_sevMedium'.tr(),
    _ => 'map_sevLow'.tr(),
  };

  @override
  Widget build(BuildContext context) {
    return TutorialStepFrame(
      title: 'tutorial_contactTitle'.tr(),
      subtitle: 'tutorial_contactSubtitle'.tr(),
      child: _saved
          ? GlassCard(
              color: Color.alphaBlend(
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                Theme.of(context).colorScheme.surface,
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(child: Text('tutorial_contactAddedConfirmation'.tr())),
                  ],
                ),
              ),
            )
          : GlassCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _nameController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'tutorial_contactNameHint'.tr(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'tutorial_contactPhoneHint'.tr(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'tutorial_contactPriorityLabel'.tr(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: _importanceOrder.map((key) {
                        final selected = _importance == key;
                        final color = _importanceColor(context, key);
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: OutlinedButton(
                              onPressed: () => setState(() => _importance = key),
                              style: OutlinedButton.styleFrom(
                                backgroundColor: selected ? color : null,
                                foregroundColor: selected ? Colors.white : null,
                                side: selected
                                    ? BorderSide.none
                                    : BorderSide(color: Theme.of(context).colorScheme.outline),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                minimumSize: const Size(0, 36),
                              ),
                              child: Text(
                                _importanceLabel(key),
                                style: const TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed:
                          (_saving ||
                              _nameController.text.trim().isEmpty ||
                              _phoneController.text.trim().isEmpty)
                          ? null
                          : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text('tutorial_contactAddCta'.tr()),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => setState(() => _saved = true),
                      child: Text('tutorial_contactSkipCta'.tr()),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
