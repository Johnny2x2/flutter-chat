import 'package:flutter/material.dart';
import 'package:my_chat_app/models/profile.dart';
import 'package:my_chat_app/utils/constants.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Page to search for and add friends
class AddFriendPage extends StatefulWidget {
  const AddFriendPage({Key? key}) : super(key: key);

  static Route<void> route() {
    return MaterialPageRoute(
      builder: (context) => const AddFriendPage(),
    );
  }

  @override
  State<AddFriendPage> createState() => _AddFriendPageState();
}

class _AddFriendPageState extends State<AddFriendPage> {
  final _searchController = TextEditingController();
  List<Profile> _searchResults = [];
  Set<String> _existingFriendIds = {};
  Set<String> _pendingRequestIds = {};
  bool _isLoading = false;
  bool _hasSearched = false;
  late final String _myUserId;

  @override
  void initState() {
    super.initState();
    _myUserId = supabase.auth.currentUser!.id;
    _loadExistingFriendships();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingFriendships() async {
    try {
      // Get all friendships where I am involved
      final friendshipsAsUser = await supabase
          .from('friendships')
          .select('friend_id, status')
          .eq('user_id', _myUserId);

      final friendshipsAsFriend = await supabase
          .from('friendships')
          .select('user_id, status')
          .eq('friend_id', _myUserId);

      final existingIds = <String>{};
      final pendingIds = <String>{};

      for (final f in friendshipsAsUser) {
        if (f['status'] == 'accepted') {
          existingIds.add(f['friend_id']);
        } else if (f['status'] == 'pending') {
          pendingIds.add(f['friend_id']);
        }
      }

      for (final f in friendshipsAsFriend) {
        if (f['status'] == 'accepted') {
          existingIds.add(f['user_id']);
        } else if (f['status'] == 'pending') {
          pendingIds.add(f['user_id']);
        }
      }

      setState(() {
        _existingFriendIds = existingIds;
        _pendingRequestIds = pendingIds;
      });
    } catch (_) {
      // Silently fail - we'll just show add buttons for everyone
    }
  }

  Future<void> _searchUsers() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      return;
    }

    setState(() {
      _isLoading = true;
      _hasSearched = true;
    });

    try {
      final results = await supabase
          .from('profiles')
          .select()
          .ilike('username', '%$query%')
          .neq('id', _myUserId)
          .limit(20);

      setState(() {
        _searchResults =
            (results as List).map((map) => Profile.fromMap(map)).toList();
        _isLoading = false;
      });
    } on PostgrestException catch (error) {
      context.showErrorSnackBar(message: error.message);
      setState(() {
        _isLoading = false;
      });
    } catch (_) {
      context.showErrorSnackBar(message: unexpectedErrorMessage);
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _sendFriendRequest(String friendId) async {
    try {
      await supabase.from('friendships').insert({
        'user_id': _myUserId,
        'friend_id': friendId,
        'status': 'pending',
      });

      setState(() {
        _pendingRequestIds.add(friendId);
      });

      context.showSnackBar(message: 'Friend request sent!');
    } on PostgrestException catch (error) {
      context.showErrorSnackBar(message: error.message);
    } catch (_) {
      context.showErrorSnackBar(message: unexpectedErrorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Friend'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Search by username',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onSubmitted: (_) => _searchUsers(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _searchUsers,
                  child: const Text('Search'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? preloader
                : _hasSearched
                    ? _searchResults.isEmpty
                        ? const Center(
                            child: Text('No users found'),
                          )
                        : ListView.builder(
                            itemCount: _searchResults.length,
                            itemBuilder: (context, index) {
                              final profile = _searchResults[index];
                              final isFriend =
                                  _existingFriendIds.contains(profile.id);
                              final isPending =
                                  _pendingRequestIds.contains(profile.id);

                              return ListTile(
                                leading: CircleAvatar(
                                  child: Text(
                                    getSafeInitials(profile.username),
                                  ),
                                ),
                                title: Text(profile.username),
                                trailing: isFriend
                                    ? const Chip(
                                        label: Text('Friend'),
                                        backgroundColor: Colors.green,
                                        labelStyle:
                                            TextStyle(color: Colors.white),
                                      )
                                    : isPending
                                        ? const Chip(
                                            label: Text('Pending'),
                                            backgroundColor: Colors.orange,
                                            labelStyle:
                                                TextStyle(color: Colors.white),
                                          )
                                        : ElevatedButton(
                                            onPressed: () =>
                                                _sendFriendRequest(profile.id),
                                            child: const Text('Add'),
                                          ),
                              );
                            },
                          )
                    : const Center(
                        child: Text('Search for users by username'),
                      ),
          ),
        ],
      ),
    );
  }
}
