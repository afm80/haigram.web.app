import 'package:flutter/material.dart';

import '../services/social_service.dart';
import '../services/user_service.dart';
import '../theme.dart';
import 'common_widgets.dart';
import 'post_widgets.dart' show timeAgo;

class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: const Text('الرسائل'),
        actions: [
          IconButton(
            tooltip: 'رسالة جديدة',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const _FriendsScreen()),
            ),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: StreamBuilder<List<Conversation>>(
        stream: SocialService.conversations(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _MessageState(
                message: 'تعذر تحميل الرسائل\n${snapshot.error}');
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final conversations = snapshot.data!;
          if (conversations.isEmpty) {
            return const _MessageState(
                message: 'لا توجد محادثات بعد\nابدأ محادثة مع أحد أصدقائك',
                icon: Icons.chat_bubble_outline_rounded);
          }
          return ListView.separated(
            itemCount: conversations.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, indent: 76, color: colors.surfaceHigh),
            itemBuilder: (context, index) {
              final conversation = conversations[index];
              final otherUid =
                  conversation.otherParticipant(SocialService.currentUid);
              return FutureBuilder<AppUser?>(
                future: UserService.profileOf(otherUid),
                builder: (context, userSnapshot) {
                  final user = userSnapshot.data;
                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: UserAvatar(
                      uid: otherUid,
                      fallbackName: user?.username ?? '',
                      radius: 26,
                    ),
                    title: Text(
                      user?.displayName ?? 'مستخدم',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      conversation.lastMessage.isEmpty
                          ? 'ابدأ المحادثة'
                          : conversation.lastMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.textDim),
                    ),
                    trailing: conversation.updatedAt.millisecondsSinceEpoch == 0
                        ? null
                        : Text(
                            timeAgo(conversation.updatedAt),
                            style:
                                TextStyle(color: colors.textDim, fontSize: 11),
                          ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          conversationId: conversation.id,
                          otherUid: otherUid,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _FriendsScreen extends StatefulWidget {
  const _FriendsScreen();

  @override
  State<_FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<_FriendsScreen> {
  late final Future<List<AppUser>> _friends = _loadFriends();
  bool _opening = false;

  Future<List<AppUser>> _loadFriends() async {
    final ids = await SocialService.mutualFriendIds();
    final users = await Future.wait(ids.map(UserService.profileOf));
    return users.whereType<AppUser>().toList();
  }

  Future<void> _openChat(AppUser friend) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final conversationId = await SocialService.startConversation(friend.uid);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversationId: conversationId,
            otherUid: friend.uid,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر بدء المحادثة: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(title: const Text('رسالة جديدة')),
      body: FutureBuilder<List<AppUser>>(
        future: _friends,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _MessageState(
                message: 'تعذر تحميل قائمة الأصدقاء\n${snapshot.error}');
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final friends = snapshot.data!;
          if (friends.isEmpty) {
            return const _MessageState(
              message:
                  'لا يوجد أصدقاء متبادلون بعد\nتابعوا بعضكما لتبدآ المحادثة',
              icon: Icons.people_outline_rounded,
            );
          }
          return ListView.builder(
            itemCount: friends.length,
            itemBuilder: (context, index) {
              final friend = friends[index];
              return ListTile(
                leading: UserAvatar(
                  uid: friend.uid,
                  fallbackName: friend.username,
                  radius: 23,
                ),
                title: Text(friend.displayName),
                subtitle: Text('@${friend.username}',
                    style: TextStyle(color: colors.textDim)),
                trailing: _opening
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.chevron_left_rounded),
                onTap: _opening ? null : () => _openChat(friend),
              );
            },
          );
        },
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String otherUid;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.otherUid,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _text = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    final text = _text.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await SocialService.sendMessage(widget.conversationId, text);
      _text.clear();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر إرسال الرسالة: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        titleSpacing: 0,
        title: StreamBuilder<AppUser?>(
          stream: UserService.profileStream(widget.otherUid),
          builder: (context, snapshot) {
            final user = snapshot.data;
            return Row(
              children: [
                UserAvatar(
                  uid: widget.otherUid,
                  fallbackName: user?.username ?? '',
                  radius: 19,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    user?.displayName ?? 'محادثة',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            );
          },
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: SocialService.messages(widget.conversationId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _MessageState(
                      message: 'تعذر تحميل المحادثة\n${snapshot.error}');
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data!;
                if (messages.isEmpty) {
                  return const _MessageState(
                    message: 'أرسل أول رسالة لبدء المحادثة',
                    icon: Icons.waving_hand_outlined,
                  );
                }
                return ListView.builder(
                  reverse: true,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[messages.length - 1 - index];
                    final mine = message.senderUid == SocialService.currentUid;
                    return Align(
                      alignment:
                          mine ? Alignment.centerLeft : Alignment.centerRight,
                      child: Container(
                        constraints: BoxConstraints(
                            maxWidth: MediaQuery.sizeOf(context).width * 0.76),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: mine ? AppColors.accent : colors.surfaceHigh,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          message.text,
                          style: TextStyle(
                              color: mine ? Colors.white : colors.text),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'اكتب رسالة...',
                        counterText: '',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    style:
                        IconButton.styleFrom(backgroundColor: AppColors.accent),
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  String _message(SocialNotification notification) {
    switch (notification.type) {
      case 'follow':
        return 'بدأ بمتابعتك';
      case 'like':
        return 'أعجب بمنشورك';
      case 'comment':
        final text = notification.commentText;
        return text == null || text.isEmpty ? 'علّق على منشورك' : 'علّق: $text';
      default:
        return 'لديك إشعار جديد';
    }
  }

  Future<void> _markAllRead(BuildContext context) async {
    try {
      await SocialService.markAllNotificationsRead();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تحديث الإشعارات: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: const Text('الإشعارات'),
        actions: [
          TextButton(
            onPressed: () => _markAllRead(context),
            child: const Text('قراءة الكل'),
          ),
        ],
      ),
      body: StreamBuilder<List<SocialNotification>>(
        stream: SocialService.notifications(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _MessageState(
                message: 'تعذر تحميل الإشعارات\n${snapshot.error}');
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final notifications = snapshot.data!;
          if (notifications.isEmpty) {
            return const _MessageState(
              message: 'لا توجد إشعارات بعد',
              icon: Icons.notifications_none_rounded,
            );
          }
          return ListView.separated(
            itemCount: notifications.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, indent: 76, color: colors.surfaceHigh),
            itemBuilder: (context, index) {
              final notification = notifications[index];
              return ListTile(
                onTap: notification.read
                    ? null
                    : () async {
                        try {
                          await SocialService.markNotificationRead(
                              notification.id);
                        } catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('تعذر تحديث الإشعار: $error')),
                            );
                          }
                        }
                      },
                leading: UserAvatar(
                  uid: notification.actorUid,
                  fallbackName: notification.actorUsername,
                  radius: 23,
                  onTap: () => openProfile(context, notification.actorUid),
                ),
                title: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '@${notification.actorUsername} ',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: _message(notification)),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  timeAgo(notification.createdAt),
                  style: TextStyle(color: colors.textDim, fontSize: 12),
                ),
                trailing: notification.read
                    ? null
                    : const Icon(Icons.circle,
                        color: AppColors.accent, size: 9),
                tileColor:
                    notification.read ? null : colors.surface.withOpacity(0.7),
              );
            },
          );
        },
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  final String message;
  final IconData icon;

  const _MessageState({
    required this.message,
    this.icon = Icons.mark_chat_unread_outlined,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 50, color: context.appColors.textDim),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.appColors.textDim),
              ),
            ],
          ),
        ),
      );
}
