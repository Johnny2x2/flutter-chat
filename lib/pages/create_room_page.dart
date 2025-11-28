import 'package:flutter/material.dart';
import 'package:my_chat_app/pages/chat_page.dart';
import 'package:my_chat_app/utils/constants.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Page to create a new chat room and invite friends
class CreateRoomPage extends StatefulWidget {
  const CreateRoomPage({Key? key}) : super(key: key);

  static Route<void> route() {
    return MaterialPageRoute(
      builder: (context) => const CreateRoomPage(),
    );
  }

  @override
  State<CreateRoomPage> createState() => _CreateRoomPageState();
}

class _CreateRoomPageState extends State<CreateRoomPage> {
  final _roomNameController = TextEditingController();
  late final String _myUserId;
  List<Map<String, dynamic>> _friends = [];
  Set<String> _selectedFriendIds = {};
  bool _isLoading = true;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _myUserId = supabase.auth.currentUser!.id;
    _loadFriends();
  }

  @override
  void dispose() {
    _roomNameController.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    try {
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

      setState(() {
        _friends = [
          ...List<Map<String, dynamic>>.from(friendsAsUser),
          ...List<Map<String, dynamic>>.from(friendsAsFriend),
        ];
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

  Future<void> _createRoom() async {
    if (_selectedFriendIds.isEmpty) {
      context.showErrorSnackBar(message: 'Please select at least one friend');
      return;
    }

    setState(() {
      _isCreating = true;
    });

    try {
      // Create the conversation with optional name
      final roomName = _roomNameController.text.trim();
      final conversationResult = await supabase
          .from('conversations')
          .insert({
            if (roomName.isNotEmpty) 'name': roomName,
          })
          .select()
          .single();

      final conversationId = conversationResult['id'];

      // Add myself and all selected friends as participants
      final participants = [
        {'conversation_id': conversationId, 'profile_id': _myUserId},
        ..._selectedFriendIds.map((friendId) => {
              'conversation_id': conversationId,
              'profile_id': friendId,
            }),
      ];

      await supabase.from('conversation_participants').insert(participants);

      // Get the title for the chat page
      final title = roomName.isNotEmpty
          ? roomName
          : _getSelectedFriendsNames().join(', ');

      if (mounted) {
        // Pop back and navigate to the new chat room
        Navigator.of(context).pop();
        Navigator.of(context).push(
          ChatPage.route(
            conversationId: conversationId,
            title: title,
          ),
        );
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
          _isCreating = false;
        });
      }
    }
  }

  List<String> _getSelectedFriendsNames() {
    final names = <String>[];
    for (final friend in _friends) {
      final friendProfile = friend['friend'] ?? friend['user'];
      final friendId = friendProfile['id'];
      if (_selectedFriendIds.contains(friendId)) {
        names.add(friendProfile['username'] ?? 'Unknown');
      }
    }
    return names;
  }

  String _getSafeInitials(String username) {
    if (username.isEmpty) return '?';
    if (username.length == 1) return username.toUpperCase();
    return username.substring(0, 2).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Chat Room'),
      ),
      body: _isLoading
          ? preloader
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    controller: _roomNameController,
                    decoration: const InputDecoration(
                      labelText: 'Room Name (optional)',
                      hintText: 'Enter a name for your chat room',
                      prefixIcon: Icon(Icons.chat),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    children: [
                      Icon(Icons.people, color: Colors.grey),
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
                const SizedBox(height: 8),
                Expanded(
                  child: _friends.isEmpty
                      ? const Center(
                          child: Text(
                            'No friends yet. Add some friends first!',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _friends.length,
                          itemBuilder: (context, index) {
                            final friendship = _friends[index];
                            final friendProfile =
                                friendship['friend'] ?? friendship['user'];
                            final friendId = friendProfile['id'];
                            final username =
                                friendProfile['username'] ?? 'Unknown';
                            final isSelected =
                                _selectedFriendIds.contains(friendId);

                            return CheckboxListTile(
                              secondary: CircleAvatar(
                                child: Text(_getSafeInitials(username)),
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
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: _isCreating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.add),
                      label: Text(_isCreating
                          ? 'Creating...'
                          : 'Create Room (${_selectedFriendIds.length} selected)'),
                      onPressed:
                          _isCreating || _selectedFriendIds.isEmpty
                              ? null
                              : _createRoom,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
