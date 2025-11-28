import 'dart:async';

import 'package:flutter/material.dart';
import 'package:my_chat_app/pages/chat_page.dart';
import 'package:my_chat_app/pages/create_room_page.dart';
import 'package:my_chat_app/pages/friends_list_page.dart';
import 'package:my_chat_app/pages/register_page.dart';
import 'package:my_chat_app/utils/constants.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart';

/// Page to display list of conversations
class ConversationsPage extends StatefulWidget {
  const ConversationsPage({Key? key}) : super(key: key);

  static Route<void> route() {
    return MaterialPageRoute(
      builder: (context) => const ConversationsPage(),
    );
  }

  @override
  State<ConversationsPage> createState() => _ConversationsPageState();
}

class _ConversationsPageState extends State<ConversationsPage> {
  late final String _myUserId;
  List<Map<String, dynamic>> _conversations = [];
  bool _isLoading = true;
  StreamSubscription? _conversationSubscription;

  @override
  void initState() {
    super.initState();
    _myUserId = supabase.auth.currentUser!.id;
    _loadConversations();
    _subscribeToConversations();
  }

  @override
  void dispose() {
    _conversationSubscription?.cancel();
    super.dispose();
  }

  void _subscribeToConversations() {
    _conversationSubscription = supabase
        .from('conversation_participants')
        .stream(primaryKey: ['id'])
        .eq('profile_id', _myUserId)
        .listen((data) {
          _loadConversations();
        });
  }

  Future<void> _loadConversations() async {
    try {
      // Get all conversations where I am a participant with joined data
      final participations = await supabase
          .from('conversation_participants')
          .select('conversation_id, conversations(*)')
          .eq('profile_id', _myUserId);

      if (participations.isEmpty) {
        setState(() {
          _conversations = [];
          _isLoading = false;
        });
        return;
      }

      final conversationIds = participations
          .map((p) => p['conversation_id'] as String)
          .toList();

      // Get all participants for these conversations (excluding myself)
      final allParticipants = await supabase
          .from('conversation_participants')
          .select('conversation_id, profile_id, profiles(*)')
          .inFilter('conversation_id', conversationIds)
          .neq('profile_id', _myUserId);

      // Get last messages for all conversations
      final allMessages = await supabase
          .from('messages')
          .select()
          .inFilter('conversation_id', conversationIds)
          .order('created_at', ascending: false);

      // Group participants by conversation using fold
      final participantsByConversation = allParticipants.fold<Map<String, List<Map<String, dynamic>>>>(
        {},
        (map, p) {
          final convId = p['conversation_id'] as String;
          (map[convId] ??= []).add(p);
          return map;
        },
      );

      // Get latest message per conversation (first occurrence is latest due to order)
      final lastMessageByConversation = <String, Map<String, dynamic>>{};
      for (final msg in allMessages) {
        final convId = msg['conversation_id'] as String;
        if (!lastMessageByConversation.containsKey(convId)) {
          lastMessageByConversation[convId] = msg;
        }
      }

      // Build conversation list
      final conversations = <Map<String, dynamic>>[];
      for (final participation in participations) {
        final conversationId = participation['conversation_id'] as String;
        final conversationData = participation['conversations'];

        conversations.add({
          'id': conversationId,
          'name': conversationData['name'],
          'created_at': conversationData['created_at'],
          'participants': participantsByConversation[conversationId] ?? [],
          'last_message': lastMessageByConversation[conversationId],
        });
      }

      // Sort by last message time or created_at
      conversations.sort((a, b) {
        final aTime = a['last_message'] != null
            ? DateTime.parse(a['last_message']['created_at'])
            : DateTime.parse(a['created_at']);
        final bTime = b['last_message'] != null
            ? DateTime.parse(b['last_message']['created_at'])
            : DateTime.parse(b['created_at']);
        return bTime.compareTo(aTime);
      });

      setState(() {
        _conversations = conversations;
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

  Future<void> _signOut() async {
    await supabase.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        RegisterPage.route(),
        (route) => false,
      );
    }
  }

  String _getConversationTitle(Map<String, dynamic> conversation) {
    if (conversation['name'] != null) {
      return conversation['name'];
    }
    final participants = conversation['participants'] as List;
    if (participants.isEmpty) {
      return 'Empty Conversation';
    }
    return participants
        .map((p) => (p['profiles'] as Map<String, dynamic>)['username'])
        .join(', ');
  }

  String _getSafeInitials(String text) {
    if (text.isEmpty) return '?';
    if (text.length == 1) return text.toUpperCase();
    return text.substring(0, 2).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat Rooms'),
        actions: [
          IconButton(
            icon: const Icon(Icons.people),
            tooltip: 'Friends',
            onPressed: () async {
              await Navigator.of(context).push(FriendsListPage.route());
              _loadConversations();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: _signOut,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(CreateRoomPage.route());
          _loadConversations();
        },
        icon: const Icon(Icons.add),
        label: const Text('New Room'),
        backgroundColor: Colors.orange,
      ),
      body: _isLoading
          ? preloader
          : _conversations.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.chat_bubble_outline,
                        size: 64,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No chat rooms yet',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Create a room and invite your friends!',
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Create Room'),
                        onPressed: () async {
                          await Navigator.of(context)
                              .push(CreateRoomPage.route());
                          _loadConversations();
                        },
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadConversations,
                  child: ListView.builder(
                    itemCount: _conversations.length,
                    itemBuilder: (context, index) {
                      final conversation = _conversations[index];
                      final title = _getConversationTitle(conversation);
                      final lastMessage = conversation['last_message'];

                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(_getSafeInitials(title)),
                        ),
                        title: Text(title),
                        subtitle: lastMessage != null
                            ? Text(
                                lastMessage['content'],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )
                            : const Text('No messages yet'),
                        trailing: lastMessage != null
                            ? Text(
                                format(
                                  DateTime.parse(lastMessage['created_at']),
                                  locale: 'en_short',
                                ),
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              )
                            : null,
                        onTap: () {
                          Navigator.of(context).push(
                            ChatPage.route(
                              conversationId: conversation['id'],
                              title: title,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
    );
  }
}
