import 'package:flutter/material.dart';
import 'package:my_chat_app/pages/add_friend_page.dart';
import 'package:my_chat_app/pages/chat_page.dart';
import 'package:my_chat_app/utils/constants.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Page to display the user's friends list
class FriendsListPage extends StatefulWidget {
  const FriendsListPage({Key? key}) : super(key: key);

  static Route<void> route() {
    return MaterialPageRoute(
      builder: (context) => const FriendsListPage(),
    );
  }

  @override
  State<FriendsListPage> createState() => _FriendsListPageState();
}

/// Returns a safe substring for avatar display (up to 2 characters)
String _getSafeInitials(String username) {
  if (username.isEmpty) return '?';
  if (username.length == 1) return username.toUpperCase();
  return username.substring(0, 2).toUpperCase();
}

class _FriendsListPageState extends State<FriendsListPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final String _myUserId;

  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _pendingRequests = [];
  List<Map<String, dynamic>> _sentRequests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _myUserId = supabase.auth.currentUser!.id;
    _loadFriends();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    setState(() {
      _isLoading = true;
    });

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

      // Get pending requests received (where I am the friend)
      final pendingReceived = await supabase
          .from('friendships')
          .select('*, user:profiles!friendships_user_id_fkey(*)')
          .eq('friend_id', _myUserId)
          .eq('status', 'pending');

      // Get pending requests sent (where I am the user)
      final pendingSent = await supabase
          .from('friendships')
          .select('*, friend:profiles!friendships_friend_id_fkey(*)')
          .eq('user_id', _myUserId)
          .eq('status', 'pending');

      setState(() {
        _friends = [
          ...List<Map<String, dynamic>>.from(friendsAsUser),
          ...List<Map<String, dynamic>>.from(friendsAsFriend),
        ];
        _pendingRequests = List<Map<String, dynamic>>.from(pendingReceived);
        _sentRequests = List<Map<String, dynamic>>.from(pendingSent);
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

  Future<void> _acceptFriendRequest(String friendshipId) async {
    try {
      await supabase
          .from('friendships')
          .update({'status': 'accepted'}).eq('id', friendshipId);
      context.showSnackBar(message: 'Friend request accepted!');
      _loadFriends();
    } on PostgrestException catch (error) {
      context.showErrorSnackBar(message: error.message);
    } catch (_) {
      context.showErrorSnackBar(message: unexpectedErrorMessage);
    }
  }

  Future<void> _deleteFriendship(String friendshipId, String successMessage) async {
    try {
      await supabase.from('friendships').delete().eq('id', friendshipId);
      context.showSnackBar(message: successMessage);
      _loadFriends();
    } on PostgrestException catch (error) {
      context.showErrorSnackBar(message: error.message);
    } catch (_) {
      context.showErrorSnackBar(message: unexpectedErrorMessage);
    }
  }

  Future<void> _rejectFriendRequest(String friendshipId) async {
    await _deleteFriendship(friendshipId, 'Friend request rejected');
  }

  Future<void> _removeFriend(String friendshipId) async {
    await _deleteFriendship(friendshipId, 'Friend removed');
  }

  Future<void> _cancelRequest(String friendshipId) async {
    await _deleteFriendship(friendshipId, 'Friend request cancelled');
  }

  Future<void> _startConversation(String friendId, String friendUsername) async {
    try {
      // Find existing 1-on-1 conversation between us using a more efficient query
      // Get all my conversation IDs
      final myConversations = await supabase
          .from('conversation_participants')
          .select('conversation_id')
          .eq('profile_id', _myUserId);

      if (myConversations.isNotEmpty) {
        final myConversationIds = (myConversations as List)
            .map((c) => c['conversation_id'] as String)
            .toList();

        // Find conversations where the friend is also a participant
        final sharedConversations = await supabase
            .from('conversation_participants')
            .select('conversation_id')
            .eq('profile_id', friendId)
            .inFilter('conversation_id', myConversationIds);

        // Check each shared conversation to find a 1-on-1 (exactly 2 participants)
        for (final conv in sharedConversations) {
          final conversationId = conv['conversation_id'] as String;
          final participantCount = await supabase
              .from('conversation_participants')
              .select('id')
              .eq('conversation_id', conversationId);

          if (participantCount.length == 2) {
            // Found existing 1-on-1 conversation
            if (mounted) {
              Navigator.of(context).push(
                ChatPage.route(
                  conversationId: conversationId,
                  title: friendUsername,
                ),
              );
            }
            return;
          }
        }
      }

      // No existing conversation, create a new one
      final conversationResult = await supabase
          .from('conversations')
          .insert({})
          .select()
          .single();

      final conversationId = conversationResult['id'];

      // Add both participants
      await supabase.from('conversation_participants').insert([
        {'conversation_id': conversationId, 'profile_id': _myUserId},
        {'conversation_id': conversationId, 'profile_id': friendId},
      ]);

      if (mounted) {
        Navigator.of(context).push(
          ChatPage.route(
            conversationId: conversationId,
            title: friendUsername,
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.orange,
          unselectedLabelColor: Colors.grey,
          tabs: [
            Tab(
              text: 'Friends (${_friends.length})',
            ),
            Tab(
              text: 'Requests (${_pendingRequests.length})',
            ),
            Tab(
              text: 'Sent (${_sentRequests.length})',
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () async {
              await Navigator.of(context).push(AddFriendPage.route());
              _loadFriends();
            },
          ),
        ],
      ),
      body: _isLoading
          ? preloader
          : TabBarView(
              controller: _tabController,
              children: [
                _buildFriendsList(),
                _buildPendingRequestsList(),
                _buildSentRequestsList(),
              ],
            ),
    );
  }

  Widget _buildFriendsList() {
    if (_friends.isEmpty) {
      return const Center(
        child: Text('No friends yet. Add some friends!'),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadFriends,
      child: ListView.builder(
        itemCount: _friends.length,
        itemBuilder: (context, index) {
          final friendship = _friends[index];
          // Determine if friend data comes from 'friend' or 'user' key
          final friendProfile =
              friendship['friend'] ?? friendship['user'];
          final friendId = friendProfile['id'];
          final username = friendProfile['username'] ?? 'Unknown';

          return ListTile(
            leading: CircleAvatar(
              child: Text(_getSafeInitials(username)),
            ),
            title: Text(username),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.chat, color: Colors.orange),
                  tooltip: 'Start conversation',
                  onPressed: () => _startConversation(friendId, username),
                ),
                IconButton(
                  icon: const Icon(Icons.person_remove, color: Colors.red),
                  tooltip: 'Remove friend',
                  onPressed: () => _showRemoveFriendDialog(
                    friendship['id'],
                    username,
                  ),
                ),
              ],
            ),
            onTap: () => _startConversation(friendId, username),
          );
        },
      ),
    );
  }

  Widget _buildPendingRequestsList() {
    if (_pendingRequests.isEmpty) {
      return const Center(
        child: Text('No pending friend requests'),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadFriends,
      child: ListView.builder(
        itemCount: _pendingRequests.length,
        itemBuilder: (context, index) {
          final request = _pendingRequests[index];
          final userProfile = request['user'];
          final username = userProfile['username'] ?? 'Unknown';

          return ListTile(
            leading: CircleAvatar(
              child: Text(_getSafeInitials(username)),
            ),
            title: Text(username),
            subtitle: const Text('Wants to be your friend'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.check, color: Colors.green),
                  onPressed: () => _acceptFriendRequest(request['id']),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red),
                  onPressed: () => _rejectFriendRequest(request['id']),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSentRequestsList() {
    if (_sentRequests.isEmpty) {
      return const Center(
        child: Text('No sent friend requests'),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadFriends,
      child: ListView.builder(
        itemCount: _sentRequests.length,
        itemBuilder: (context, index) {
          final request = _sentRequests[index];
          final friendProfile = request['friend'];
          final username = friendProfile['username'] ?? 'Unknown';

          return ListTile(
            leading: CircleAvatar(
              child: Text(_getSafeInitials(username)),
            ),
            title: Text(username),
            subtitle: const Text('Request pending'),
            trailing: IconButton(
              icon: const Icon(Icons.cancel, color: Colors.orange),
              onPressed: () => _cancelRequest(request['id']),
            ),
          );
        },
      ),
    );
  }

  void _showRemoveFriendDialog(String friendshipId, String username) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Friend'),
        content: Text('Are you sure you want to remove $username from your friends?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _removeFriend(friendshipId);
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
