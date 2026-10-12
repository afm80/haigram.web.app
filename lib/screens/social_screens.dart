import 'package:image_picker/image_picker.dart';
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
                      showOnline: true,
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
                          : conversation.lastSenderUid ==
                                  SocialService.currentUid
                              ? 'أنت: ${conversation.lastMessage}'
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
                  showOnline: true,
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
  final _picker = ImagePicker();
  late final Stream<ChatBlockState> _blockState;
  bool _sending = false;
  bool _showStickers = false;

  static const _stickers = [
    '❤️',
    '😂',
    '😍',
    '🥹',
    '👍',
    '👏',
    '🔥',
    '🥰',
    '😎',
    '🤍',
    '💯',
    '🎉',
  ];

  @override
  void initState() {
    super.initState();
    _blockState = SocialService.blockState(widget.otherUid);
  }

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

  Future<void> _sendSticker(String sticker) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await SocialService.sendSticker(widget.conversationId, sticker);
      if (mounted) setState(() => _showStickers = false);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر إرسال الملصق: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_sending) return;
    try {
      final image = await _picker.pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 70,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() => _sending = true);
      await SocialService.sendImage(widget.conversationId, bytes);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر إرسال الصورة: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _chooseImageSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('اختيار من المعرض'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('التقاط صورة'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _pickImage(source);
  }

  Future<void> _selectChatAction(String action) async {
    if (action == 'profile') {
      openProfile(context, widget.otherUid);
      return;
    }
    if (action == 'block' || action == 'unblock') {
      final blocking = action == 'block';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(blocking ? 'حظر المستخدم؟' : 'إلغاء الحظر؟'),
          content: Text(
            blocking
                ? 'لن تتمكن أنت وهذا المستخدم من إرسال الرسائل لبعضكما.'
                : 'سيتمكن هذا المستخدم من مراسلتك مجدداً.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(blocking ? 'حظر' : 'إلغاء الحظر'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      try {
        await SocialService.setBlocked(widget.otherUid, blocking);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(blocking ? 'تم حظر المستخدم' : 'تم إلغاء الحظر')),
          );
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تعذر تحديث الحظر: $error')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return StreamBuilder<ChatBlockState>(
      stream: _blockState,
      builder: (context, blockSnapshot) {
        if (blockSnapshot.hasError) {
          return Scaffold(
            backgroundColor: colors.bg,
            body: _MessageState(
                message: 'تعذر تحميل حالة الحظر\n${blockSnapshot.error}'),
          );
        }
        final blockState = blockSnapshot.data ??
            const ChatBlockState(blockedByMe: false, blockedByThem: false);
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
                      showOnline: true,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            user?.displayName ?? 'محادثة',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (user != null)
                            Text(
                              '@${user.username}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: context.appColors.textDim,
                                  fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            actions: [
              PopupMenuButton<String>(
                tooltip: 'خيارات المحادثة',
                onSelected: _selectChatAction,
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'profile',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.person_outline),
                      title: Text('عرض الملف الشخصي'),
                    ),
                  ),
                  PopupMenuItem(
                    value: blockState.blockedByMe ? 'unblock' : 'block',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(blockState.blockedByMe
                          ? Icons.person_add_alt_1
                          : Icons.block),
                      title: Text(blockState.blockedByMe
                          ? 'إلغاء الحظر'
                          : 'حظر المستخدم'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              if (blockState.blocked)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: colors.surfaceHigh,
                  child: Text(
                    blockState.blockedByMe
                        ? 'حظرت هذا المستخدم. ألغِ الحظر لإرسال الرسائل.'
                        : 'لا يمكنك مراسلة هذا المستخدم.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.textDim),
                  ),
                ),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[messages.length - 1 - index];
                        final mine =
                            message.senderUid == SocialService.currentUid;
                        final sticker = message.kind == 'sticker';
                        return Align(
                          alignment: mine
                              ? AlignmentDirectional.centerEnd
                              : AlignmentDirectional.centerStart,
                          child: Container(
                            constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.sizeOf(context).width * 0.78),
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: sticker
                                ? const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 2)
                                : const EdgeInsets.symmetric(
                                    horizontal: 13, vertical: 9),
                            decoration: sticker
                                ? null
                                : BoxDecoration(
                                    color: mine
                                        ? const Color(0xFF168CFF)
                                        : colors.surfaceHigh,
                                    borderRadius: BorderRadiusDirectional.only(
                                      topStart: const Radius.circular(18),
                                      topEnd: const Radius.circular(18),
                                      bottomStart:
                                          Radius.circular(mine ? 18 : 4),
                                      bottomEnd: Radius.circular(mine ? 4 : 18),
                                    ),
                                  ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (message.kind == 'image' &&
                                    message.imageBytes != null)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(13),
                                    child: Image.memory(
                                      message.imageBytes!,
                                      width: 220,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                else
                                  Text(
                                    message.text,
                                    style: TextStyle(
                                      color: mine ? Colors.white : colors.text,
                                      fontSize: sticker ? 38 : 15,
                                    ),
                                  ),
                                if (!sticker) const SizedBox(height: 3),
                                if (mine)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        message.readBy.contains(widget.otherUid)
                                            ? Icons.done_all_rounded
                                            : message.deliveredTo
                                                    .contains(widget.otherUid)
                                                ? Icons.done_all_rounded
                                                : Icons.done_rounded,
                                        size: 14,
                                        color: message.readBy
                                                .contains(widget.otherUid)
                                            ? const Color(0xFF53BDEB)
                                            : message.deliveredTo
                                                    .contains(widget.otherUid)
                                                ? Colors.white70
                                                : Colors.white54,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        timeAgo(message.createdAt),
                                        style: TextStyle(
                                          color: mine
                                              ? Colors.white70
                                              : colors.textDim,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  )
                                else
                                  Text(
                                    timeAgo(message.createdAt),
                                    style: TextStyle(
                                      color: colors.textDim,
                                      fontSize: 10,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              if (!blockState.blocked) ...[
                if (_showStickers)
                  Container(
                    height: 112,
                    color: colors.surface,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    child: GridView.count(
                      crossAxisCount: 6,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 8,
                      children: [
                        for (final sticker in _stickers)
                          InkWell(
                            onTap:
                                _sending ? null : () => _sendSticker(sticker),
                            borderRadius: BorderRadius.circular(12),
                            child: Center(
                              child: Text(sticker,
                                  style: const TextStyle(fontSize: 27)),
                            ),
                          ),
                      ],
                    ),
                  ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: 'إرسال صورة أو التقاط صورة',
                          onPressed: _sending ? null : _chooseImageSource,
                          icon: const Icon(Icons.add_circle_outline_rounded),
                        ),
                        IconButton(
                          tooltip: 'الملصقات والرموز التعبيرية',
                          onPressed: () =>
                              setState(() => _showStickers = !_showStickers),
                          icon: Icon(
                            _showStickers
                                ? Icons.keyboard_rounded
                                : Icons.emoji_emotions_outlined,
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _text,
                            minLines: 1,
                            maxLines: 4,
                            maxLength: 2000,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(),
                            onTap: () {
                              if (_showStickers) {
                                setState(() => _showStickers = false);
                              }
                            },
                            decoration: const InputDecoration(
                              hintText: 'اكتب رسالة...',
                              counterText: '',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        IconButton.filled(
                          onPressed: _sending ? null : _send,
                          style: IconButton.styleFrom(
                              backgroundColor: AppColors.accent),
                          icon: _sending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.send_rounded,
                                  color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
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
