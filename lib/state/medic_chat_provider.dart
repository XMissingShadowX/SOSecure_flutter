import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/repositories/chat_repository.dart';
import '../domain/models/chat_message.dart';

part 'medic_chat_provider.g.dart';

const _welcome =
    'Hola, soy tu acompañante de bienestar. Puedes contarme cómo te sientes '
    'o pedirme técnicas para manejar ansiedad, estrés o una crisis emocional. '
    'Si estás en peligro físico inmediato, usa el botón SOS de la app.';

// Respuestas enlatadas de getOfflineResponse() en medic-tab.tsx — se usan cuando
// /api/chat falla (sin conexión, error del servidor), para no dejar al usuario
// sin ninguna respuesta en un momento de crisis.
const _offlineResponses = {
  'ansiedad':
      '**Técnica 5-4-3-2-1 para ansiedad:**\nNombra en voz alta:\n• 5 cosas que puedes VER\n• 4 cosas que puedes TOCAR\n• 3 cosas que puedes OÍR\n• 2 cosas que puedes OLER\n• 1 cosa que puedes SABOREAR\n\nEsto ancla tu mente al presente. 💙',
  'respiracion':
      '**Respiración cuadrada (Box Breathing):**\n1. Inhala contando 4 segundos\n2. Retén el aire 4 segundos\n3. Exhala contando 4 segundos\n4. Pausa 4 segundos\n\nRepite 4-6 veces. Usado por fuerzas de élite para calmarse. 🌬️',
  'crisis':
      '**Si estás en crisis emocional:**\n\n🆘 Líneas de apoyo México:\n• SAPTEL: 55 5259-8121 (24h)\n• CONASAMA: 800 290-0024\n• Cruz Roja: 065\n\nNo estás solo/a. Hay personas que quieren ayudarte. 💙',
  'estres':
      '**Técnicas rápidas anti-estrés:**\n• Mueve los hombros en círculos\n• Agua fría en muñecas\n• Cuenta hacia atrás desde 10\n• Haz una lista de 3 cosas por las que estás agradecido/a\n• Estira el cuello suavemente',
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
      content =
          _offlineResponse(trimmed) ??
          '💙 Sin conexión. Si necesitas ayuda:\n• **SAPTEL:** 55 5259-8121';
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
