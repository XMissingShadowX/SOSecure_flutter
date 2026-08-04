// Puerto de DBMessage/ChatMsg (components/emergency-chat.tsx).
class EmergencyChatMessage {
  final String id;
  final String contactId; // el otro lado de la conversación (uuid, o AI_ID)
  final String text;
  final DateTime timestamp;
  final bool isMe;
  final String type; // 'text' | 'location' | 'sos' | 'ai' | 'media'
  final bool loading;

  const EmergencyChatMessage({
    required this.id,
    required this.contactId,
    required this.text,
    required this.timestamp,
    required this.isMe,
    required this.type,
    this.loading = false,
  });

  // Puerto de dbToUI(): convierte una fila cruda de chat_messages al lado
  // que le corresponde a myId (el contactId siempre es "el otro").
  factory EmergencyChatMessage.fromDb(Map<String, dynamic> row, String myId) {
    final senderId = row['sender_id'] as String;
    final receiverId = row['receiver_id'] as String;
    final isMe = senderId == myId;
    return EmergencyChatMessage(
      id: row['id'] as String,
      contactId: isMe ? receiverId : senderId,
      text: row['content'] as String,
      timestamp: DateTime.parse(row['created_at'] as String),
      isMe: isMe,
      type: row['type'] as String? ?? 'text',
    );
  }
}
