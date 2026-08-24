/// Реплика в переписке с аналитиком.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.mine,
    required this.text,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as int,
    mine: json['role'] == 'user',
    text: (json['text'] ?? '') as String,
    createdAt: DateTime.tryParse(
      (json['created_at'] ?? '') as String,
    )?.toLocal(),
  );

  final int id;

  /// Наша реплика или ответ аналитика.
  final bool mine;

  final String text;
  final DateTime? createdAt;
}
