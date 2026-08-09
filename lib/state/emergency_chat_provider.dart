import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/env.dart';
import '../data/repositories/emergency_chat_repository.dart';
import '../data/supabase_client.dart';
import '../domain/models/emergency_chat_message.dart';
import '../platform/sos_alarm.dart';
import 'auth_provider.dart';
import 'contacts_provider.dart';
import 'sos_provider.dart';

part 'emergency_chat_provider.g.dart';

const aiContactId = '__safewalk_ai__';

// Expuesto para que app_shell_screen.dart pueda ocultar el botón flotante
// idle de SosButton mientras el panel del chat está abierto — su input
// queda en la misma esquina inferior y se tapaban entre sí.
@Riverpod(keepAlive: true)
class EmergencyChatOpen extends _$EmergencyChatOpen {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

class EmergencyChatState {
  final List<EmergencyChatMessage> messages;
  final Map<String, String?> resolvedIds; // email -> uuid (null = sin cuenta)
  final int unread;
  final bool sending;

  const EmergencyChatState({
    this.messages = const [],
    this.resolvedIds = const {},
    this.unread = 0,
    this.sending = false,
  });

  EmergencyChatState copyWith({
    List<EmergencyChatMessage>? messages,
    Map<String, String?>? resolvedIds,
    int? unread,
    bool? sending,
  }) {
    return EmergencyChatState(
      messages: messages ?? this.messages,
      resolvedIds: resolvedIds ?? this.resolvedIds,
      unread: unread ?? this.unread,
      sending: sending ?? this.sending,
    );
  }
}

// Puerto del estado de components/emergency-chat.tsx (sin LIVE_ID/streaming en
// vivo, ver addendum de Fase 2 — esa parte queda en Fase 6b). Resuelve el uuid
// de cada contacto por email, carga historial, escucha mensajes entrantes por
// Realtime, y dispara el broadcast de SOS a los contactos con cuenta.
@Riverpod(keepAlive: true)
class EmergencyChat extends _$EmergencyChat {
  final _repo = EmergencyChatRepository();
  RealtimeChannel? _channel;
  bool _sosBroadcastSent = false;

  @override
  EmergencyChatState build() {
    ref.onDispose(() {
      if (_channel != null) supabase.removeChannel(_channel!);
    });
    ref.listen(currentUserProvider, (prev, next) {
      if (next != null && prev?.id != next.id) _init(next.id);
    });
    // contactsProvider carga su RPC de forma asíncrona — si _init() corría
    // antes de que terminara (lo normal, ya que ambos arrancan juntos al
    // abrir la app), _resolveContacts() encontraba una lista vacía, dejaba
    // resolvedIds vacío, y nunca se reintentaba: los contactos se quedaban
    // en "Buscando..." para siempre. Reintentar cada vez que la lista cambie
    // (incluyendo la primera vez que llega con datos reales).
    ref.listen(contactsProvider, (prev, next) {
      if (next.valueOrNull != null) _resolveContacts();
    });
    ref.listen(sosProvider, (prev, next) {
      if (next.active && !(prev?.active ?? false)) {
        _sosBroadcastSent = false;
      }
      if (next.active && !_sosBroadcastSent) {
        _sosBroadcastSent = true;
        _broadcastSos();
      }
    });
    final user = ref.read(currentUserProvider);
    // Diferido a un microtask: si _resolveContacts() no encuentra contactos
    // que resolver (sin awaits pendientes), llegaba a `state.copyWith(...)`
    // de forma síncrona, antes de que build() hubiera terminado de fijar el
    // estado inicial del notifier — Riverpod lo rechaza con "Tried to read
    // the state of an uninitialized provider".
    if (user != null) Future.microtask(() => _init(user.id));
    return const EmergencyChatState();
  }

  Future<void> _init(String myId) async {
    await _resolveContacts();
    final history = await _repo.loadHistory(myId);
    final unread = history
        .where((m) => !m.isMe)
        .length; // aproximado — is_read no viaja al cliente
    state = state.copyWith(messages: history, unread: unread);
    _subscribeRealtime(myId);
  }

  Future<void> _resolveContacts() async {
    final contacts = ref.read(contactsProvider).valueOrNull ?? [];
    final relevant = contacts.where(
      (c) => c.importance == 'primary' || c.importance == 'secondary',
    );
    final resolved = Map<String, String?>.from(state.resolvedIds);
    for (final c in relevant) {
      final email = c.email;
      if (email == null || resolved.containsKey(email)) continue;
      resolved[email] = await _repo.resolveUserIdByEmail(email);
    }
    state = state.copyWith(resolvedIds: resolved);
  }

  void _subscribeRealtime(String myId) {
    _channel = supabase
        .channel('chat-realtime-$myId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_id',
            value: myId,
          ),
          callback: (payload) {
            final msg = EmergencyChatMessage.fromDb(payload.newRecord, myId);
            state = state.copyWith(
              messages: [...state.messages, msg],
              unread: state.unread + 1,
            );
            _notifyIncoming(msg);
          },
        )
        .subscribe();
  }

  // No existe en la web (emergency-chat.tsx no notifica mensajes entrantes) —
  // añadido a pedido. Resuelve el nombre del contacto invirtiendo
  // resolvedIds (email -> uuid) para mostrarlo en vez del uuid crudo.
  void _notifyIncoming(EmergencyChatMessage msg) {
    final contacts = ref.read(contactsProvider).valueOrNull ?? [];
    final matches = contacts.where(
      (c) => state.resolvedIds[c.email] == msg.contactId,
    );
    final senderName = matches.isNotEmpty
        ? matches.first.name
        : 'chat_newMessage'.tr();
    final body = switch (msg.type) {
      'sos' => 'chat_sosAlertShort'.tr(),
      'location' => 'chat_locationShared'.tr(),
      'media' => 'chat_mediaShared'.tr(),
      _ => msg.text,
    };
    SosAlarm.notifyMessage(
      senderId: msg.contactId,
      title: senderName,
      body: body,
    );
  }

  Future<void> openConversation(String contactId) async {
    final userId = ref.read(currentUserProvider)?.id;
    if (userId == null) return;
    await _repo.markRead(myId: userId, senderId: contactId);
  }

  Future<void> sendText({
    required String receiverId,
    required String text,
    String type = 'text',
  }) async {
    final userId = ref.read(currentUserProvider)?.id;
    if (userId == null || text.trim().isEmpty) return;
    state = state.copyWith(sending: true);
    try {
      final msg = await _repo.sendMessage(
        myId: userId,
        receiverId: receiverId,
        content: text,
        type: type,
      );
      state = state.copyWith(messages: [...state.messages, msg]);
    } finally {
      state = state.copyWith(sending: false);
    }
  }

  Future<void> _broadcastSos() async {
    final userId = ref.read(currentUserProvider)?.id;
    if (userId == null) return;
    final sosAlert = ref.read(sosProvider).alert;
    // Antes solo mandaba el link de Google Maps — el contacto no tenía
    // ninguna forma de llegar a /emergency/{id} (la página real donde se ve
    // la transmisión en vivo) desde el chat. El sufijo `sosecure-live:{id}`
    // (invisible en la UI, ver el parseo en emergency_chat_widget.dart) es
    // lo que le permite al widget mostrar el botón "Ver transmisión" en vez
    // de que el usuario tenga que copiar la URL a mano.
    // El sufijo `sosecure-live:{id}` se concatena fuera de la traducción a
    // propósito: es un marcador que parsea la UI, no texto para leer. Si
    // viviera dentro de la cadena traducible, un cambio de un traductor
    // rompería el botón "Ver transmisión" sin que nadie lo note.
    final text = sosAlert != null
        ? '${'chat_sosAlertWithLocation'.tr(namedArgs: {
            'mapUrl':
                'https://maps.google.com/?q=${sosAlert.latitude},${sosAlert.longitude}',
            'liveUrl': '${Env.apiBaseUrl}/emergency/${sosAlert.id}',
          })}\nsosecure-live:${sosAlert.id}'
        : 'chat_sosNoLocation'.tr();
    for (final receiverId in state.resolvedIds.values) {
      if (receiverId == null || receiverId == userId) continue;
      try {
        final msg = await _repo.sendMessage(
          myId: userId,
          receiverId: receiverId,
          content: text,
          type: 'sos',
        );
        state = state.copyWith(messages: [...state.messages, msg]);
      } catch (_) {
        // Best-effort — un fallo de un contacto no debe bloquear a los demás.
      }
    }
  }

  Future<String> askAi({
    required List<EmergencyChatMessage> history,
    double? latitude,
    double? longitude,
  }) {
    final apiHistory = history
        .where((m) => m.contactId == aiContactId)
        .map((m) => {'role': m.isMe ? 'user' : 'assistant', 'content': m.text})
        .toList();
    return _repo.sendToAI(
      history: apiHistory,
      latitude: latitude,
      longitude: longitude,
    );
  }

  void addLocalMessage(EmergencyChatMessage message) {
    state = state.copyWith(messages: [...state.messages, message]);
  }

  void clearUnread() => state = state.copyWith(unread: 0);
}
