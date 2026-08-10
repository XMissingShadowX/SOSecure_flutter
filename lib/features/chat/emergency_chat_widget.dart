import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../core/glass.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/models/emergency_chat_message.dart';
import '../../state/emergency_chat_provider.dart';
import '../../state/contacts_provider.dart';
import '../../state/location_provider.dart';
import '../../state/premium_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/sos_provider.dart';
import 'live_stream_viewer.dart';

// Puerto del ítem LIVE_ID de emergency-chat.tsx: vista previa de la propia
// transmisión mientras el SOS está activo (solo aparece con sosActive &&
// sosAlert, igual que en la web — no es para ver la de un contacto, para eso
// está el botón "Ver transmisión" en el mensaje de alerta recibido).
const myLiveContactId = '__my_live__';

// Puerto de components/emergency-chat.tsx (sin LIVE_ID / transmisión en vivo,
// ver Fase 6b): botón flotante + panel con lista de contactos (SOSecure AI +
// contactos primary/secondary) y conversación 1:1 (chat_messages + realtime,
// o el asistente de IA vía /api/emergency-chat/).
class EmergencyChatWidget extends ConsumerStatefulWidget {
  const EmergencyChatWidget({super.key});

  @override
  ConsumerState<EmergencyChatWidget> createState() =>
      _EmergencyChatWidgetState();
}

class _EmergencyChatWidgetState extends ConsumerState<EmergencyChatWidget> {
  bool _open = false;
  String? _activeId;
  final _inputController = TextEditingController();
  bool _aiLoading = false;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _openConversation(String id) {
    setState(() => _activeId = id);
    ref.read(emergencyChatProvider.notifier).clearUnread();
    if (id != aiContactId) {
      ref.read(emergencyChatProvider.notifier).openConversation(id);
    } else if (!ref
        .read(emergencyChatProvider)
        .messages
        .any((m) => m.contactId == aiContactId)) {
      ref
          .read(emergencyChatProvider.notifier)
          .addLocalMessage(
            EmergencyChatMessage(
              id: 'ai-welcome',
              contactId: aiContactId,
              text: 'chat_welcome'.tr(),
              timestamp: DateTime.now(),
              isMe: false,
              type: 'ai',
            ),
          );
    }
  }

  Future<void> _send({String type = 'text'}) async {
    final location = ref.read(locationWatcherProvider);
    String text;
    if (type == 'location') {
      text = location.hasCoordinates
          ? 'chat_myLocation'.tr(
              namedArgs: {
                'url':
                    'https://maps.google.com/?q=${location.latitude},${location.longitude}',
              },
            )
          : 'chat_noLocationNow'.tr();
    } else {
      text = _inputController.text.trim();
      if (text.isEmpty) return;
    }

    final activeId = _activeId;
    if (activeId == null) return;

    if (activeId == aiContactId) {
      final notifier = ref.read(emergencyChatProvider.notifier);
      notifier.addLocalMessage(
        EmergencyChatMessage(
          id: 'u-${DateTime.now().microsecondsSinceEpoch}',
          contactId: aiContactId,
          text: text,
          timestamp: DateTime.now(),
          isMe: true,
          type: 'ai',
        ),
      );
      _inputController.clear();
      setState(() => _aiLoading = true);
      try {
        final reply = await notifier.askAi(
          history: ref.read(emergencyChatProvider).messages,
          latitude: location.latitude,
          longitude: location.longitude,
        );
        notifier.addLocalMessage(
          EmergencyChatMessage(
            id: 'ai-${DateTime.now().microsecondsSinceEpoch}',
            contactId: aiContactId,
            text: reply,
            timestamp: DateTime.now(),
            isMe: false,
            type: 'ai',
          ),
        );
      } catch (e) {
        notifier.addLocalMessage(
          EmergencyChatMessage(
            id: 'ai-err-${DateTime.now().microsecondsSinceEpoch}',
            contactId: aiContactId,
            text: 'chat_aiConnectionError'.tr(),
            timestamp: DateTime.now(),
            isMe: false,
            type: 'ai',
          ),
        );
      } finally {
        if (mounted) setState(() => _aiLoading = false);
      }
      return;
    }

    _inputController.clear();
    await ref
        .read(emergencyChatProvider.notifier)
        .sendText(
          receiverId: activeId,
          text: text,
          type: type == 'location' ? 'location' : 'text',
        );
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(emergencyChatProvider);
    final simpleMode = ref.watch(simpleModeProvider);

    if (!_open) {
      return Positioned(
        bottom: simpleMode ? 118 : 112,
        right: 16,
        child: FloatingActionButton(
          heroTag: 'emergency_chat_fab',
          onPressed: () {
            setState(() => _open = true);
            ref.read(emergencyChatOpenProvider.notifier).set(true);
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.chat_bubble_outline),
              if (chat.unread > 0)
                Positioned(
                  top: -6,
                  right: -6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.error,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Text(
                      '${chat.unread}',
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Positioned(
      left: 12,
      right: 12,
      bottom: 80,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: GlassCard(
          // El panel del chat es la única superficie grande que en la web NO es
          // glass: emergency-chat.tsx usa `bg-card` opaco, no <Card>. Tiene
          // sentido — es una conversación larga que se lee sobre el mapa y el
          // resto del contenido, y translúcida se vuelve ilegible.
          color: Theme.of(context).colorScheme.surface,
          strong: true,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _ChatHeader(
                activeId: _activeId,
                onBack: () => setState(() => _activeId = null),
                onClose: () {
                  setState(() => _open = false);
                  ref.read(emergencyChatOpenProvider.notifier).set(false);
                },
              ),
              Expanded(
                child: _activeId == null
                    ? _ContactList(onSelect: _openConversation)
                    : _Conversation(
                        activeId: _activeId!,
                        aiLoading: _aiLoading,
                      ),
              ),
              // La vista previa de la propia transmisión no tiene acciones
              // rápidas ni caja de mensaje — solo el video.
              if (_activeId != null && _activeId != myLiveContactId)
                _QuickActions(
                  activeId: _activeId!,
                  onShareLocation: () => _send(type: 'location'),
                ),
              if (_activeId != null && _activeId != myLiveContactId)
                _InputBar(
                  controller: _inputController,
                  activeId: _activeId!,
                  sending: chat.sending || _aiLoading,
                  onSend: () => _send(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatHeader extends ConsumerWidget {
  final String? activeId;
  final VoidCallback onBack;
  final VoidCallback onClose;
  const _ChatHeader({
    required this.activeId,
    required this.onBack,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(contactsProvider).valueOrNull ?? [];
    final resolvedIds = ref.watch(emergencyChatProvider).resolvedIds;
    String title = 'chat_chat'.tr();
    if (activeId == aiContactId) {
      title = 'chat_ai'.tr();
    } else if (activeId == myLiveContactId) {
      title = 'chat_myLiveStream'.tr();
    } else if (activeId != null) {
      final contact = contacts
          .where((c) => resolvedIds[c.email] == activeId)
          .firstOrNull;
      title = contact?.name ?? 'chat_contactFallback'.tr();
    }
    return Container(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          if (activeId != null)
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: onBack,
              visualDensity: VisualDensity.compact,
            ),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onClose,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _ContactList extends ConsumerWidget {
  final void Function(String id) onSelect;
  const _ContactList({required this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsAsync = ref.watch(contactsProvider);
    final resolvedIds = ref.watch(emergencyChatProvider).resolvedIds;
    final contacts = (contactsAsync.valueOrNull ?? [])
        .where((c) => c.importance == 'primary' || c.importance == 'secondary')
        .toList();
    final sos = ref.watch(sosProvider);

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        if (sos.active && sos.alert != null)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(
                context,
              ).colorScheme.error.withValues(alpha: 0.2),
              child: Icon(
                Icons.podcasts,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            title: Text('chat_myLiveStream'.tr()),
            subtitle: Text('chat_myLiveStreamDesc'.tr()),
            onTap: () => onSelect(myLiveContactId),
          ),
        ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.2),
            child: Icon(
              Icons.shield_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          title: Text('chat_ai'.tr()),
          subtitle: Text('chat_aiSubtitle'.tr()),
          onTap: () => onSelect(aiContactId),
        ),
        for (final c in contacts)
          ListTile(
            leading: CircleAvatar(
              child: Text(c.name.isNotEmpty ? c.name[0].toUpperCase() : '?'),
            ),
            title: Text(c.name),
            subtitle: Text(
              c.email == null
                  ? 'chat_noEmail'.tr()
                  : (resolvedIds.containsKey(c.email)
                        ? (resolvedIds[c.email] != null
                              ? 'chat_inSOSecure'.tr()
                              : '${'chat_noAccountLabel'.tr()} — ${'chat_useWhatsapp'.tr()}')
                        : 'routes_searching'.tr()),
              style: const TextStyle(fontSize: 12),
            ),
            onTap: () {
              final uuid = c.email != null ? resolvedIds[c.email] : null;
              onSelect(uuid ?? c.id);
            },
          ),
      ],
    );
  }
}

class _Conversation extends ConsumerWidget {
  final String activeId;
  final bool aiLoading;
  const _Conversation({required this.activeId, required this.aiLoading});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (activeId == myLiveContactId) {
      final alertId = ref.watch(sosProvider).alert?.id;
      if (alertId == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.all(12),
        child: LiveStreamViewer(alertId: alertId),
      );
    }

    final chat = ref.watch(emergencyChatProvider);
    final isAi = activeId == aiContactId;
    final isPremiumAsync = ref.watch(isPremiumProvider);

    if (isAi &&
        !(isPremiumAsync.valueOrNull ?? false) &&
        !isPremiumAsync.isLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'chat_aiPremiumGateDesc'.tr(),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final messages = chat.messages
        .where((m) => m.contactId == activeId)
        .toList();
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: messages.length + (aiLoading ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= messages.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final m = messages[i];
        final bg = m.type == 'sos'
            ? Theme.of(context).colorScheme.error
            : m.isMe
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.surfaceContainerHighest;
        final fg = (m.isMe || m.type == 'sos')
            ? Colors.white
            : Theme.of(context).colorScheme.onSurface;
        // Puerto de Fase 6b: el mensaje de alerta SOS lleva el id de la
        // alerta en un sufijo invisible (ver _broadcastSos en
        // emergency_chat_provider.dart) — se extrae acá para mostrar un
        // botón de "Ver transmisión" y no mostrar el sufijo crudo.
        final liveMatch = RegExp(r'\nsosecure-live:(.+)$').firstMatch(m.text);
        final displayText = liveMatch != null
            ? m.text.substring(0, liveMatch.start)
            : m.text;
        final liveAlertId = liveMatch?.group(1);
        return Align(
          alignment: m.isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.65,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(displayText, style: TextStyle(color: fg, fontSize: 13)),
                if (liveAlertId != null) ...[
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: fg,
                      side: BorderSide(color: fg.withValues(alpha: 0.6)),
                    ),
                    onPressed: () => showModalBottomSheet(
                      context: context,
                      builder: (_) => Padding(
                        padding: const EdgeInsets.all(12),
                        child: LiveStreamViewer(alertId: liveAlertId),
                      ),
                    ),
                    icon: const Icon(Icons.podcasts, size: 16),
                    label: Text(
                      'chat_viewStream'.tr(),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QuickActions extends ConsumerWidget {
  final String activeId;
  final VoidCallback onShareLocation;
  const _QuickActions({required this.activeId, required this.onShareLocation});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(contactsProvider).valueOrNull ?? [];
    final resolvedIds = ref.watch(emergencyChatProvider).resolvedIds;
    final contact = contacts
        .where((c) => resolvedIds[c.email] == activeId || c.id == activeId)
        .firstOrNull;
    final hasAccount =
        contact?.email != null && resolvedIds[contact!.email] != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Wrap(
        spacing: 6,
        children: [
          ActionChip(
            avatar: const Icon(Icons.location_on_outlined, size: 14),
            label: Text(
              'chat_shareLocation'.tr(),
              style: const TextStyle(fontSize: 11),
            ),
            onPressed: onShareLocation,
          ),
          if (activeId != aiContactId && contact?.phone != null)
            ActionChip(
              avatar: const Icon(Icons.call_outlined, size: 14),
              label: Text(
                'chat_call'.tr(),
                style: const TextStyle(fontSize: 11),
              ),
              onPressed: () => launchUrl(Uri.parse('tel:${contact!.phone}')),
            ),
          if (activeId != aiContactId && !hasAccount && contact?.phone != null)
            ActionChip(
              avatar: const Icon(Icons.chat_outlined, size: 14),
              label: Text(
                'chat_whatsapp'.tr(),
                style: const TextStyle(fontSize: 11),
              ),
              onPressed: () => launchUrl(
                Uri.parse(
                  'https://wa.me/${contact!.phone.replaceAll(RegExp(r'\D'), '')}',
                ),
                mode: LaunchMode.externalApplication,
              ),
            ),
        ],
      ),
    );
  }
}

class _InputBar extends ConsumerWidget {
  final TextEditingController controller;
  final String activeId;
  final bool sending;
  final VoidCallback onSend;
  const _InputBar({
    required this.controller,
    required this.activeId,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(contactsProvider).valueOrNull ?? [];
    final resolvedIds = ref.watch(emergencyChatProvider).resolvedIds;
    final contact = contacts
        .where((c) => resolvedIds[c.email] == activeId || c.id == activeId)
        .firstOrNull;
    final hasAccount =
        activeId == aiContactId ||
        (contact?.email != null && resolvedIds[contact!.email] != null);

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: hasAccount && !sending,
              decoration: InputDecoration(
                isDense: true,
                hintText: hasAccount
                    ? 'chat_placeholder'.tr()
                    : 'chat_noAccountShort'.tr(),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: hasAccount ? (_) => onSend() : null,
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filled(
            onPressed: hasAccount && !sending ? onSend : null,
            icon: sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}
