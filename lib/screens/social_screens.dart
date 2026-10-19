import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/post_service.dart';
import '../services/presence_service.dart';
import '../services/social_service.dart';
import '../services/user_service.dart';
import '../theme.dart';
import 'common_widgets.dart';
import 'photo_tools.dart' show fitImageUnderLimit;
import 'post_widgets.dart' show PostDetailScreen, PostImage, timeAgo;
import 'profile_screen.dart' show FollowActionButton, openChatWith;
import 'sticker_sheet.dart';
import 'story_widgets.dart' show StoryViewed, StoryViewer;
import '../route_state.dart';

import '../l10n.dart';
import '../net_error.dart';

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
        title: Text(tr('صندوق البريد')),
        actions: [
          IconButton(
            tooltip: tr('رسالة جديدة'),
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
                const _NotificationsSummaryTile(),
                Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(16, 14, 16, 6),
                  child: Text(tr('المحادثات'),
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
          height: 320,
          child: ErrorState(
              error: snapshot.error, title: tr('تعذر تحميل الرسائل')),
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
    // المحادثات التي لم تُرسل فيها أي رسالة بعد لا تظهر في الصندوق.
    // ولا تظهر ما مسحتُها «لديّ» ما لم يصلها نشاط بعد المسح.
    final conversations = snapshot.data!
        .where((c) => c.visibleFor(SocialService.currentUid))
        .toList();
    if (conversations.isEmpty) {
      return [
        SizedBox(
          height: 240,
          child: _MessageState(
            message: tr('لا توجد محادثات بعد\nابدأ محادثة مع أحد أصدقائك'),
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
    final unread = conversation.unreadFor(SocialService.currentUid);
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
            user?.displayName ?? tr('مستخدم'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: StreamBuilder<bool>(
            stream: PresenceService.isOnline(otherUid),
            builder: (context, onlineSnapshot) {
              // المتصل الآن: «نشط الآن» بدل آخر رسالة (كما في تيكتوك).
              if (onlineSnapshot.data == true) {
                return Text(
                  tr('نشط الآن'),
                  maxLines: 1,
                  style: TextStyle(
                      color: Color(0xFF25D366), fontWeight: FontWeight.w600),
                );
              }
              return _LastMessagePreview(
                conversation: conversation,
                unread: unread,
              );
            },
          ),
          trailing: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (conversation.updatedAt.millisecondsSinceEpoch != 0)
                Text(
                  timeAgo(conversation.updatedAt),
                  style: TextStyle(
                      color: unread ? colors.text : colors.textDim,
                      fontSize: 11),
                ),
              if (unread)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          // ضغطة مطولة: حذف المحادثة لديّ فقط.
          onLongPress: () => _confirmAndClearChat(context, conversation.id),
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

/// معاينة آخر رسالة في الصندوق. تحترم «حذف لديّ فقط»: إن كانت آخر رسالة قد
/// أخفيتُها لا يظهر نصها هنا.
class _LastMessagePreview extends StatefulWidget {
  final Conversation conversation;
  final bool unread;

  const _LastMessagePreview({
    required this.conversation,
    required this.unread,
  });

  @override
  State<_LastMessagePreview> createState() => _LastMessagePreviewState();
}

class _LastMessagePreviewState extends State<_LastMessagePreview> {
  StreamSubscription<Set<String>>? _sub;
  Set<String> _hidden = const {};

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(covariant _LastMessagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversation.id != widget.conversation.id) {
      _sub?.cancel();
      _hidden = const {};
      _listen();
    }
  }

  void _listen() {
    _sub = SocialService.hiddenMessageIds(widget.conversation.id).listen(
      (ids) {
        if (mounted) setState(() => _hidden = ids);
      },
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final c = widget.conversation;
    final hidden =
        c.lastMessageId.isNotEmpty && _hidden.contains(c.lastMessageId);
    final text = hidden
        ? tr('تم حذف الرسالة')
        : c.lastMessage.isEmpty
            ? tr('ابدأ المحادثة')
            : c.lastSenderUid == SocialService.currentUid
                ? trf('أنت: {0}', [c.lastMessage])
                : c.lastMessage;
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: widget.unread ? colors.text : colors.textDim,
        fontWeight: widget.unread ? FontWeight.w700 : FontWeight.normal,
        fontStyle: hidden ? FontStyle.italic : FontStyle.normal,
      ),
    );
  }
}

/// يؤكد ثم يحذف المحادثة لديّ فقط (الطرف الآخر لا يتأثر). true عند النجاح.
Future<bool> _confirmAndClearChat(
    BuildContext context, String conversationId) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(tr('حذف المحادثة؟')),
      content: Text(tr('تُحذف المحادثة من قائمتك فقط، وتبقى لدى الطرف الآخر.')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(tr('إلغاء')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(tr('حذف')),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  try {
    await SocialService.clearChatForMe(conversationId);
    return true;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(friendlyError(error, fallback: tr('تعذر حذف المحادثة')))),
      );
    }
    return false;
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

/// الساعة بصيغة 24 ساعة بتوقيت الجهاز.
String _clock(DateTime t) {
  final l = t.toLocal();
  return '${_two(l.hour)}:${_two(l.minute)}';
}

bool _sameDay(DateTime a, DateTime b) {
  final x = a.toLocal();
  final y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

String _dayLabel(DateTime t) {
  final now = DateTime.now();
  if (_sameDay(t, now)) return tr('اليوم');
  if (_sameDay(t, now.subtract(const Duration(days: 1)))) return tr('أمس');
  final l = t.toLocal();
  return '${l.year}/${_two(l.month)}/${_two(l.day)}';
}

/// مدخل موحد للإشعارات، يعرض أحدث حدث ويفتح القائمة الزمنية الكاملة.
class _NotificationsSummaryTile extends StatefulWidget {
  const _NotificationsSummaryTile();

  @override
  State<_NotificationsSummaryTile> createState() =>
      _NotificationsSummaryTileState();
}

class _NotificationsSummaryTileState extends State<_NotificationsSummaryTile> {
  late final Stream<List<SocialNotification>> _notifications =
      SocialService.notifications();

  String _summary(List<SocialNotification> all) {
    if (all.isNotEmpty) {
      return '@${all.first.actorUsername} ${_notificationMessage(all.first)}';
    }
    return tr('لا يوجد نشاط جديد');
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
            child: Icon(Icons.notifications_none_rounded,
                color: Colors.white, size: 24),
          ),
          title: Text(tr('الإشعارات'),
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
            appRoute(
                'notifications', const {}, (_) => const NotificationsScreen()),
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
      return tr('بدأ بمتابعتك');
    case 'followRequest':
      return tr('يريد متابعتك');
    case 'followAccepted':
      return tr('قبل طلب متابعتك');
    case 'like':
      return tr('أعجب بمنشورك');
    case 'comment':
      final text = notification.commentText;
      return text == null || text.isEmpty
          ? tr('علّق على منشورك')
          : trf('علّق: {0}', [text]);
    default:
      return tr('لديك إشعار جديد');
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
      final conversationId = await SocialService.startConversation(user.uid);
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
          SnackBar(
              content: Text(
                  friendlyError(error, fallback: tr('تعذر فتح المحادثة')))),
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
                friendlyError(snapshot.error,
                    fallback: tr('تعذر تحميل الأشخاص الذين تتابعهم')),
                textAlign: TextAlign.center,
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
                    ? tr('تابع أصدقاءك لتظهر حساباتهم هنا')
                    : friendlyError(widget.error,
                        fallback: tr('تعذر تحميل القصص')),
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
                                StoryViewed.allSeen(widget.stories[storyIndex]),
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
  late Future<List<AppUser>> _friends = _loadFriends();
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
          SnackBar(
              content: Text(
                  friendlyError(error, fallback: tr('تعذر بدء المحادثة')))),
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
      appBar: AppBar(title: Text(tr('رسالة جديدة'))),
      body: FutureBuilder<List<AppUser>>(
        future: _friends,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(
                error: snapshot.error,
                title: tr('تعذر تحميل قائمة الأصدقاء'),
                onRetry: () => setState(() => _friends = _loadFriends()));
          }
          if (!snapshot.hasData) {
            return const AppLoading();
          }
          final friends = snapshot.data!;
          if (friends.isEmpty) {
            return _MessageState(
              message: tr(
                  'لا يوجد أصدقاء متبادلون بعد\nتابعوا بعضكما لتبدآ المحادثة'),
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

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _text = TextEditingController();
  final _messageFocus = FocusNode();
  bool _showStickers = false;
  final _picker = ImagePicker();
  final _scroll = ScrollController();
  Timer? _draftTimer;
  late final Stream<ChatBlockState> _blockState;
  StreamSubscription<Map<String, DateTime>>? _typingSub;
  StreamSubscription<RemoteMessage>? _chatPushSub;
  Map<String, DateTime> _typingUsers = const {};
  ChatMessage? _replyTarget;
  DateTime? _readAtWhenOpened;
  bool _capturedReadAtWhenOpened = false;
  bool _sending = false;
  bool _draftRestored = false;
  String? _failedText;
  List<Uint8List> _failedImages = const [];
  // صور مرفقة بانتظار الإرسال اليدوي (حتى 10، كإنستغرام).
  final List<Uint8List> _pendingImages = [];
  static const _maxAttach = 10;
  Set<String> _hidden = const {};
  StreamSubscription<Set<String>>? _hiddenSub;

  // الرسائل: اشتراك واحد يُنشأ في initState (لا يُعاد إنشاؤه مع كل build).
  StreamSubscription<List<ChatMessage>>? _messagesSub;
  List<ChatMessage>? _live; // آخر الرسائل مباشرةً
  final List<ChatMessage> _older = []; // صفحات أقدم حُمّلت عند التمرير
  DateTime? _anchor; // بعد تحميل الأقدم: يبدأ المباشر من هنا بلا حدّ
  bool _hasMore = true;
  Object? _messagesError;
  bool _loadingMore = false;
  bool _foreground = true;

  List<ChatMessage>? get _messages {
    final live = _live;
    if (live == null) return null;
    if (_older.isEmpty) return live;
    final ids = {for (final m in live) m.id};
    return [..._older.where((m) => !ids.contains(m.id)), ...live];
  }

  // حالة المراسلة مع غير الأصدقاء: رسالة أولى نصية فقط ثم انتظار الردّ.
  StreamSubscription<Map<String, dynamic>?>? _chatSub;
  Map<String, dynamic>? _chatData;
  bool? _friends; // null = لم يُعرف بعد (لا نقيّد الواجهة حتى يُعرف)

  /// المحادثة غير مقبولة بعد وليسا صديقين.
  bool get _restricted {
    final data = _chatData;
    if (data == null || _friends != false) return false;
    return !(data['accepted'] as bool? ?? true);
  }

  bool get _hasMessages =>
      ((_chatData?['lastMessageId'] as String?) ?? '').isNotEmpty;

  /// أرسلتُ الرسالة الأخيرة ولم يردّ الطرف الآخر: لا يمكنني الإرسال.
  /// افتتحتُ هذه المحادثة من قبل (حتى لو حذفتُ رسالتي): لا افتتاح ثانٍ.
  bool get _startedByMe =>
      (_chatData?['startedBy'] as List?)?.contains(SocialService.currentUid) ??
      false;

  bool get _waitingForReply =>
      _restricted &&
      ((_hasMessages &&
              _chatData?['lastSenderUid'] == SocialService.currentUid) ||
          (!_hasMessages && _startedByMe));

  /// أول رسالة لغير صديق: نص فقط.
  bool get _firstMessageToStranger =>
      _restricted && !_hasMessages && !_startedByMe;

  /// وقتٌ مخزّن في خريطة بمستند المحادثة (readAt / deliveredAt / clearedAt).
  DateTime? _stampOf(String field, String uid) {
    final raw = _chatData?[field];
    if (raw is Map) {
      final value = raw[uid];
      if (value is Timestamp) return value.toDate();
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _blockState = SocialService.blockState(widget.otherUid);
    _hiddenSub = SocialService.hiddenMessageIds(widget.conversationId).listen(
      (ids) {
        if (mounted) setState(() => _hidden = ids);
      },
      onError: (_) {},
    );
    _typingSub = SocialService.typingState(widget.conversationId).listen(
      (typing) {
        if (mounted) setState(() => _typingUsers = typing);
      },
      onError: (_) {},
    );
    SocialService.registerChatPushNotifications().catchError((_) {});
    _chatPushSub = SocialService.foregroundChatMessages.listen((message) {
      final notification = message.notification;
      if (!mounted || notification == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(notification.body ?? tr('رسالة جديدة')),
          duration: const Duration(seconds: 3),
        ),
      );
    });
    _messageFocus.addListener(_syncTypingState);
    _messageFocus.addListener(_hideStickersOnFocus);
    _text.addListener(_syncTypingState);
    _text.addListener(_scheduleDraftSave);
    _restoreDraft();
    _scroll.addListener(_onScroll);
    _chatSub = SocialService.chatStream(widget.conversationId).listen(
      (data) {
        if (!_capturedReadAtWhenOpened) {
          _capturedReadAtWhenOpened = true;
          final readAt = data?['readAt'];
          final value = readAt is Map ? readAt[SocialService.currentUid] : null;
          if (value is Timestamp) _readAtWhenOpened = value.toDate();
        }
        if (mounted) setState(() => _chatData = data);
      },
      onError: (_) {},
    );
    SocialService.areMutualFriends(widget.otherUid).then((value) {
      if (mounted) setState(() => _friends = value);
    }).catchError((Object _) {});
    _subscribeMessages();
  }

  /// عند الضغط على خانة الكتابة تُغلق لوحة الملصقات ويظهر الكيبورد.
  void _hideStickersOnFocus() {
    if (_messageFocus.hasFocus && _showStickers && mounted) {
      setState(() => _showStickers = false);
    }
  }

  void _toggleStickers() {
    if (_showStickers) {
      setState(() => _showStickers = false);
      _messageFocus.requestFocus();
    } else {
      FocusScope.of(context).unfocus();
      setState(() => _showStickers = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messagesSub?.cancel();
    _chatSub?.cancel();
    _hiddenSub?.cancel();
    _typingSub?.cancel();
    _chatPushSub?.cancel();
    _messageFocus.removeListener(_syncTypingState);
    _messageFocus.removeListener(_hideStickersOnFocus);
    _text.removeListener(_syncTypingState);
    _text.removeListener(_scheduleDraftSave);
    _draftTimer?.cancel();
    _saveDraft();
    _messageFocus.dispose();
    _scroll.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    if (foreground) _markRead();
  }

  void _syncTypingState() {
    if (!mounted) return;
    final shouldType = _messageFocus.hasFocus && _text.text.trim().isNotEmpty;
    SocialService.setTyping(widget.conversationId, isTyping: shouldType)
        .catchError((_) {});
  }

  String get _draftKey =>
      'chat_draft_${SocialService.currentUid}_${widget.conversationId}';

  Future<void> _restoreDraft() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!mounted) return;
      final draft = preferences.getString(_draftKey);
      if (draft != null && _text.text.isEmpty) _text.text = draft;
      _draftRestored = true;
    } catch (_) {}
  }

  void _scheduleDraftSave() {
    if (!_draftRestored) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 350), _saveDraft);
  }

  Future<void> _saveDraft() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final draft = _text.text;
      if (draft.trim().isEmpty) {
        await preferences.remove(_draftKey);
      } else {
        await preferences.setString(_draftKey, draft);
      }
    } catch (_) {}
  }

  void _subscribeMessages() {
    _messagesSub?.cancel();
    _messagesError = null;
    _messagesSub =
        SocialService.messages(widget.conversationId, since: _anchor).listen(
      (messages) {
        if (!mounted) return;
        setState(() {
          _live = messages;
          _messagesError = null;
          _loadingMore = false;
          // إن رجع أقل من الصفحة فلا يوجد أقدم (قبل تحميل أي صفحة أقدم).
          if (_anchor == null && _older.isEmpty) {
            _hasMore = messages.length >= SocialService.messagesPageSize;
          }
        });
        _markRead();
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _messagesError = error;
          _loadingMore = false;
        });
      },
    );
  }

  /// علامة «مقروءة» فقط عندما تكون المحادثة ظاهرة والتطبيق في الواجهة:
  /// كتابة واحدة بوقت أحدث رسالة من الطرف الآخر، لا تعديل كل رسالة.
  void _markRead() {
    final messages = _messages;
    if (!_foreground || !mounted || messages == null) return;
    DateTime? latest;
    for (final m in messages) {
      if (m.senderUid == SocialService.currentUid) continue;
      if (latest == null || m.createdAt.isAfter(latest)) latest = m.createdAt;
    }
    if (latest == null) return;
    final mine = _stampOf('readAt', SocialService.currentUid);
    if (mine != null && !latest.isAfter(mine)) return;
    SocialService.markChatRead(widget.conversationId, latest)
        .catchError((Object _) {});
  }

  /// عند الوصول لأعلى القائمة (أقدم الرسائل) نحمّل صفحة أقدم فقط، دون إعادة
  /// قراءة ما سبق.
  void _onScroll() {
    if (!_scroll.hasClients || _loadingMore || !_hasMore) return;
    if (_live == null) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
      _loadOlder();
    }
  }

  Future<void> _loadOlder() async {
    final live = _live;
    if (live == null || live.isEmpty || _loadingMore) return;
    setState(() => _loadingMore = true);
    final liveStart = live.first.createdAt;
    try {
      final oldest = _older.isNotEmpty ? _older.first : live.first;
      final page = await SocialService.olderMessages(
          widget.conversationId, oldest.createdAt);
      if (!mounted) return;
      setState(() {
        final known = {
          for (final m in _older) m.id,
          for (final m in live) m.id,
        };
        _older.insertAll(0, page.where((m) => !known.contains(m.id)));
        _hasMore = page.length >= SocialService.messagesPageSize;
        _loadingMore = false;
      });
      if (_anchor == null) {
        // من الآن يبدأ المباشر من أقدم رسالة حالية ويكبر بلا حدّ، فلا تنشأ
        // فجوة بين الصفحات الأقدم والرسائل الجديدة.
        _anchor = liveStart;
        _subscribeMessages();
      }
    } catch (error) {
      if (mounted) setState(() => _loadingMore = false);
      _showError(tr('تعذر تحميل الرسائل'), error);
    }
  }

  void _showError(String what, Object error) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(error, fallback: what))),
      );
    }
  }

  Future<void> _showMessageSearch() async {
    final controller = TextEditingController();
    var generation = 0;
    var loading = false;
    Object? error;
    var results = <ChatMessage>[];

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(tr('بحث في المحادثة')),
          content: SizedBox(
            width: 420,
            height: MediaQuery.sizeOf(context).height * 0.55,
            child: Column(
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: tr('اكتب كلمة للبحث'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: IconButton(
                      tooltip: tr('مسح'),
                      onPressed: () {
                        controller.clear();
                        setDialogState(() {
                          generation++;
                          results = [];
                          loading = false;
                          error = null;
                        });
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                  onChanged: (value) async {
                    final request = ++generation;
                    if (value.trim().isEmpty) {
                      setDialogState(() {
                        results = [];
                        loading = false;
                        error = null;
                      });
                      return;
                    }
                    setDialogState(() {
                      loading = true;
                      error = null;
                    });
                    try {
                      final found = await SocialService.searchMessages(
                          widget.conversationId, value);
                      if (!dialogContext.mounted || request != generation) {
                        return;
                      }
                      setDialogState(() {
                        results = found;
                        loading = false;
                      });
                    } catch (searchError) {
                      if (!dialogContext.mounted || request != generation) {
                        return;
                      }
                      setDialogState(() {
                        error = searchError;
                        loading = false;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: loading
                      ? const Center(
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : error != null
                          ? Center(child: Text(tr('تعذر البحث في المحادثة')))
                          : results.isEmpty
                              ? Center(
                                  child: Text(
                                      controller.text.trim().isEmpty
                                          ? tr('اكتب كلمة للبحث')
                                          : tr('لا توجد نتائج'),
                                      textAlign: TextAlign.center))
                              : ListView.builder(
                                  itemCount: results.length,
                                  itemBuilder: (context, index) {
                                    final message = results[index];
                                    return ListTile(
                                      dense: true,
                                      leading: Icon(message.kind == 'image'
                                          ? Icons.image_outlined
                                          : Icons.chat_bubble_outline_rounded),
                                      title: Text(
                                        message.text,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        textDirection:
                                            SocialService.inferTextDirection(
                                                message.text),
                                      ),
                                      subtitle: Text(
                                        '${_dayLabel(message.createdAt)} · ${_clock(message.createdAt)}',
                                      ),
                                      trailing: IconButton(
                                        tooltip: tr('نسخ الرسالة'),
                                        onPressed: () {
                                          Clipboard.setData(ClipboardData(
                                              text: message.text));
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(SnackBar(
                                                  content: Text(
                                                      tr('تم نسخ الرسالة'))));
                                        },
                                        icon: const Icon(Icons.copy_rounded),
                                      ),
                                    );
                                  },
                                ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(tr('إغلاق')),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  /// يرسل الصورة المرفقة ثم النص (بهذا الترتيب) عند ضغط زر الإرسال فقط.
  /// رفع الصورة هو الجزء البطيء، لذلك يُعطَّل الزر أثناءه فقط.
  Future<void> _send() async {
    if (_sending) return;
    final text = _text.text.trim();
    final images = List<Uint8List>.of(_pendingImages);
    final replyTarget = _replyTarget;
    if (text.isEmpty && images.isEmpty) return;
    _text.clear();
    setState(() {
      _pendingImages.clear();
      _failedText = null;
      _failedImages = const [];
    });

    if (images.isNotEmpty) {
      setState(() => _sending = true);
      var sent = 0;
      try {
        for (final image in images) {
          // الردّ يُرفق بأول صورة فقط.
          await SocialService.sendImage(
            widget.conversationId,
            image,
            replyToMessageId: sent == 0 ? replyTarget?.id : null,
            replyToText: sent == 0 ? replyTarget?.text : null,
            replyToSenderUid: sent == 0 ? replyTarget?.senderUid : null,
          );
          sent++;
        }
      } catch (e) {
        if (mounted) {
          final rest = images.sublist(sent);
          if (_pendingImages.isEmpty) _pendingImages.addAll(rest);
          if (_text.text.isEmpty) _text.text = text;
          setState(() {
            _failedImages = rest;
            _failedText = text.isEmpty ? null : text;
          });
        }
        _showError(tr('تعذر إرسال الصورة'), e);
        return;
      } finally {
        if (mounted) setState(() => _sending = false);
      }
    }

    if (text.isNotEmpty) {
      final sending = isStickerOnly(text) && !_firstMessageToStranger
          ? SocialService.sendSticker(
              widget.conversationId,
              text,
              replyToMessageId: replyTarget?.id,
              replyToText: replyTarget?.text,
              replyToSenderUid: replyTarget?.senderUid,
            )
          : SocialService.sendMessage(
              widget.conversationId,
              text,
              replyToMessageId: replyTarget?.id,
              replyToText: replyTarget?.text,
              replyToSenderUid: replyTarget?.senderUid,
            );
      try {
        await sending;
        if (mounted) {
          setState(() {
            _replyTarget = null;
            _failedText = null;
            _failedImages = const [];
          });
        }
      } catch (e) {
        if (mounted) {
          if (_text.text.isEmpty) _text.text = text;
          setState(() {
            _failedText = text;
            _failedImages = const [];
          });
        }
        _showError(tr('تعذر إرسال الرسالة'), e);
      }
    } else if (mounted) {
      setState(() => _replyTarget = null);
    }
  }

  void _openNetworkImage(String url) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _NetworkImageViewer(url: url),
      ),
    );
  }

  void _openImage(Uint8List bytes) => openFullScreenImage(context, bytes);

  Future<void> _pickImage(ImageSource source) async {
    if (_sending) return;
    final remote = PostService.useRemoteMedia;
    final maxBytes = remote ? 4 * 1024 * 1024 : 700 * 1024;
    final side = remote ? 1600.0 : 1280.0;
    final quality = remote ? 85 : 70;
    final room = _maxAttach - _pendingImages.length;
    if (room <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('الحد الأقصى 10 صور في الرسالة الواحدة'))),
      );
      return;
    }
    try {
      final List<XFile> files;
      if (source == ImageSource.gallery) {
        files = await _picker.pickMultiImage(
          maxWidth: side,
          maxHeight: side,
          imageQuality: quality,
        );
      } else {
        final shot = await _picker.pickImage(
          source: source,
          maxWidth: side,
          maxHeight: side,
          imageQuality: quality,
        );
        files = shot == null ? const [] : [shot];
      }
      if (files.isEmpty) return;
      final added = <Uint8List>[];
      for (final file in files.take(room)) {
        added.add(await fitImageUnderLimit(
          await file.readAsBytes(),
          maxBytes: maxBytes,
          maxSide: side.round(),
          quality: quality,
        ));
      }
      if (!mounted) return;
      setState(() => _pendingImages.addAll(added));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  friendlyError(error, fallback: tr('تعذر إرفاق الصورة')))),
        );
      }
    }
  }

  Future<void> _selectChatAction(String action) async {
    if (action == 'profile') {
      openProfile(context, widget.otherUid);
      return;
    }
    if (action == 'clear') {
      final cleared =
          await _confirmAndClearChat(context, widget.conversationId);
      if (cleared && mounted) Navigator.of(context).pop();
      return;
    }
    if (action == 'block' || action == 'unblock') {
      final blocking = action == 'block';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(blocking ? tr('حظر المستخدم؟') : tr('إلغاء الحظر؟')),
          content: Text(
            blocking
                ? tr('لن تتمكن أنت وهذا المستخدم من إرسال الرسائل لبعضكما.')
                : tr('سيتمكن هذا المستخدم من مراسلتك مجدداً.'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(tr('إلغاء')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(blocking ? tr('حظر') : tr('إلغاء الحظر')),
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
                content: Text(
                    blocking ? tr('تم حظر المستخدم') : tr('تم إلغاء الحظر'))),
          );
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    friendlyError(error, fallback: tr('تعذر تحديث الحظر')))),
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
            SnackBar(content: Text(friendlyError(error, fallback: failure))),
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
            ListTile(
              leading: const Icon(Icons.add_reaction_outlined),
              title: Text(tr('إضافة تفاعل')),
              onTap: () {
                Navigator.pop(sheetContext);
                _showReactionPicker(message);
              },
            ),
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: Text(tr('رد')),
              onTap: () {
                Navigator.pop(sheetContext);
                if (mounted) setState(() => _replyTarget = message);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: Text(tr('نسخ الرسالة')),
              onTap: () {
                Navigator.pop(sheetContext);
                Clipboard.setData(ClipboardData(text: message.text));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(tr('تم نسخ الرسالة'))),
                  );
                }
              },
            ),
            if (mine)
              ListTile(
                leading: const Icon(Icons.delete_forever_rounded,
                    color: AppColors.brandPurple),
                title: Text(tr('حذف لدى الجميع')),
                subtitle: Text(tr('تُحذف الرسالة من المحادثة عند الطرفين')),
                onTap: () {
                  Navigator.pop(sheetContext);
                  run(
                    () => SocialService.deleteMessage(
                        widget.conversationId, message.id),
                    tr('تعذر حذف الرسالة'),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: Text(tr('حذف لدي فقط')),
              subtitle: Text(tr('تبقى الرسالة ظاهرة للطرف الآخر')),
              onTap: () {
                Navigator.pop(sheetContext);
                run(
                  () => SocialService.hideMessageForMe(
                      widget.conversationId, message.id),
                  tr('تعذر حذف الرسالة'),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// النقر مرتين على رسالة: تفاعل ❤️ سريع (وإن كان موجوداً يُزال)، كإنستغرام.
  /// بقية التفاعلات (😂 👍 🔥 ...) من الضغط المطوّل ← إضافة تفاعل.
  Future<void> _quickHeart(ChatMessage message) async {
    final me = SocialService.currentUid;
    final hasHeart = message.reactions[me] == '❤️';
    HapticFeedback.lightImpact();
    try {
      await SocialService.setMessageReaction(
        widget.conversationId,
        message.id,
        hasHeart ? null : '❤️',
      );
    } catch (error) {
      _showError(tr('تعذر تحديث التفاعل'), error);
    }
  }

  Future<void> _showReactionPicker(ChatMessage message) async {
    const reactions = ['❤️', '😂', '😮', '😢', '👏', '🔥', '👍', '🙏'];
    final selected = await showModalBottomSheet<String?>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final reaction in reactions)
                IconButton(
                  tooltip: reaction,
                  onPressed: () => Navigator.pop(sheetContext, reaction),
                  icon: Text(reaction, style: const TextStyle(fontSize: 28)),
                ),
              IconButton(
                tooltip: tr('إزالة التفاعل'),
                onPressed: () => Navigator.pop(sheetContext, ''),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    try {
      await SocialService.setMessageReaction(
        widget.conversationId,
        message.id,
        selected.isEmpty ? null : selected,
      );
    } catch (error) {
      _showError(tr('تعذر تحديث التفاعل'), error);
    }
  }

  Widget _messageBody(String text, {required bool mine}) {
    final style = TextStyle(
      color: mine ? Colors.white : context.appColors.text,
      fontSize: 15,
      height: 1.35,
    );
    final linkPattern = RegExp(r'https?://\S+|www\.\S+');
    final matches = linkPattern.allMatches(text);
    if (matches.isEmpty) {
      return Text(
        text,
        textDirection: SocialService.inferTextDirection(text),
        style: style,
      );
    }

    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(
          text: text.substring(cursor, match.start),
          style: style,
        ));
      }
      final url = text.substring(match.start, match.end);
      spans.add(TextSpan(
        text: url,
        style: style.copyWith(
          color: mine ? Colors.white : AppColors.brandPurple,
          decoration: TextDecoration.underline,
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () => launchUrl(Uri.parse(url)),
      ));
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(
        text: text.substring(cursor),
        style: style,
      ));
    }

    return RichText(
      textAlign: TextAlign.start,
      textDirection: SocialService.inferTextDirection(text),
      text: TextSpan(children: spans, style: style),
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
            body: ErrorState(
                error: blockSnapshot.error, title: tr('تعذر تحميل حالة الحظر')),
          );
        }
        final blockState = blockSnapshot.data ??
            const ChatBlockState(blockedByMe: false, blockedByThem: false);
        return PopScope(
          canPop: !_showStickers,
          onPopInvoked: (didPop) {
            if (!didPop) setState(() => _showStickers = false);
          },
          child: Scaffold(
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
                            user?.displayName ?? tr('محادثة'),
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
              IconButton(
                tooltip: tr('بحث في المحادثة'),
                onPressed: _showMessageSearch,
                icon: const Icon(Icons.search_rounded),
              ),
              PopupMenuButton<String>(
                tooltip: tr('خيارات المحادثة'),
                onSelected: _selectChatAction,
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'profile',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.person_outline),
                      title: Text(tr('عرض الملف الشخصي')),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'clear',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline_rounded),
                      title: Text(tr('حذف المحادثة لديّ')),
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
                          ? tr('إلغاء الحظر')
                          : tr('حظر المستخدم')),
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
                        ? tr('حظرت هذا المستخدم. ألغِ الحظر لإرسال الرسائل.')
                        : tr('لا يمكنك مراسلة هذا المستخدم.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.textDim),
                  ),
                ),
              Expanded(
                child: Builder(
                  builder: (context) {
                    if (_messagesError != null && _messages == null) {
                      return ErrorState(
                          error: _messagesError,
                          title: tr('تعذر تحميل المحادثة'),
                          onRetry: () {
                            setState(() => _messagesError = null);
                            _subscribeMessages();
                          });
                    }
                    if (_messages == null) {
                      return const AppLoading();
                    }
                    final cleared =
                        _stampOf('clearedAt', SocialService.currentUid);
                    final otherRead = _stampOf('readAt', widget.otherUid);
                    final otherDelivered =
                        _stampOf('deliveredAt', widget.otherUid);
                    final messages = _messages!
                        .where((m) =>
                            !_hidden.contains(m.id) &&
                            (cleared == null || m.createdAt.isAfter(cleared)))
                        .toList();
                    if (messages.isEmpty) {
                      return _MessageState(
                        message: tr('أرسل أول رسالة لبدء المحادثة'),
                        icon: Icons.waving_hand_outlined,
                      );
                    }
                    int? unreadDividerAfter;
                    for (var i = 0; i < messages.length; i++) {
                      final message = messages[messages.length - 1 - i];
                      if (message.senderUid != SocialService.currentUid &&
                          (_readAtWhenOpened == null ||
                              message.createdAt.isAfter(_readAtWhenOpened!))) {
                        unreadDividerAfter = i;
                      }
                    }
                    final unreadDividerPosition = unreadDividerAfter == null
                        ? null
                        : unreadDividerAfter + 1;
                    return ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      itemCount: messages.length +
                          (unreadDividerPosition == null ? 0 : 1) +
                          (_loadingMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (_loadingMore &&
                            index ==
                                messages.length +
                                    (unreadDividerPosition == null ? 0 : 1)) {
                          return const Padding(
                            padding: EdgeInsets.all(12),
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          );
                        }
                        if (index == unreadDividerPosition) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 5),
                                decoration: BoxDecoration(
                                  color: colors.surfaceHigh,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(
                                  tr('رسائل غير مقروءة'),
                                  style: TextStyle(
                                    color: colors.textDim,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }
                        final messageIndex = unreadDividerPosition != null &&
                                index > unreadDividerPosition
                            ? index - 1
                            : index;
                        final message =
                            messages[messages.length - 1 - messageIndex];
                        final mine =
                            message.senderUid == SocialService.currentUid;
                        final sticker = message.kind == 'sticker';
                        // مقروءة/مسلَّمة: إيصال المحادثة (readAt/deliveredAt)
                        // أو الحقول القديمة في الرسالة نفسها (رسائل سابقة).
                        final isRead =
                            message.readBy.contains(widget.otherUid) ||
                                (otherRead != null &&
                                    !message.createdAt.isAfter(otherRead));
                        final isDelivered = isRead ||
                            message.deliveredTo.contains(widget.otherUid) ||
                            (otherDelivered != null &&
                                !message.createdAt.isAfter(otherDelivered));
                        final reactionCounts = <String, int>{};
                        for (final reaction in message.reactions.values) {
                          reactionCounts.update(reaction, (count) => count + 1,
                              ifAbsent: () => 1);
                        }
                        final bubble = GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onDoubleTap: () => _quickHeart(message),
                          onLongPress: () => _showMessageActions(message, mine),
                          child: Container(
                            constraints: BoxConstraints(
                                maxWidth: MediaQuery.sizeOf(context).width *
                                    (mine ? 0.78 : 0.70)),
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
                                if (message.replyToMessageId != null &&
                                    (message.replyToText ?? '')
                                        .trim()
                                        .isNotEmpty)
                                  Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: mine
                                          ? Colors.white.withOpacity(0.12)
                                          : colors.surface,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: mine
                                            ? Colors.white.withOpacity(0.2)
                                            : colors.surfaceHigh,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          tr('ردّ على رسالة'),
                                          style: TextStyle(
                                            color: mine
                                                ? Colors.white70
                                                : colors.textDim,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          message.replyToText ?? '',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: mine
                                                ? Colors.white
                                                : colors.text,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          textDirection:
                                              SocialService.inferTextDirection(
                                                  message.replyToText ?? ''),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (message.kind == 'image' &&
                                    (message.imageUrl != null ||
                                        message.imageBytes != null))
                                  _ChatImage(
                                    url: message.imageUrl,
                                    bytes: message.imageBytes,
                                    onTap: () => message.imageUrl != null
                                        ? _openNetworkImage(message.imageUrl!)
                                        : _openImage(message.imageBytes!),
                                  )
                                else if (sticker)
                                  StickerMessage(message.text)
                                else
                                  _messageBody(message.text, mine: mine),
                                if (!sticker) const SizedBox(height: 3),
                                if (mine)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isDelivered
                                            ? Icons.done_all_rounded
                                            : Icons.done_rounded,
                                        size: 14,
                                        color: isRead
                                            ? const Color(0xFFC4B5FD)
                                            : isDelivered
                                                ? Colors.white70
                                                : Colors.white54,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _clock(message.createdAt),
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
                                    _clock(message.createdAt),
                                    style: TextStyle(
                                      color: colors.textDim,
                                      fontSize: 10,
                                    ),
                                  ),
                                if (reactionCounts.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 5),
                                    child: Wrap(
                                      spacing: 4,
                                      children: [
                                        for (final reaction
                                            in reactionCounts.entries)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: mine
                                                  ? Colors.white
                                                      .withOpacity(0.16)
                                                  : colors.surface,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              '${reaction.key} ${reaction.value}',
                                              style:
                                                  const TextStyle(fontSize: 11),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                        final row = Align(
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
                                      padding: const EdgeInsetsDirectional.only(
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
                        // فاصل التاريخ فوق أول رسالة في كل يوم.
                        final previous = messageIndex + 1 < messages.length
                            ? messages[messages.length - 2 - messageIndex]
                            : null;
                        if (previous != null &&
                            _sameDay(previous.createdAt, message.createdAt)) {
                          return row;
                        }
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: colors.surfaceHigh,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _dayLabel(message.createdAt),
                                  style: TextStyle(
                                      color: colors.textDim, fontSize: 11),
                                ),
                              ),
                            ),
                            row,
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
              if (_typingUsers.keys
                  .any((uid) => uid != SocialService.currentUid))
                SafeArea(
                  top: false,
                  child: Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: colors.surfaceHigh,
                    child: Text(
                      tr('يكتب الآن…'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.textDim,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              if (!blockState.blocked && _waitingForReply)
                SafeArea(
                  top: false,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    color: colors.surfaceHigh,
                    child: Text(
                      tr('انتظر رد الطرف الآخر لتكمل المراسلة'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.textDim),
                    ),
                  ),
                )
              else if (!blockState.blocked) ...[
                if (_firstMessageToStranger)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                    child: Text(
                      tr('هذه أول رسالة لغير صديق: نص فقط، ولن تستطيع إرسال غيرها حتى يردّ.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.textDim, fontSize: 12),
                    ),
                  ),
                if (_failedText != null || _failedImages.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: colors.surfaceHigh,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            tr('تعذر إرسال الرسالة'),
                            style: TextStyle(color: colors.textDim),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _sending
                              ? null
                              : () {
                                  setState(() {
                                    if (_failedImages.isNotEmpty &&
                                        _pendingImages.isEmpty) {
                                      _pendingImages.addAll(_failedImages);
                                    }
                                    if (_failedText != null &&
                                        _text.text.isEmpty) {
                                      _text.text = _failedText!;
                                    }
                                  });
                                  _send();
                                },
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(tr('إعادة المحاولة')),
                        ),
                      ],
                    ),
                  ),
                if (_pendingImages.isNotEmpty)
                  _PendingImagesStrip(
                    images: _pendingImages,
                    onRemove: (index) =>
                        setState(() => _pendingImages.removeAt(index)),
                  ),
                if (_replyTarget != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: colors.surfaceHigh,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${tr('رد على')}: ${_replyTarget!.text}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                TextStyle(color: colors.textDim, fontSize: 12),
                            textDirection: SocialService.inferTextDirection(
                                _replyTarget!.text),
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(() => _replyTarget = null),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          tooltip: tr('إلغاء الرد'),
                        ),
                      ],
                    ),
                  ),
                SafeArea(
                  top: false,
                  bottom: !_showStickers,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // الأزرار تستدعي المنتقي مباشرة داخل الضغطة (شرط المتصفحات).
                        IconButton(
                          tooltip: tr('التقاط صورة'),
                          visualDensity: VisualDensity.compact,
                          onPressed: (_sending || _firstMessageToStranger)
                              ? null
                              : () => _pickImage(ImageSource.camera),
                          icon: const Icon(Icons.photo_camera_outlined),
                        ),
                        IconButton(
                          tooltip: tr('إرسال صورة'),
                          visualDensity: VisualDensity.compact,
                          onPressed: (_sending || _firstMessageToStranger)
                              ? null
                              : () => _pickImage(ImageSource.gallery),
                          icon: const Icon(Icons.image_outlined),
                        ),
                        IconButton(
                          tooltip: tr('الملصقات والرموز التعبيرية'),
                          visualDensity: VisualDensity.compact,
                          onPressed: _toggleStickers,
                          icon: Icon(_showStickers
                              ? Icons.keyboard_alt_outlined
                              : Icons.emoji_emotions_outlined),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _text,
                            focusNode: _messageFocus,
                            minLines: 1,
                            maxLines: 4,
                            maxLength: 2000,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(),
                            decoration: InputDecoration(
                              hintText: tr('اكتب رسالة...'),
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
                if (_showStickers)
                  SafeArea(
                    top: false,
                    child: StickerPanel(controller: _text),
                  ),
              ],
            ],
          ),
        ));
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
        SnackBar(
            content:
                Text(friendlyError(e, fallback: tr('تعذر تحديث الإشعار')))),
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
      SnackBar(content: Text(tr('تعذر فتح هذا الإشعار'))),
    );
    return;
  }

  Post? post;
  try {
    post = await PostService.postById(postId);
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(
          content:
              Text(friendlyError(error, fallback: tr('تعذر فتح المنشور')))),
    );
    return;
  }
  if (!context.mounted) return;
  if (post == null) {
    messenger.showSnackBar(
      SnackBar(content: Text(tr('هذا المنشور لم يعد متاحاً'))),
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
          SnackBar(
              content: Text(
                  friendlyError(error, fallback: tr('تعذر تحديث الإشعارات')))),
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
        title: Text(title ?? tr('الإشعارات')),
        actions: [
          TextButton(
            onPressed: () => _markAllRead(context),
            child: Text(tr('قراءة الكل')),
          ),
        ],
      ),
      body: StreamBuilder<List<SocialNotification>>(
        stream: SocialService.notifications(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(
                error: snapshot.error, title: tr('تعذر تحميل الإشعارات'));
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
            return _MessageState(
              message: tr('لا توجد إشعارات بعد'),
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
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];

String _shortDate(DateTime d) {
  final base = '${d.day} ${tr(_arabicMonths[d.month - 1])}';
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
          SnackBar(
              content: Text(
                  friendlyError(error, fallback: tr('تعذر تحديث الإشعارات')))),
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
          title: Text(tr('النشاط')),
          actions: [
            IconButton(
              tooltip: tr('زيارات الملف الشخصي'),
              icon: const Icon(Icons.visibility_outlined),
              onPressed: () => rootNavigatorOf(context).push(
                appRoute('profileVisits', const {},
                    (_) => const ProfileVisitsScreen()),
              ),
            ),
            TextButton(
              onPressed: () => _markAllRead(context),
              child: Text(tr('قراءة الكل')),
            ),
          ],
          bottom: TabBar(
            tabs: [Tab(text: tr('متابعون جدد')), Tab(text: tr('النشاط'))],
          ),
        ),
        body: StreamBuilder<List<SocialNotification>>(
          stream: SocialService.notifications(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ErrorState(
                  error: snapshot.error, title: tr('تعذر تحميل الإشعارات'));
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
                Text(tr('لا يوجد متابعون جدد'),
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
                '${n.type == 'followRequest' ? tr('يريد متابعتك') : tr('بدأ في متابعتك')}. ${_shortDate(n.createdAt)}',
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
            label: Text(_expanded ? tr('عرض أقل') : tr('عرض الكل'),
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
      return _MessageState(
        message: tr('لا يوجد نشاط جديد'),
        icon: Icons.notifications_none_rounded,
      );
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, indent: 76, color: context.appColors.surfaceHigh),
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
            messenger.showSnackBar(SnackBar(
                content: Text(tr('تم إرسال طلب المتابعة، بانتظار الموافقة'))));
          }
        case FollowState.requested:
          await PostService.cancelFollowRequest(uid);
        case FollowState.following:
          await openChatWith(context, uid);
      }
    } catch (error) {
      messenger.showSnackBar(SnackBar(
          content:
              Text(friendlyError(error, fallback: tr('تعذر تنفيذ الإجراء')))));
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(
            switch (state) {
              FollowState.none => tr('رد المتابعة'),
              FollowState.requested => tr('تم إرسال الطلب'),
              FollowState.following => tr('مراسلة'),
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
      for (final e in ranked) e.key: tr('أشخاص قد تعرفهم'),
    };

    // 2) تكملة من أصحاب أحدث الصور.
    if (candidates.length < _maxSuggestions) {
      try {
        final recent =
            await PostService.stream(PostType.photo, limit: 30).first;
        for (final post in recent) {
          if (!known.contains(post.uid) && !candidates.containsKey(post.uid)) {
            candidates[post.uid] = tr('مقترح لك');
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
              child: Text(tr('حسابات مقترحة'),
                  style: TextStyle(
                      color: colors.textDim, fontWeight: FontWeight.w700)),
            ),
            for (final item in items)
              _SuggestionCard(
                key: ValueKey(item.user.uid),
                suggestion: item,
                onDismiss: () => setState(() => _dismissed.add(item.user.uid)),
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
                tooltip: tr('إخفاء'),
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
      return posts.where((p) => p.type == PostType.photo).take(4).toList();
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
      messenger.showSnackBar(SnackBar(
          content:
              Text(friendlyError(error, fallback: tr('تعذر حفظ الإعداد')))));
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
            title: Text(tr('زيارات الملف الشخصي')),
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
              ? _MessageState(
                  message: tr(
                      'ميزة زيارات الملف الشخصي متوقفة.\nشغّلها من الزر بالأعلى لتعرف من زار ملفك ويرى الآخرون زياراتك لهم.'),
                  icon: Icons.visibility_off_outlined,
                )
              : StreamBuilder<List<ProfileVisit>>(
                  stream: SocialService.profileVisits(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return ErrorState(
                          error: snapshot.error,
                          title: tr('تعذر تحميل الزيارات'));
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
                                Text(tr('لا توجد زيارات بعد'),
                                    style: TextStyle(color: colors.textDim)),
                              ],
                            ),
                          ),
                        for (final visit in visits) _VisitTile(visit: visit),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            tr('قد تظهر هنا أسماء الأشخاص الذين شغّلوا سجل الزيارات لديهم وزاروا ملفك الشخصي خلال آخر 30 يوماً. بإمكانهم أيضاً رؤية متى تزور ملفهم الشخصي. يمكنك إيقاف هذا الإعداد في أي وقت.'),
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
          title: Text(user?.displayName ?? tr('مستخدم'),
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

/// «قائمة الحظر»: الحسابات التي حظرتُها مع زر إلغاء الحظر.
class BlockedUsersScreen extends StatelessWidget {
  const BlockedUsersScreen({super.key});

  Future<void> _unblock(BuildContext context, String uid, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('إلغاء الحظر؟')),
        content: Text(tr('سيتمكن هذا المستخدم من مراسلتك مجدداً إذا كنتما تتابعان بعضكما.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr('إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr('إلغاء الحظر')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await SocialService.setBlocked(uid, false);
      PostService.notifyStatsChanged();
      messenger.showSnackBar(SnackBar(content: Text(tr('تم إلغاء الحظر'))));
    } catch (error) {
      messenger.showSnackBar(SnackBar(
          content:
              Text(friendlyError(error, fallback: tr('تعذر تحديث الحظر')))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(title: Text(tr('قائمة الحظر'))),
      body: StreamBuilder<List<String>>(
        stream: SocialService.blockedUserIds(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(
                error: snapshot.error, title: tr('تعذر تحميل قائمة الحظر'));
          }
          if (!snapshot.hasData) return const AppLoading();
          final ids = snapshot.data!;
          if (ids.isEmpty) {
            return _MessageState(
              message: tr('لم تحظر أي حساب'),
              icon: Icons.block_rounded,
            );
          }
          return ListView(
            children: [
              for (final uid in ids)
                FutureBuilder<AppUser?>(
                  future: UserService.profileOf(uid),
                  builder: (context, userSnap) {
                    final user = userSnap.data;
                    final name = user?.displayName ?? tr('مستخدم');
                    return ListTile(
                      leading: UserAvatar(
                        uid: uid,
                        fallbackName: user?.username ?? '',
                        profile: user,
                        radius: 24,
                      ),
                      title: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: user == null
                          ? null
                          : Text('@${user.username}',
                              style: TextStyle(
                                  color: colors.textDim, fontSize: 12)),
                      trailing: OutlinedButton(
                        onPressed: () => _unblock(context, uid, name),
                        child: Text(tr('إلغاء الحظر')),
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
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
      messenger.showSnackBar(SnackBar(
          content:
              Text(friendlyError(error, fallback: tr('تعذر تنفيذ الإجراء')))));
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
          return Text(tr('تمت المعالجة'),
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
              child: Text(tr('قبول'), style: TextStyle(fontSize: 12)),
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
              child: Text(tr('رفض'), style: TextStyle(fontSize: 12)),
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


/// صورة داخل فقاعة المحادثة: أكبر وأوضح، تحافظ على النسبة (حتى ارتفاع معقول)،
/// وتعود للرابط الأصلي إن فشل الرابط المُحسَّن.
class _ChatImage extends StatelessWidget {
  final String? url;
  final Uint8List? bytes;
  final VoidCallback onTap;
  const _ChatImage({this.url, this.bytes, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final width =
        (MediaQuery.sizeOf(context).width * 0.62).clamp(200.0, 300.0).toDouble();
    Widget placeholder(double height) => SizedBox(
          width: width,
          height: height,
          child: const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
    Widget failed() => SizedBox(
          width: width,
          height: 120,
          child: Center(
            child: Text(tr('تعذر تحميل صورة'),
                style: TextStyle(color: colors.textDim)),
          ),
        );
    Widget network(String address, {required Widget Function() onError}) =>
        Image.network(
          address,
          width: width,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : placeholder(200),
          errorBuilder: (context, _, __) => onError(),
        );

    final Widget image;
    if (url != null) {
      final raw = url!;
      final optimized = PostService.optimizedImageUrl(raw, 800);
      image = network(
        optimized,
        onError: () => optimized == raw ? failed() : network(raw, onError: failed),
      );
    } else {
      image = Image.memory(bytes!, width: width, fit: BoxFit.cover);
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 380),
          child: image,
        ),
      ),
    );
  }
}

/// عرض الصورة بملء الشاشة (رابط): تكبير بالقرص، ومؤشر تحميل، وعودة للأصل عند الفشل.
class _NetworkImageViewer extends StatelessWidget {
  final String url;
  const _NetworkImageViewer({required this.url});

  @override
  Widget build(BuildContext context) {
    Widget loading(BuildContext context, Widget child, ImageChunkEvent? p) =>
        p == null
            ? child
            : const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
    Widget failed() => Center(
          child: Text(tr('تعذر تحميل صورة'),
              style: const TextStyle(color: Colors.white70)),
        );
    final optimized = PostService.optimizedImageUrl(url, 1600);
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          tooltip: tr('إغلاق'),
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SizedBox.expand(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Center(
            child: Image.network(
              optimized,
              fit: BoxFit.contain,
              loadingBuilder: loading,
              errorBuilder: (context, _, __) => optimized == url
                  ? failed()
                  : Image.network(
                      url,
                      fit: BoxFit.contain,
                      loadingBuilder: loading,
                      errorBuilder: (context, _, __) => failed(),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// شريط معاينة الصور المرفقة قبل الإرسال، مع زر إزالة لكل صورة.
class _PendingImagesStrip extends StatelessWidget {
  final List<Uint8List> images;
  final void Function(int index) onRemove;
  const _PendingImagesStrip({required this.images, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 102,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
        itemCount: images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) => Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(images[index],
                  width: 84, height: 88, fit: BoxFit.cover),
            ),
            PositionedDirectional(
              top: -6,
              end: -6,
              child: GestureDetector(
                onTap: () => onRemove(index),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                      color: Colors.black87, shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded,
                      size: 16, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
