import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';

import '../services/post_service.dart';
import '../services/social_service.dart';
import '../services/user_service.dart';
import '../theme.dart';
import 'common_widgets.dart';
import 'post_widgets.dart' show timeAgo;
import 'story_widgets.dart' show StoryViewed, StoryViewer;
import '../route_state.dart';

/// صندوق البريد (على طريقة تيكتوك): صف الأصدقاء، ثم المتابعون والإعجابات
/// والتعليقات، ثم المحادثات.
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: const Text('صندوق البريد'),
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
      body: StreamBuilder<List<StoryGroup>>(
        stream: PostService.storyGroups(),
        builder: (context, storySnapshot) {
          final stories = storySnapshot.data ?? const <StoryGroup>[];
          return StreamBuilder<List<Conversation>>(
            stream: SocialService.conversations(),
            builder: (context, snapshot) => ListView(
              padding: const EdgeInsets.only(bottom: 80),
              children: [
                _FollowingRail(
                  stories: stories,
                  error: storySnapshot.error,
                ),
                const _ActivityTiles(),
                const Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(16, 14, 16, 6),
                  child: Text('المحادثات',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                ..._conversationItems(context, snapshot, stories),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _conversationItems(
    BuildContext context,
    AsyncSnapshot<List<Conversation>> snapshot,
    List<StoryGroup> stories,
  ) {
    final colors = context.appColors;
    if (snapshot.hasError) {
      return [
        SizedBox(
          height: 240,
          child: _MessageState(message: 'تعذر تحميل الرسائل\n${snapshot.error}'),
        ),
      ];
    }
    if (!snapshot.hasData) {
      return const [
        Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    final conversations = snapshot.data!;
    if (conversations.isEmpty) {
      return const [
        SizedBox(
          height: 240,
          child: _MessageState(
            message: 'لا توجد محادثات بعد\nابدأ محادثة مع أحد أصدقائك',
            icon: Icons.chat_bubble_outline_rounded,
          ),
        ),
      ];
    }
    return [
      for (final conversation in conversations)
        Column(
          key: ValueKey(conversation.id),
          mainAxisSize: MainAxisSize.min,
          children: [
            _conversationTile(context, conversation, stories),
            Divider(height: 1, indent: 76, color: colors.surfaceHigh),
          ],
        ),
    ];
  }

  Widget _conversationTile(
    BuildContext context,
    Conversation conversation,
    List<StoryGroup> stories,
  ) {
    final colors = context.appColors;
    final otherUid = conversation.otherParticipant(SocialService.currentUid);
    return FutureBuilder<AppUser?>(
      future: UserService.profileOf(otherUid),
      builder: (context, userSnapshot) {
        final user = userSnapshot.data;
        final storyIndex = stories.indexWhere((group) => group.uid == otherUid);
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: UserAvatar(
            uid: otherUid,
            fallbackName: user?.username ?? '',
            profile: user,
            radius: 26,
            showOnline: true,
            hasStory: storyIndex >= 0,
            storySeen:
                storyIndex >= 0 && StoryViewed.allSeen(stories[storyIndex]),
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
                : conversation.lastSenderUid == SocialService.currentUid
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
                  style: TextStyle(color: colors.textDim, fontSize: 11),
                ),
          onTap: () => Navigator.of(context).push(
            appRoute(
              'chat',
              {'cid': conversation.id, 'uid': otherUid},
              (_) => ChatScreen(
                conversationId: conversation.id,
                otherUid: otherUid,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// نوع نشاط في صندوق البريد (متابعون / إعجابات / تعليقات).
class _ActivityCategory {
  final String type;
  final String title;
  final String emptyText;
  final IconData icon;
  final Color color;

  const _ActivityCategory({
    required this.type,
    required this.title,
    required this.emptyText,
    required this.icon,
    required this.color,
  });
}

const _activityCategories = [
  _ActivityCategory(
    type: 'follow',
    title: 'المتابعون',
    emptyText: 'لا يوجد متابعون جدد',
    icon: Icons.person_add_alt_1_rounded,
    color: AppColors.brandCyan,
  ),
  _ActivityCategory(
    type: 'like',
    title: 'الإعجابات',
    emptyText: 'لا توجد إعجابات جديدة',
    icon: Icons.favorite_rounded,
    color: AppColors.brandRed,
  ),
  _ActivityCategory(
    type: 'comment',
    title: 'التعليقات',
    emptyText: 'لا توجد تعليقات جديدة',
    icon: Icons.chat_bubble_rounded,
    color: AppColors.accent,
  ),
];

class _ActivityTiles extends StatefulWidget {
  const _ActivityTiles();

  @override
  State<_ActivityTiles> createState() => _ActivityTilesState();
}

class _ActivityTilesState extends State<_ActivityTiles> {
  late final Stream<List<SocialNotification>> _notifications =
      SocialService.notifications();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SocialNotification>>(
      stream: _notifications,
      builder: (context, snapshot) {
        final all = snapshot.data ?? const <SocialNotification>[];
        return Column(
          children: [
            for (final category in _activityCategories)
              _ActivityTile(
                category: category,
                items: all.where((n) => n.type == category.type).toList(),
              ),
          ],
        );
      },
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final _ActivityCategory category;
  final List<SocialNotification> items;

  const _ActivityTile({required this.category, required this.items});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final unread = items.where((n) => !n.read).length;
    final latest = items.isEmpty ? null : items.first;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: category.color,
        child: Icon(category.icon, color: Colors.white, size: 24),
      ),
      title: Text(category.title,
          style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        latest == null
            ? category.emptyText
            : '@${latest.actorUsername} ${_notificationMessage(latest)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: colors.textDim),
      ),
      trailing: unread > 0
          ? Container(
              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                unread > 99 ? '99+' : '$unread',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700),
              ),
            )
          : Icon(Icons.chevron_left_rounded, color: colors.textDim),
      onTap: () => Navigator.of(context).push(
        appRoute(
          'notifications',
          {'type': category.type, 'title': category.title},
          (_) => NotificationsScreen(
            type: category.type,
            title: category.title,
          ),
        ),
      ),
    );
  }
}

String _notificationMessage(SocialNotification notification) {
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

class _FollowingRail extends StatefulWidget {
  final List<StoryGroup> stories;
  final Object? error;

  const _FollowingRail({required this.stories, this.error});

  @override
  State<_FollowingRail> createState() => _FollowingRailState();
}

class _FollowingRailState extends State<_FollowingRail> {
  late final Stream<List<String>> _following = PostService.followingIds();
  final Map<String, Future<AppUser?>> _profiles = {};

  Future<AppUser?> _profile(String uid) =>
      _profiles.putIfAbsent(uid, () => UserService.profileOf(uid));

  Future<void> _openUser(AppUser user) async {
    final storyIndex =
        widget.stories.indexWhere((group) => group.uid == user.uid);
    if (storyIndex >= 0) {
      await Navigator.of(context).push<void>(
        PageRouteBuilder(
          opaque: true,
          pageBuilder: (_, __, ___) => StoryViewer(
            groups: widget.stories,
            initial: storyIndex,
          ),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
      if (mounted) setState(() {});
      return;
    }

    try {
      if (!await SocialService.areMutualFriends(user.uid)) {
        if (mounted) openProfile(context, user.uid);
        return;
      }
      final conversationId =
          await SocialService.startConversation(user.uid);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        appRoute<void>(
          'chat',
          {'cid': conversationId, 'uid': user.uid},
          (_) => ChatScreen(
            conversationId: conversationId,
            otherUid: user.uid,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر فتح المحادثة: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 112,
      child: StreamBuilder<List<String>>(
        stream: _following,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'تعذر تحميل الأشخاص الذين تتابعهم: ${snapshot.error}',
                style: TextStyle(color: context.appColors.textDim),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          final following = snapshot.data!
              .where((uid) => uid != SocialService.currentUid)
              .toList();
          if (following.isEmpty) {
            return Center(
              child: Text(
                widget.error == null
                    ? 'تابع أصدقاءك لتظهر حساباتهم هنا'
                    : 'تعذر تحميل القصص: ${widget.error}',
                style: TextStyle(color: context.appColors.textDim),
              ),
            );
          }

          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 4),
            itemCount: following.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final uid = following[index];
              final storyIndex =
                  widget.stories.indexWhere((group) => group.uid == uid);
              return FutureBuilder<AppUser?>(
                future: _profile(uid),
                builder: (context, userSnapshot) {
                  final user = userSnapshot.data;
                  if (userSnapshot.hasError) {
                    return SizedBox(
                      width: 68,
                      child: Center(
                        child: Icon(
                          Icons.person_off_outlined,
                          color: context.appColors.textDim,
                        ),
                      ),
                    );
                  }
                  if (user == null) {
                    return const SizedBox(
                      width: 68,
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  }
                  return SizedBox(
                    width: 68,
                    child: InkWell(
                      onTap: () => _openUser(user),
                      borderRadius: BorderRadius.circular(16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          UserAvatar(
                            uid: uid,
                            profile: user,
                            fallbackName: user.username,
                            radius: 25,
                            showOnline: true,
                            hasStory: storyIndex >= 0,
                            storySeen: storyIndex >= 0 &&
                                StoryViewed.allSeen(
                                    widget.stories[storyIndex]),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: context.appColors.text,
                            ),
                          ),
                        ],
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
        appRoute(
          'chat',
          {'cid': conversationId, 'uid': friend.uid},
          (_) => ChatScreen(
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
    '🥳',
    '😘',
    '😭',
    '🙏',
    '✨',
    '🫶',
  ];
  static const _stickerColors = [
    Color(0xFFFFE0E8),
    Color(0xFFFFF0C2),
    Color(0xFFE4DBFF),
    Color(0xFFD8F5E8),
    Color(0xFFDDF2FF),
    Color(0xFFFFE7D6),
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

  Future<void> _showMessageActions(ChatMessage message) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.appColors.surface,
      builder: (sheetContext) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
          title: const Text('حذف الرسالة'),
          onTap: () async {
            Navigator.pop(sheetContext);
            try {
              await SocialService.deleteMessage(
                  widget.conversationId, message.id);
            } catch (error) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('تعذر حذف الرسالة: $error')),
                );
              }
            }
          },
        ),
      ),
    );
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
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onLongPress: mine
                                ? () => _showMessageActions(message)
                                : null,
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
                    height: 150,
                    color: colors.surface,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    child: GridView.count(
                      crossAxisCount: 6,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 8,
                      children: [
                        for (var i = 0; i < _stickers.length; i++)
                          InkWell(
                            onTap:
                                _sending
                                    ? null
                                    : () => _sendSticker(_stickers[i]),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _stickerColors[
                                    i % _stickerColors.length],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _stickers[i],
                                style: const TextStyle(fontSize: 27),
                              ),
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
                          onPressed: () {
                            FocusScope.of(context).unfocus();
                            setState(() => _showStickers = !_showStickers);
                          },
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
  /// عند تحديده تُعرض إشعارات هذا النوع فقط (follow / like / comment).
  final String? type;
  final String? title;

  const NotificationsScreen({super.key, this.type, this.title});

  Future<void> _markAllRead(BuildContext context) async {
    try {
      await SocialService.markAllNotificationsRead(type: type);
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
        title: Text(title ?? 'الإشعارات'),
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
          final notifications = type == null
              ? snapshot.data!
              : snapshot.data!.where((n) => n.type == type).toList();
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
                      TextSpan(text: _notificationMessage(notification)),
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
