import 'dart:async';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';

import '../services/post_service.dart';
import '../services/presence_service.dart';
import '../services/social_service.dart';
import '../services/user_service.dart';
import '../theme.dart';
import 'common_widgets.dart';
import 'post_widgets.dart' show PostDetailScreen, PostImage, timeAgo;
import 'profile_screen.dart' show FollowActionButton, openChatWith;
import 'sticker_sheet.dart';
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
            onPressed: () => rootNavigatorOf(context).push(
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
                const _ActivitySummaryTile(),
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
          child: AppLoading(),
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
          subtitle: StreamBuilder<bool>(
            stream: PresenceService.isOnline(otherUid),
            builder: (context, onlineSnapshot) {
              // المتصل الآن: «نشط الآن» بدل آخر رسالة (كما في تيكتوك).
              if (onlineSnapshot.data == true) {
                return const Text(
                  'نشط الآن',
                  maxLines: 1,
                  style: TextStyle(
                      color: Color(0xFF25D366), fontWeight: FontWeight.w600),
                );
              }
              return Text(
                conversation.lastMessage.isEmpty
                    ? 'ابدأ المحادثة'
                    : conversation.lastSenderUid == SocialService.currentUid
                        ? 'أنت: ${conversation.lastMessage}'
                        : conversation.lastMessage,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.textDim),
              );
            },
          ),
          trailing: conversation.updatedAt.millisecondsSinceEpoch == 0
              ? null
              : Text(
                  timeAgo(conversation.updatedAt),
                  style: TextStyle(color: colors.textDim, fontSize: 11),
                ),
          onTap: () => rootNavigatorOf(context).push(
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

/// صف واحد «النشاط والمتابعون الجدد» (على طريقة تيكتوك) يفتح صفحة النشاط.
class _ActivitySummaryTile extends StatefulWidget {
  const _ActivitySummaryTile();

  @override
  State<_ActivitySummaryTile> createState() => _ActivitySummaryTileState();
}

class _ActivitySummaryTileState extends State<_ActivitySummaryTile> {
  late final Stream<List<SocialNotification>> _notifications =
      SocialService.notifications();

  String _summary(List<SocialNotification> all) {
    final names = <String>[];
    for (final n in all) {
      if ((n.type == 'follow' || n.type == 'followRequest') &&
          !names.contains(n.actorUsername)) {
        names.add(n.actorUsername);
      }
    }
    if (names.length == 1) return '@${names[0]} بدأ بمتابعتك';
    if (names.length == 2) return '@${names[0]} و @${names[1]} يتابعانك';
    if (names.length > 2) {
      return '@${names[0]} و @${names[1]} و ${names.length - 2} آخرين يتابعونك';
    }
    if (all.isNotEmpty) {
      return '@${all.first.actorUsername} ${_notificationMessage(all.first)}';
    }
    return 'لا يوجد نشاط جديد';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return StreamBuilder<List<SocialNotification>>(
      stream: _notifications,
      builder: (context, snapshot) {
        final all = snapshot.data ?? const <SocialNotification>[];
        final unread = all.where((n) => !n.read).length;
        return ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          leading: const CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.brandPurple,
            child: Icon(Icons.bolt_rounded, color: Colors.white, size: 24),
          ),
          title: const Text('النشاط والمتابعون الجدد',
              style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            _summary(all),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textDim),
          ),
          trailing: unread > 0
              ? Container(
                  constraints:
                      const BoxConstraints(minWidth: 22, minHeight: 22),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: const BoxDecoration(
                    color: AppColors.notificationRed,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    widthFactor: 1,
                    heightFactor: 1,
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                )
              : Icon(Icons.chevron_left_rounded, color: colors.textDim),
          onTap: () => rootNavigatorOf(context).push(
            appRoute('activity', const {}, (_) => const ActivityScreen()),
          ),
        );
      },
    );
  }
}

/// «المتابعون» يشمل المتابعة المباشرة وقبول طلباتي.
bool _matchesCategory(SocialNotification n, String type) =>
    n.type == type || (type == 'follow' && n.type == 'followAccepted');

String _notificationMessage(SocialNotification notification) {
  switch (notification.type) {
    case 'follow':
      return 'بدأ بمتابعتك';
    case 'followRequest':
      return 'يريد متابعتك';
    case 'followAccepted':
      return 'قبل طلب متابعتك';
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
      await rootNavigatorOf(context).push<void>(
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
      await rootNavigatorOf(context).push<void>(
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
            return const AppLoading();
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
  Uint8List? _pendingImage; // صورة مرفقة بانتظار الإرسال اليدوي
  Set<String> _hidden = const {};
  StreamSubscription<Set<String>>? _hiddenSub;

  @override
  void initState() {
    super.initState();
    _blockState = SocialService.blockState(widget.otherUid);
    _hiddenSub = SocialService.hiddenMessageIds(widget.conversationId).listen(
      (ids) {
        if (mounted) setState(() => _hidden = ids);
      },
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _hiddenSub?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _showError(String what, Object error) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$what: $error')),
      );
    }
  }

  /// يرسل ما في خانة الكتابة (نص/ملصق) والصورة المرفقة عند ضغط زر الإرسال فقط.
  void _send() {
    final text = _text.text.trim();
    final image = _pendingImage;
    if (text.isEmpty && image == null) return;
    _text.clear();
    setState(() => _pendingImage = null);
    if (image != null) {
      SocialService.sendImage(widget.conversationId, image)
          .catchError((Object e) => _showError('تعذر إرسال الصورة', e));
    }
    if (text.isNotEmpty) {
      final sending = isSingleSticker(text)
          ? SocialService.sendSticker(widget.conversationId, text)
          : SocialService.sendMessage(widget.conversationId, text);
      sending.catchError((Object e) {
        if (mounted && _text.text.isEmpty) _text.text = text;
        _showError('تعذر إرسال الرسالة', e);
      });
    }
  }

  void _openImage(Uint8List bytes) => openFullScreenImage(context, bytes);

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
      if (bytes.length > 700 * 1024) {
        _showError('تعذر إرفاق الصورة', 'حجم الصورة يجب ألا يتجاوز 700 كيلوبايت');
        return;
      }
      setState(() => _pendingImage = bytes);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر إرفاق الصورة: $error')),
        );
      }
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

  Future<void> _showMessageActions(ChatMessage message, bool mine) async {
    Future<void> run(Future<void> Function() action, String failure) async {
      try {
        await action();
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$failure: $error')),
          );
        }
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.appColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (mine)
              ListTile(
                leading: const Icon(Icons.delete_forever_rounded,
                    color: AppColors.brandPurple),
                title: const Text('حذف لدى الجميع'),
                subtitle: const Text('تُحذف الرسالة من المحادثة عند الطرفين'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  run(
                    () => SocialService.deleteMessage(
                        widget.conversationId, message.id),
                    'تعذر حذف الرسالة',
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('حذف لدي فقط'),
              subtitle: const Text('تبقى الرسالة ظاهرة للطرف الآخر'),
              onTap: () {
                Navigator.pop(sheetContext);
                run(
                  () => SocialService.hideMessageForMe(
                      widget.conversationId, message.id),
                  'تعذر حذف الرسالة',
                );
              },
            ),
          ],
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
                      onTap: () => openProfile(context, widget.otherUid),
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
                      return const AppLoading();
                    }
                    final messages = snapshot.data!
                        .where((m) => !_hidden.contains(m.id))
                        .toList();
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
                          final bubble = GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onLongPress: () =>
                                _showMessageActions(message, mine),
                            child: Container(
                            constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.sizeOf(context).width * (mine ? 0.78 : 0.70)),
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
                                        ? AppColors.brandPurple
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
                                  GestureDetector(
                                    onTap: () => _openImage(message.imageBytes!),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(13),
                                      child: Image.memory(
                                        message.imageBytes!,
                                        width: 220,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  )
                                else if (sticker)
                                  StickerGlyph(message.text, size: 56)
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
                                            ? const Color(0xFFC4B5FD)
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
                        return Align(
                          alignment: mine
                              ? AlignmentDirectional.centerEnd
                              : AlignmentDirectional.centerStart,
                          child: mine
                              ? bubble
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    // النقر على صورة المرسل يفتح حسابه.
                                    Padding(
                                      padding:
                                          const EdgeInsetsDirectional.only(
                                              end: 6, bottom: 4),
                                      child: UserAvatar(
                                        uid: message.senderUid,
                                        radius: 14,
                                        onTap: () => openProfile(
                                            context, message.senderUid),
                                      ),
                                    ),
                                    Flexible(child: bubble),
                                  ],
                                ),
                        );
                      },
                    );
                  },
                ),
              ),
              if (!blockState.blocked) ...[
                if (_pendingImage != null)
                  PendingImagePreview(
                    bytes: _pendingImage!,
                    onRemove: () => setState(() => _pendingImage = null),
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
                            showStickerSheet(
                              context,
                              onPick: (sticker) =>
                                  insertAtCursor(_text, sticker),
                            );
                          },
                          icon: const Icon(Icons.emoji_emotions_outlined),
                        ),
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

/// عند النقر على إشعار: يُعلَّم مقروءاً ثم ينقلك إلى مصدره حسب نوعه:
/// متابعة ← ملف المتابِع، إعجاب ← المنشور، تعليق ← المنشور مع نافذة التعليقات.
Future<void> _openNotification(
  BuildContext context,
  SocialNotification notification,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);

  if (!notification.read) {
    SocialService.markNotificationRead(notification.id).catchError((Object e) {
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر تحديث الإشعار: $e')),
      );
    });
  }

  if (notification.type == 'follow' ||
      notification.type == 'followRequest' ||
      notification.type == 'followAccepted') {
    openProfile(context, notification.actorUid);
    return;
  }

  final postId = notification.postId;
  if (postId == null || postId.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('تعذر فتح هذا الإشعار')),
    );
    return;
  }

  Post? post;
  try {
    post = await PostService.postById(postId);
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text('تعذر فتح المنشور: $error')),
    );
    return;
  }
  if (!context.mounted) return;
  if (post == null) {
    messenger.showSnackBar(
      const SnackBar(content: Text('هذا المنشور لم يعد متاحاً')),
    );
    return;
  }

  final opened = post;
  navigator.push<void>(appRoute<void>(
    'post',
    {'id': opened.id},
    (_) => PostDetailScreen(post: opened),
  ));

  if (notification.type == 'comment') {
    // ننتظر انتهاء انتقال الصفحة ثم نفتح نافذة التعليقات فوقها.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (context.mounted) showCommentsSheet(context, opened);
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
            return const AppLoading();
          }
          final notifications = type == null
              ? snapshot.data!
              : snapshot.data!
                  .where((n) => _matchesCategory(n, type!))
                  .toList();
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
            itemBuilder: (context, index) =>
                _NotificationTile(notification: notifications[index]),
          );
        },
      ),
    );
  }
}

/// صف إشعار واحد (يُستعمل في شاشة الإشعارات وتبويب النشاط).
class _NotificationTile extends StatelessWidget {
  final SocialNotification notification;
  final Widget? trailing;
  final String? subtitle;

  const _NotificationTile(
      {required this.notification, this.trailing, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ListTile(
      onTap: () => _openNotification(context, notification),
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
        subtitle ?? timeAgo(notification.createdAt),
        style: TextStyle(color: colors.textDim, fontSize: 12),
      ),
      trailing: trailing ??
          (notification.type == 'followRequest'
              ? _FollowRequestActions(requesterUid: notification.actorUid)
              : notification.read
                  ? null
                  : const Icon(Icons.circle,
                      color: AppColors.notificationRed, size: 9)),
      tileColor: notification.read ? null : colors.surface.withOpacity(0.7),
    );
  }
}

const _arabicMonths = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

String _shortDate(DateTime d) {
  final base = '${d.day} ${_arabicMonths[d.month - 1]}';
  return d.year == DateTime.now().year ? base : '$base ${d.year}';
}

/// صفحة «النشاط والمتابعون الجدد»: تبويبان على طريقة تيكتوك.
class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});

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
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: colors.bg,
        appBar: AppBar(
          title: const Text('النشاط'),
          actions: [
            IconButton(
              tooltip: 'زيارات الملف الشخصي',
              icon: const Icon(Icons.visibility_outlined),
              onPressed: () => rootNavigatorOf(context).push(
                appRoute('profileVisits', const {},
                    (_) => const ProfileVisitsScreen()),
              ),
            ),
            TextButton(
              onPressed: () => _markAllRead(context),
              child: const Text('قراءة الكل'),
            ),
          ],
          bottom: const TabBar(
            tabs: [Tab(text: 'متابعون جدد'), Tab(text: 'النشاط')],
          ),
        ),
        body: StreamBuilder<List<SocialNotification>>(
          stream: SocialService.notifications(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _MessageState(
                  message: 'تعذر تحميل الإشعارات\n${snapshot.error}');
            }
            if (!snapshot.hasData) {
              return const AppLoading();
            }
            final all = snapshot.data!;
            final followers = all
                .where((n) => n.type == 'follow' || n.type == 'followRequest')
                .toList();
            final activity = all
                .where((n) => n.type != 'follow' && n.type != 'followRequest')
                .toList();
            return TabBarView(
              children: [
                _NewFollowersTab(items: followers),
                _ActivityListTab(items: activity),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NewFollowersTab extends StatefulWidget {
  final List<SocialNotification> items;
  const _NewFollowersTab({required this.items});

  @override
  State<_NewFollowersTab> createState() => _NewFollowersTabState();
}

class _NewFollowersTabState extends State<_NewFollowersTab> {
  static const _collapsedCount = 3;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final items = widget.items;
    if (items.isEmpty) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 36),
            child: Column(
              children: [
                Icon(Icons.person_add_alt_1_rounded,
                    size: 50, color: colors.textDim),
                const SizedBox(height: 12),
                Text('لا يوجد متابعون جدد',
                    style: TextStyle(color: colors.textDim)),
              ],
            ),
          ),
          const _SuggestedAccounts(),
          const SizedBox(height: 24),
        ],
      );
    }
    final shown = _expanded ? items : items.take(_collapsedCount).toList();
    return ListView(
      children: [
        for (final n in shown)
          _NotificationTile(
            notification: n,
            subtitle:
                '${n.type == 'followRequest' ? 'يريد متابعتك' : 'بدأ في متابعتك'}. ${_shortDate(n.createdAt)}',
            trailing: n.type == 'followRequest'
                ? _FollowRequestActions(requesterUid: n.actorUid)
                : _FollowBackButton(uid: n.actorUid),
          ),
        if (items.length > _collapsedCount)
          TextButton.icon(
            onPressed: () => setState(() => _expanded = !_expanded),
            icon: Icon(
              _expanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              color: colors.textDim,
            ),
            label: Text(_expanded ? 'عرض أقل' : 'عرض الكل',
                style: TextStyle(color: colors.textDim)),
          ),
        const _SuggestedAccounts(),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _ActivityListTab extends StatelessWidget {
  final List<SocialNotification> items;
  const _ActivityListTab({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _MessageState(
        message: 'لا يوجد نشاط جديد',
        icon: Icons.notifications_none_rounded,
      );
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => Divider(
          height: 1, indent: 76, color: context.appColors.surfaceHigh),
      itemBuilder: (context, index) =>
          _NotificationTile(notification: items[index]),
    );
  }
}

/// «رد المتابعة» إن لم أكن أتابعه، وإلا «مراسلة».
class _FollowBackButton extends StatelessWidget {
  final String uid;
  const _FollowBackButton({required this.uid});

  Future<void> _onPressed(BuildContext context, FollowState state) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      switch (state) {
        case FollowState.none:
          final result = await PostService.follow(uid);
          if (result == FollowState.requested) {
            messenger.showSnackBar(const SnackBar(
                content: Text('تم إرسال طلب المتابعة، بانتظار الموافقة')));
          }
        case FollowState.requested:
          await PostService.cancelFollowRequest(uid);
        case FollowState.following:
          await openChatWith(context, uid);
      }
    } catch (error) {
      messenger.showSnackBar(
          SnackBar(content: Text('تعذر تنفيذ الإجراء: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return StreamBuilder<FollowState>(
      stream: PostService.followState(uid),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }
        final state = snapshot.data!;
        final red = state == FollowState.none;
        return FilledButton(
          onPressed: () => _onPressed(context, state),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            backgroundColor: red ? AppColors.brandPurple : colors.surfaceHigh,
            foregroundColor: red ? Colors.white : colors.text,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(
            switch (state) {
              FollowState.none => 'رد المتابعة',
              FollowState.requested => 'تم إرسال الطلب',
              FollowState.following => 'مراسلة',
            },
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        );
      },
    );
  }
}

/// حساب مقترح مع سبب الاقتراح.
class _Suggestion {
  final AppUser user;
  final String reason;
  const _Suggestion(this.user, this.reason);
}

/// «حسابات مقترحة»: أولاً من يتابعهم من أتابعهم، ثم أصحاب آخر المنشورات.
class _SuggestedAccounts extends StatefulWidget {
  const _SuggestedAccounts();

  @override
  State<_SuggestedAccounts> createState() => _SuggestedAccountsState();
}

class _SuggestedAccountsState extends State<_SuggestedAccounts> {
  static const _maxSuggestions = 8;
  late final Future<List<_Suggestion>> _future = _load();
  final Set<String> _dismissed = {};

  Future<List<_Suggestion>> _load() async {
    final me = PostService.uidOrEmpty;
    final following = (await PostService.followingIdsOnce(me)).toSet();
    final known = {me, ...following};

    // 1) من يتابعهم من أتابعهم (حتى 10 حسابات للعيّنة).
    final counts = <String, int>{};
    final sample = following.take(10).toList();
    final lists = await Future.wait(sample.map((uid) async {
      try {
        return await PostService.followingIdsOnce(uid);
      } catch (_) {
        return const <String>[];
      }
    }));
    for (final ids in lists) {
      for (final id in ids) {
        if (!known.contains(id)) counts[id] = (counts[id] ?? 0) + 1;
      }
    }
    final ranked = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final candidates = <String, String>{
      for (final e in ranked) e.key: 'أشخاص قد تعرفهم',
    };

    // 2) تكملة من أصحاب أحدث الصور.
    if (candidates.length < _maxSuggestions) {
      try {
        final recent = await PostService.stream(PostType.photo, limit: 30).first;
        for (final post in recent) {
          if (!known.contains(post.uid) && !candidates.containsKey(post.uid)) {
            candidates[post.uid] = 'مقترح لك';
          }
        }
      } catch (_) {}
    }

    final result = <_Suggestion>[];
    for (final entry in candidates.entries) {
      if (result.length >= _maxSuggestions) break;
      try {
        if (await SocialService.isBlockedEither(entry.key)) continue;
        final user = await UserService.profileOf(entry.key);
        if (user != null) result.add(_Suggestion(user, entry.value));
      } catch (_) {}
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return FutureBuilder<List<_Suggestion>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: AppLoading(),
          );
        }
        final items = (snapshot.data ?? const <_Suggestion>[])
            .where((s) => !_dismissed.contains(s.user.uid))
            .toList();
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 4),
              child: Text('حسابات مقترحة',
                  style: TextStyle(
                      color: colors.textDim, fontWeight: FontWeight.w700)),
            ),
            for (final item in items)
              _SuggestionCard(
                key: ValueKey(item.user.uid),
                suggestion: item,
                onDismiss: () =>
                    setState(() => _dismissed.add(item.user.uid)),
              ),
          ],
        );
      },
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final _Suggestion suggestion;
  final VoidCallback onDismiss;

  const _SuggestionCard(
      {super.key, required this.suggestion, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final user = suggestion.user;
    return Column(
      children: [
        ListTile(
          onTap: () => openProfile(context, user.uid),
          leading: UserAvatar(
            uid: user.uid,
            fallbackName: user.username,
            profile: user,
            radius: 24,
          ),
          title: Text(user.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('@${user.username} · ${suggestion.reason}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.textDim, fontSize: 12)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 100,
                height: 38,
                child: Center(
                  child: FollowActionButton(uid: user.uid, compact: true),
                ),
              ),
              IconButton(
                tooltip: 'إخفاء',
                onPressed: onDismiss,
                icon: Icon(Icons.close_rounded, color: colors.textDim),
              ),
            ],
          ),
        ),
        if (!user.isPrivate) _SuggestionThumbs(uid: user.uid),
        Divider(height: 20, color: colors.surfaceHigh),
      ],
    );
  }
}

/// حتى 4 صور مصغّرة من أحدث منشورات الحساب المقترح.
class _SuggestionThumbs extends StatefulWidget {
  final String uid;
  const _SuggestionThumbs({required this.uid});

  @override
  State<_SuggestionThumbs> createState() => _SuggestionThumbsState();
}

class _SuggestionThumbsState extends State<_SuggestionThumbs> {
  late final Future<List<Post>> _posts = _load();

  Future<List<Post>> _load() async {
    try {
      final posts = await PostService.profilePosts(widget.uid, limit: 8).first;
      return posts
          .where((p) => p.type == PostType.photo)
          .take(4)
          .toList();
    } catch (_) {
      return const <Post>[];
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Post>>(
      future: _posts,
      builder: (context, snapshot) {
        final posts = snapshot.data ?? const <Post>[];
        if (posts.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: i < posts.length
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: PostImage(post: posts[i]),
                          )
                        : const SizedBox.shrink(),
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

/// «زيارات الملف الشخصي»: من زاروا ملفي خلال آخر 30 يوماً.
class ProfileVisitsScreen extends StatelessWidget {
  const ProfileVisitsScreen({super.key});

  Future<void> _setEnabled(BuildContext context, bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await UserService.updatePrivacy(profileVisits: value);
    } catch (error) {
      messenger.showSnackBar(
          SnackBar(content: Text('تعذر حفظ الإعداد: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final myUid = SocialService.currentUid;
    return StreamBuilder<AppUser?>(
      stream: UserService.profileStream(myUid),
      builder: (context, profileSnapshot) {
        final enabled =
            (profileSnapshot.data ?? UserService.me)?.profileVisits ?? true;
        return Scaffold(
          backgroundColor: colors.bg,
          appBar: AppBar(
            title: const Text('زيارات الملف الشخصي'),
            actions: [
              Switch(
                value: enabled,
                activeColor: AppColors.brandPurple,
                onChanged: (value) => _setEnabled(context, value),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: !enabled
              ? const _MessageState(
                  message:
                      'ميزة زيارات الملف الشخصي متوقفة.\nشغّلها من الزر بالأعلى لتعرف من زار ملفك ويرى الآخرون زياراتك لهم.',
                  icon: Icons.visibility_off_outlined,
                )
              : StreamBuilder<List<ProfileVisit>>(
                  stream: SocialService.profileVisits(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return _MessageState(
                          message: 'تعذر تحميل الزيارات\n${snapshot.error}');
                    }
                    if (!snapshot.hasData) {
                      return const AppLoading();
                    }
                    final visits = snapshot.data!;
                    return ListView(
                      children: [
                        if (visits.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 36),
                            child: Column(
                              children: [
                                Icon(Icons.visibility_outlined,
                                    size: 50, color: colors.textDim),
                                const SizedBox(height: 12),
                                Text('لا توجد زيارات بعد',
                                    style: TextStyle(color: colors.textDim)),
                              ],
                            ),
                          ),
                        for (final visit in visits) _VisitTile(visit: visit),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'قد تظهر هنا أسماء الأشخاص الذين شغّلوا سجل الزيارات لديهم وزاروا ملفك الشخصي خلال آخر 30 يوماً. بإمكانهم أيضاً رؤية متى تزور ملفهم الشخصي. يمكنك إيقاف هذا الإعداد في أي وقت.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: colors.textDim,
                                fontSize: 12,
                                height: 1.5),
                          ),
                        ),
                      ],
                    );
                  },
                ),
        );
      },
    );
  }
}

class _VisitTile extends StatelessWidget {
  final ProfileVisit visit;
  const _VisitTile({required this.visit});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return FutureBuilder<AppUser?>(
      future: UserService.profileOf(visit.uid),
      builder: (context, snapshot) {
        final user = snapshot.data;
        return ListTile(
          onTap: () => openProfile(context, visit.uid),
          leading: UserAvatar(
            uid: visit.uid,
            fallbackName: user?.username ?? '',
            profile: user,
            radius: 24,
          ),
          title: Text(user?.displayName ?? 'مستخدم',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(timeAgo(visit.at),
              style: TextStyle(color: colors.textDim, fontSize: 12)),
          trailing: SizedBox(
            width: 118,
            height: 38,
            child: Center(
              child: FollowActionButton(uid: visit.uid, compact: true),
            ),
          ),
        );
      },
    );
  }
}

/// أزرار قبول/رفض طلب متابعة وارد (تظهر فقط ما دام الطلب معلّقاً).
class _FollowRequestActions extends StatefulWidget {
  final String requesterUid;

  const _FollowRequestActions({required this.requesterUid});

  @override
  State<_FollowRequestActions> createState() => _FollowRequestActionsState();
}

class _FollowRequestActionsState extends State<_FollowRequestActions> {
  late final Stream<bool> _pending =
      PostService.hasIncomingRequest(widget.requesterUid);
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('تعذر تنفيذ الإجراء: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return StreamBuilder<bool>(
      stream: _pending,
      builder: (context, snapshot) {
        if (snapshot.data != true) {
          return Text('تمت المعالجة',
              style: TextStyle(color: colors.textDim, fontSize: 12));
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run(() =>
                      PostService.approveFollowRequest(widget.requesterUid)),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandPurple,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('قبول', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 6),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _run(() =>
                      PostService.declineFollowRequest(widget.requesterUid)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('رفض', style: TextStyle(fontSize: 12)),
            ),
          ],
        );
      },
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
