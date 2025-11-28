/// Represents a participant in a conversation
class ConversationParticipant {
  ConversationParticipant({
    required this.id,
    required this.conversationId,
    required this.profileId,
    required this.createdAt,
  });

  /// Unique ID of the participant record
  final String id;

  /// ID of the conversation
  final String conversationId;

  /// ID of the user profile
  final String profileId;

  /// Date and time when the participant joined
  final DateTime createdAt;

  ConversationParticipant.fromMap(Map<String, dynamic> map)
      : id = map['id'] as String? ?? '',
        conversationId = map['conversation_id'] as String? ?? '',
        profileId = map['profile_id'] as String? ?? '',
        createdAt = DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now();
}
