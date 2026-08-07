import 'package:easy_localization/easy_localization.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/repositories/chat_repository.dart';
import '../domain/models/chat_message.dart';

part 'medic_chat_provider.g.dart';

String get _welcome => 'medic_welcome'.tr();

// Respuestas enlatadas de getOfflineResponse() en medic-tab.tsx — se usan cuando
// /api/chat falla (sin conexión, error del servidor), para no dejar al usuario
// sin ninguna respuesta en un momento de crisis. Las palabras clave de
// detección se quedan en español (coinciden con lo que el usuario escribe,
// que hoy siempre es español/lo que sea que escriba) — solo el contenido
// mostrado se traduce.
Map<String, String> get _offlineResponses => {
  'ansiedad': 'medic_tip5432'.tr(),
  'respiracion': 'medic_tipBoxBreathing'.tr(),
  'crisis': 'medic_tipCrisisLines'.tr(),
  'estres': 'medic_tipAntiStress'.tr(),
};

String? _offlineResponse(String prompt) {
  final lower = prompt.toLowerCase();
  if (lower.contains('ansied') ||
      lower.contains('pánico') ||
      lower.contains('angustia')) {
    return _offlineResponses['ansiedad'];
  }
  if (lower.contains('respira') || lower.contains('calmar')) {
    return _offlineResponses['respiracion'];
  }
  if (lower.contains('crisis') ||
      lower.contains('solo') ||
      lower.contains('llorar') ||
      lower.contains('triste')) {
    return _offlineResponses['crisis'];
  }
  if (lower.contains('estrés') ||
      lower.contains('estres') ||
      lower.contains('técnica')) {
    return _offlineResponses['estres'];
  }
  return null;
}

class MedicChatState {
  final List<ChatMessage> messages;
  final bool loading;

  MedicChatState({required this.messages, this.loading = false});

  MedicChatState copyWith({List<ChatMessage>? messages, bool? loading}) {
    return MedicChatState(
      messages: messages ?? this.messages,
      loading: loading ?? this.loading,
    );
  }
}

// Puerto de la lógica de estado de medic-tab.tsx (sendMessage/getOfflineResponse).
// El historial no se persiste (igual que useState en la web) — se reinicia si se
// cierra la app.
@riverpod
class MedicChat extends _$MedicChat {
  final _repo = ChatRepository();

  @override
  MedicChatState build() {
    return MedicChatState(
      messages: [
        ChatMessage(
          id: 'initial',
          role: 'assistant',
          content: _welcome,
          timestamp: DateTime.now(),
        ),
      ],
    );
  }

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.loading) return;

    final userMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: 'user',
      content: trimmed,
      timestamp: DateTime.now(),
    );
    state = state.copyWith(
      messages: [...state.messages, userMessage],
      loading: true,
    );

    final history = state.messages
        .where((m) => m.id != 'initial')
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();

    String content;
    try {
      content = await _repo.sendMessage(history);
    } catch (_) {
      content = _offlineResponse(trimmed) ?? 'medic_offlineHelp'.tr();
    }

    state = state.copyWith(
      messages: [
        ...state.messages,
        ChatMessage(
          id: '${DateTime.now().millisecondsSinceEpoch}-a',
          role: 'assistant',
          content: content,
          timestamp: DateTime.now(),
        ),
      ],
      loading: false,
    );
  }
}
