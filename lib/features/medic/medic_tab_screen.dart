import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/chat_message.dart';
import '../../state/medic_chat_provider.dart';
import '../../state/premium_provider.dart';
import '../../state/settings_provider.dart';

// Puerto de components/tabs/medic-tab.tsx: chat de apoyo psicológico con Claude
// vía /api/chat, con fallback a respuestas enlatadas si falla la red. Gateado
// por `has_premium_access` (misma RPC que usePremium() en la web).
class MedicTabScreen extends ConsumerWidget {
  const MedicTabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final premiumAsync = ref.watch(isPremiumProvider);

    return premiumAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const _UpgradeBanner(),
      data: (isPremium) =>
          isPremium ? const _ChatBody() : const _UpgradeBanner(),
    );
  }
}

class _UpgradeBanner extends StatelessWidget {
  const _UpgradeBanner();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.workspace_premium_outlined, size: 48, color: primary),
            const SizedBox(height: 16),
            const Text(
              'Chat de Apoyo Psicológico',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'El acompañante de bienestar con IA está disponible solo en planes Premium y Familiar.',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBody extends ConsumerStatefulWidget {
  const _ChatBody();

  @override
  ConsumerState<_ChatBody> createState() => _ChatBodyState();
}

class _ChatBodyState extends ConsumerState<_ChatBody> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  static const _quickPrompts = [
    (
      Icons.favorite_border,
      'Ansiedad',
      'Estoy sintiendo mucha ansiedad ahora mismo, ¿me ayudas?',
    ),
    (
      Icons.air,
      'Respirar',
      'Enséñame una técnica de respiración para calmarme',
    ),
    (
      Icons.chat_bubble_outline,
      'Hablar',
      'Solo necesito hablar con alguien de lo que siento',
    ),
    (
      Icons.emoji_emotions_outlined,
      'Técnicas',
      'Dame técnicas rápidas para manejar el estrés',
    ),
  ];

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty) return;
    _inputController.clear();
    await ref.read(medicChatProvider.notifier).send(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(medicChatProvider);
    final simpleMode = ref.watch(simpleModeProvider);
    final fontSize = ref.watch(chatFontSizeProvider);
    final primary = Theme.of(context).colorScheme.primary;

    _scrollToBottom();

    return Column(
      children: [
        Card(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          color: Color.alphaBlend(
            primary.withValues(alpha: 0.05),
            Theme.of(context).colorScheme.surface,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Si estás en crisis, no estás solo/a',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'SAPTEL: 55 5259-8121',
                              style: TextStyle(
                                color: primary,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                            const TextSpan(
                              text: ' · 24 horas',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: chat.messages.length + (chat.loading ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= chat.messages.length) {
                return const _TypingIndicator();
              }
              return _MessageBubble(
                message: chat.messages[index],
                fontSize: fontSize,
              );
            },
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: _quickPrompts.map((p) {
              final (icon, label, prompt) = p;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: OutlinedButton.icon(
                  onPressed: chat.loading ? null : () => _send(prompt),
                  icon: Icon(icon, size: 16),
                  label: Text(label, style: const TextStyle(fontSize: 12)),
                ),
              );
            }).toList(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _inputController,
                  minLines: simpleMode ? 3 : 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  style: TextStyle(fontSize: fontSize),
                  decoration: const InputDecoration(
                    hintText: 'Escribe cómo te sientes...',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: chat.loading ? null : _send,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: chat.loading
                    ? null
                    : () => _send(_inputController.text),
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Escribiendo...',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final double fontSize;
  const _MessageBubble({required this.message, required this.fontSize});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final primary = Theme.of(context).colorScheme.primary;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    final surfaceVariant = Theme.of(
      context,
    ).colorScheme.surfaceContainerHighest;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isUser ? primary : surfaceVariant,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FormattedText(
                content: message.content,
                style: TextStyle(
                  color: isUser
                      ? onPrimary
                      : Theme.of(context).colorScheme.onSurface,
                  fontSize: fontSize,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatTime(message.timestamp),
                style: TextStyle(
                  fontSize: (fontSize * 0.7).clamp(10, 14),
                  color:
                      (isUser
                              ? onPrimary
                              : Theme.of(context).colorScheme.onSurface)
                          .withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime t) {
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}

// Puerto de FormattedMessage.tsx: **negritas** y saltos de línea, sin permitir
// HTML/markup arbitrario del usuario o de la IA.
class _FormattedText extends StatelessWidget {
  final String content;
  final TextStyle style;
  const _FormattedText({required this.content, required this.style});

  @override
  Widget build(BuildContext context) {
    final lines = content.split('\n');
    final spans = <InlineSpan>[];
    for (var i = 0; i < lines.length; i++) {
      for (final part in lines[i].split(RegExp(r'(\*\*.*?\*\*)'))) {
        if (part.isEmpty) continue;
        final boldMatch = RegExp(r'^\*\*(.*)\*\*$').firstMatch(part);
        if (boldMatch != null) {
          spans.add(
            TextSpan(
              text: boldMatch.group(1),
              style: style.copyWith(fontWeight: FontWeight.bold),
            ),
          );
        } else {
          spans.add(TextSpan(text: part, style: style));
        }
      }
      if (i < lines.length - 1) spans.add(const TextSpan(text: '\n'));
    }
    return RichText(text: TextSpan(children: spans));
  }
}
