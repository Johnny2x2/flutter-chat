import 'package:flutter/material.dart';
import 'package:my_chat_app/utils/constants.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Page to invite friends to an existing chat room
class InviteToRoomPage extends StatefulWidget {
  const InviteToRoomPage({
    Key? key,
    required this.conversationId,
    required this.roomTitle,
  }) : super(key: key);

  final String conversationId;
  final String roomTitle;

  static Route<void> route({
    required String conversationId,
    required String roomTitle,
  }) {
    return MaterialPageRoute(
      builder: (context) => InviteToRoomPage(
        conversationId: conversationId,
        roomTitle: roomTitle,
      ),
    );
  }

  @override
  State<InviteToRoomPage> createState() => _InviteToRoomPageState();
}

class _InviteToRoomPageState extends State<InviteToRoomPage> {
  late final String _myUserId;
  List<Map<String, dynamic>> _availableFriends = [];
  Set<String> _selectedFriendIds = {};
  Set<String> _existingParticipantIds = {};
  bool _isLoading = true;
  bool _isInviting = false;

  @override
  void initState() {
    super.initState();
    _myUserId = supabase.auth.currentUser!.id;
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      // Get existing participants in this room
      final existingParticipants = await supabase
          .from('conversation_participants')
          .select('profile_id')
          .eq('conversation_id', widget.conversationId);

      _existingParticipantIds = existingParticipants
          .map((p) => p['profile_id'] as String)
          .toSet();

      // Get accepted friendships where I am the user or the friend
      final friendsAsUser = await supabase
          .from('friendships')
          .select('*, friend:profiles!friendships_friend_id_fkey(*)')
          .eq('user_id', _myUserId)
          .eq('status', 'accepted');

      final friendsAsFriend = await supabase
          .from('friendships')
          .select('*, user:profiles!friendships_user_id_fkey(*)')
          .eq('friend_id', _myUserId)
          .eq('status', 'accepted');

      final allFriends = [
        ...List<Map<String, dynamic>>.from(friendsAsUser),
        ...List<Map<String, dynamic>>.from(friendsAsFriend),
      ];

      // Filter out friends who are already in the room
      final availableFriends = allFriends.where((friendship) {
        final friendProfile = friendship['friend'] ?? friendship['user'];
        final friendId = friendProfile['id'];
        return !_existingParticipantIds.contains(friendId);
      }).toList();

      setState(() {
        _availableFriends = availableFriends;
        _isLoading = false;
      });
    } on PostgrestException catch (error) {
      if (mounted) {
        context.showErrorSnackBar(message: error.message);
      }
      setState(() {
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) {
        context.showErrorSnackBar(message: unexpectedErrorMessage);
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _inviteFriends() async {
    if (_selectedFriendIds.isEmpty) {
      context.showErrorSnackBar(message: 'Please select at least one friend');
      return;
    }

    setState(() {
      _isInviting = true;
    });

    try {
      // Add selected friends as participants
      final participants = _selectedFriendIds.map((friendId) => {
            'conversation_id': widget.conversationId,
            'profile_id': friendId,
          }).toList();

      await supabase.from('conversation_participants').insert(participants);

      if (mounted) {
        context.showSnackBar(
          message: 'Invited ${_selectedFriendIds.length} friend(s) to the room!',
        );
        Navigator.of(context).pop(true); // Return true to indicate success
      }
    } on PostgrestException catch (error) {
      if (mounted) {
        context.showErrorSnackBar(message: error.message);
      }
    } catch (_) {
      if (mounted) {
        context.showErrorSnackBar(message: unexpectedErrorMessage);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isInviting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Invite to "${widget.roomTitle}"'),
      ),
      body: _isLoading
          ? preloader
          : Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(Icons.person_add, color: Colors.grey),
                      SizedBox(width: 8),
                      Text(
                        'Select friends to invite:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _availableFriends.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Text(
                              'All your friends are already in this room!',
                              style: TextStyle(color: Colors.grey),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _availableFriends.length,
                          itemBuilder: (context, index) {
                            final friendship = _availableFriends[index];
                            final friendProfile =
                                friendship['friend'] ?? friendship['user'];
                            final friendId = friendProfile['id'];
                            final username =
                                friendProfile['username'] ?? 'Unknown';
                            final isSelected =
                                _selectedFriendIds.contains(friendId);

                            return CheckboxListTile(
                              secondary: CircleAvatar(
                                child: Text(getSafeInitials(username)),
                              ),
                              title: Text(username),
                              value: isSelected,
                              activeColor: Colors.orange,
                              onChanged: (bool? selected) {
                                setState(() {
                                  if (selected == true) {
                                    _selectedFriendIds.add(friendId);
                                  } else {
                                    _selectedFriendIds.remove(friendId);
                                  }
                                });
                              },
                            );
                          },
                        ),
                ),
                if (_availableFriends.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: _isInviting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.person_add),
                        label: Text(_isInviting
                            ? 'Inviting...'
                            : 'Invite (${_selectedFriendIds.length} selected)'),
                        onPressed:
                            _isInviting || _selectedFriendIds.isEmpty
                                ? null
                                : _inviteFriends,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
