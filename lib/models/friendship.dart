/// Represents a friendship between two users
class Friendship {
  Friendship({
    required this.id,
    required this.userId,
    required this.friendId,
    required this.status,
    required this.createdAt,
  });

  /// Unique ID of the friendship record
  final String id;

  /// ID of the user who initiated the friendship
  final String userId;

  /// ID of the friend
  final String friendId;

  /// Status of the friendship: 'pending', 'accepted', 'rejected'
  final String status;

  /// Date and time when the friendship was created
  final DateTime createdAt;

  /// Whether the friendship request is pending
  bool get isPending => status == 'pending';

  /// Whether the friendship is accepted
  bool get isAccepted => status == 'accepted';

  Friendship.fromMap(Map<String, dynamic> map)
      : id = map['id'],
        userId = map['user_id'],
        friendId = map['friend_id'],
        status = map['status'],
        createdAt = DateTime.parse(map['created_at']);
}
