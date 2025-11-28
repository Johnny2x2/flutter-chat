/// Represents a private conversation between users
class Conversation {
  Conversation({
    required this.id,
    required this.createdAt,
    this.name,
  });

  /// Unique ID of the conversation
  final String id;

  /// Optional name for the conversation (for group chats)
  final String? name;

  /// Date and time when the conversation was created
  final DateTime createdAt;

  Conversation.fromMap(Map<String, dynamic> map)
      : id = map['id'],
        name = map['name'],
        createdAt = DateTime.parse(map['created_at']);
}
