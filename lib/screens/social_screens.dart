import 'dart:async';
import 'image_save_stub.dart' if (dart.library.html) 'image_save_web.dart';
import 'voice_stub.dart' if (dart.library.html) 'voice_web.dart';
import 'location_stub.dart' if (dart.library.html) 'location_web.dart';
import 'dart:ui' show FontFeature, ImageFilter;

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth_gate.dart';
import '../services/note_service.dart';
import '../services/post_service.dart';
import '../services/presence_service.dart';
import '../services/social_service.dart';
import '../services/user_service.dart';
import '../theme.dart';
import '../services/gif_service.dart';
import 'chat_extras.dart';
import 'common_widgets.dart';
import 'gif_picker.dart';
import 'note_widgets.dart';
import 'photo_tools.dart' show fitImageUnderLimit;
import 'post_widgets.dart' show PostDetailScreen, PostImage, timeAgo;
import 'profile_screen.dart' show FollowActionButton, openChatWith;
import 'sticker_sheet.dart';
import 'story_backgrounds.dart' show storyGradient;
import 'story_widgets.dart' show StoryViewed, StoryViewer;
import '../route_state.dart';

import '../l10n.dart';
import '../net_error.dart';

/// يُبَث عند تغيّر مسودات المحادثات (حفظ/مسح) لتحديث معاينتها في الصندوق.
final ValueNotifier<int> chatDraftsRevision = ValueNotifier<int>(0);

/// صندوق البريد (على طريقة تيكتوك): صف الأصدقاء، ثم المتابعون والإعجابات
/// والتعليقات، ثم المحادثات.
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final _search = TextEditingController();
  bool _searching = false;
  String _term = '';

  /// مسودات المحادثات: {معرّف المحادثة: نصّ المسودة} لمعاينتها في الصف.
  Map<String, String> _drafts = const {};

  /// أسماء أصحاب المحادثات (لتشغيل البحث الفوري بلا قراءات إضافية).
  final Map<String, AppUser> _names = {};
  final Set<String> _nameLoading = <String>{};

  @override
  void initState() {
    super.initState();
    StoryViewed.load().then((_) {
      if (mounted) setState(() {});
    });
    _loadDrafts();
    chatDraftsRevision.addListener(_loadDrafts);
  }

  @override
  void dispose() {
    chatDraftsRevision.removeListener(_loadDrafts);
    _search.dispose();
    super.dispose();
  }

  /// يقرأ كل المسودات المحفوظة محلياً مرة واحدة (بلا أي قراءة من السيرفر).
  Future<void> _loadDrafts() async {
    if (!isLoggedIn) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      final prefix = 'chat_draft_${SocialService.currentUid}_';
      final drafts = <String, String>{};
      for (final key in preferences.getKeys()) {
        if (!key.startsWith(prefix)) continue;
        final text = preferences.getString(key) ?? '';
        if (text.trim().isEmpty) continue;
        drafts[key.substring(prefix.length)] = text;
      }
      if (mounted) setState(() => _drafts = drafts);
    } catch (_) {}
  }

  /// يجلب أسماء أصحاب المحادثات مرة واحدة لتشغيل البحث الفوري.
  void _ensureNames(List<Conversation>? conversations) {
    if (conversations == null) return;
    final me = SocialService.currentUid;
    final missing = <String>[];
    for (final conversation in conversations) {
      if (conversation.isGroup) continue;
      final uid = conversation.otherParticipant(me);
      if (_names.containsKey(uid) || !_nameLoading.add(uid)) continue;
      missing.add(uid);
    }
    if (missing.isEmpty) return;
    Future.wait(missing.map(UserService.profileOf)).then((users) {
      if (!mounted) return;
      setState(() {
        for (final user in users) {
          if (user != null) _names[user.uid] = user;
        }
      });
    }).catchError((Object _) {});
  }

  void _closeSearch() {
    _search.clear();
    setState(() {
      _term = '';
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: (value) => setState(() => _term = value.trim()),
                decoration: InputDecoration(
                  hintText: tr('ابحث في المحادثات'),
                  border: InputBorder.none,
                ),
              )
            : Text(tr('صندوق البريد')),
        actions: _searching
            ? [
                IconButton(
                  tooltip: tr('إغلاق'),
                  onPressed: _closeSearch,
                  icon: const Icon(Icons.close_rounded),
                ),
              ]
            : [
                IconButton(
                  tooltip: tr('بحث'),
                  onPressed: () => setState(() => _searching = true),
                  icon: const Icon(Icons.search_rounded),
                ),
                IconButton(
                  tooltip: tr('مجموعة جديدة'),
                  onPressed: () => rootNavigatorOf(context).push(
                    MaterialPageRoute(builder: (_) => const _NewGroupScreen()),
                  ),
                  icon: const Icon(Icons.group_add_rounded),
                ),
                IconButton(
                  tooltip: tr('رسالة جديدة'),
                  onPressed: () => rootNavigatorOf(context).push(
                    MaterialPageRoute(builder: (_) => const _FriendsScreen()),
                  ),
                  icon: const Icon(Icons.edit_rounded),
                ),
              ],
      ),
      body: StreamBuilder<List<StoryGroup>>(
        stream: PostService.storyGroups(),
        builder: (context, storySnapshot) {
          final stories = storySnapshot.data ?? const <StoryGroup>[];
          return StreamBuilder<List<Conversation>>(
            stream: SocialService.conversations(),
            builder: (context, snapshot) {
              _ensureNames(snapshot.data);
              final searching = _term.isNotEmpty;
              return ListView(
                padding: const EdgeInsets.only(bottom: 80),
                children: searching
                    ? _searchResults(context, snapshot, stories)
                    : [
                        _FollowingRail(
                          stories: stories,
                          error: storySnapshot.error,
                        ),
                        const _NotificationsSummaryTile(),
                        ...(_requestRows(context, snapshot) ??
                            const <Widget>[]),
                        ...(_archivedRows(context, snapshot, stories) ??
                            const <Widget>[]),
                        const _SavedMessagesRow(),
                        Padding(
                          padding:
                              EdgeInsetsDirectional.fromSTEB(16, 14, 16, 6),
                          child: Text(tr('المحادثات'),
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                        ),
                        ..._conversationItems(context, snapshot, stories),
                      ],
              );
            },
          );
        },
      ),
    );
  }

  /// نتائج البحث الفوري: يفلتر المحادثات محلياً + مدخل بحث معمّق.
  List<Widget> _searchResults(
    BuildContext context,
    AsyncSnapshot<List<Conversation>> snapshot,
    List<StoryGroup> stories,
  ) {
    final colors = context.appColors;
    final data = snapshot.data;
    if (data == null) {
      return const [
        Padding(padding: EdgeInsets.all(40), child: AppLoading()),
      ];
    }
    final me = SocialService.currentUid;
    final needle = _term.toLowerCase().replaceAll('@', '');
    final matches = data.where((conversation) {
      if (!conversation.visibleFor(me)) return false;
      if (conversation.isGroup) {
        return '${conversation.groupTitle} ${conversation.lastMessage}'
            .toLowerCase()
            .contains(needle);
      }
      final user = _names[conversation.otherParticipant(me)];
      final haystack = '${user?.name ?? ''} ${user?.username ?? ''} '
              '${conversation.lastMessage}'
          .toLowerCase();
      return haystack.contains(needle);
    }).toList();
    return [
      ListTile(
        leading: Icon(Icons.search_rounded, color: colors.text),
        title: Text(trf('البحث في الرسائل والأشخاص عن «{0}»', [_term])),
        onTap: () => rootNavigatorOf(context).push(
          MaterialPageRoute(
            builder: (_) => _ChatSearchScreen(initialQuery: _term),
          ),
        ),
      ),
      Divider(height: 1, color: colors.surfaceHigh),
      if (matches.isEmpty)
        SizedBox(
          height: 240,
          child: _MessageState(
            message: trf('لا نتائج لـ «{0}»', [_term]),
            icon: Icons.search_off_rounded,
          ),
        )
      else
        for (final conversation in matches) ...[
          _conversationTile(context, conversation, stories),
          Divider(height: 1, indent: 76, color: colors.surfaceHigh),
        ],
    ];
  }

  /// صف «طلبات الرسائل» أعلى المحادثات (كإنستغرام)، يظهر عند وجود طلب.
  List<Widget>? _requestRows(
    BuildContext context,
    AsyncSnapshot<List<Conversation>> snapshot,
  ) {
    final data = snapshot.data;
    if (data == null) return null;
    final me = SocialService.currentUid;
    final requests = data
        .where((conversation) =>
            conversation.visibleFor(me) && conversation.isRequestFor(me))
        .toList();
    if (requests.isEmpty) return null;
    final colors = context.appColors;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return [
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(Icons.mark_email_unread_outlined, color: colors.text),
        title: Text(tr('طلبات الرسائل'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${requests.length}', style: TextStyle(color: colors.textDim)),
            const SizedBox(width: 6),
            Icon(
              rtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
              color: colors.textDim,
            ),
          ],
        ),
        onTap: () => rootNavigatorOf(context).push(
          MaterialPageRoute(builder: (_) => const _MessageRequestsScreen()),
        ),
      ),
      Divider(height: 1, indent: 76, color: colors.surfaceHigh),
    ];
  }

  /// صف «المؤرشفة» أعلى المحادثات (كإنستغرام)، يظهر فقط عند وجود مؤرشفة.
  List<Widget>? _archivedRows(
    BuildContext context,
    AsyncSnapshot<List<Conversation>> snapshot,
    List<StoryGroup> stories,
  ) {
    final data = snapshot.data;
    if (data == null) return null;
    final archived = data
        .where((conversation) =>
            conversation.visibleFor(SocialService.currentUid) &&
            conversation.archivedFor(SocialService.currentUid))
        .toList();
    if (archived.isEmpty) return null;
    final colors = context.appColors;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return [
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(Icons.archive_outlined, color: colors.text),
        title: Text(tr('المؤرشفة'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${archived.length}', style: TextStyle(color: colors.textDim)),
            const SizedBox(width: 6),
            Icon(
              rtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
              color: colors.textDim,
            ),
          ],
        ),
        onTap: () => rootNavigatorOf(context).push(
          MaterialPageRoute(
            builder: (_) => _ArchivedChatsScreen(
              tileBuilder: (tileContext, conversation) =>
                  _conversationTile(tileContext, conversation, stories),
            ),
          ),
        ),
      ),
      Divider(height: 1, indent: 76, color: colors.surfaceHigh),
    ];
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
    // والمؤرشفة تُخفى من الصندوق (لها صف مستقل أعلى القائمة).
    final conversations = snapshot.data!
        .where((c) =>
            c.visibleFor(SocialService.currentUid) &&
            !c.archivedFor(SocialService.currentUid) &&
            !c.isRequestFor(SocialService.currentUid))
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
    final me = SocialService.currentUid;
    final isGroup = conversation.isGroup;
    final otherUid = isGroup ? '' : conversation.otherParticipant(me);
    final unread = conversation.unreadFor(me);
    final pinned = conversation.pinnedFor(me);
    final muted = conversation.mutedFor(me);
    if (isGroup) {
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: _PinBadge(
          pinned: pinned,
          child: _GroupAvatar(conversation: conversation, radius: 26),
        ),
        title: Text(
          conversation.groupTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: _drafts[conversation.id] != null
            ? _DraftLine(text: _drafts[conversation.id]!)
            : _LastMessagePreview(conversation: conversation, unread: unread),
        trailing:
            _conversationTrailing(context, conversation, unread, pinned, muted),
        onLongPress: () => _showChatMenu(context, conversation),
        onTap: () => rootNavigatorOf(context).push(
          appRoute(
            'chat',
            {'cid': conversation.id, 'uid': ''},
            (_) => ChatScreen(
              conversationId: conversation.id,
              otherUid: '',
              isGroup: true,
            ),
          ),
        ),
      );
    }
    return FutureBuilder<AppUser?>(
      future: UserService.profileOf(otherUid),
      builder: (context, userSnapshot) {
        final user = userSnapshot.data;
        final storyIndex = stories.indexWhere((group) => group.uid == otherUid);
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: _PinBadge(
            pinned: pinned,
            child: UserAvatar(
              uid: otherUid,
              fallbackName: user?.username ?? '',
              profile: user,
              radius: 26,
              showOnline: true,
              hasStory: storyIndex >= 0,
              storySeen:
                  storyIndex >= 0 && StoryViewed.allSeen(stories[storyIndex]),
            ),
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
              // المسودة أولاً (كإنستغرام)، ثم «نشط الآن»، ثم آخر رسالة.
              final draft = _drafts[conversation.id];
              if (draft != null) return _DraftLine(text: draft);
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
          trailing: _conversationTrailing(
              context, conversation, unread, pinned, muted),
          // ضغطة مطولة: قائمة (تثبيت / حذف المحادثة لديّ).
          onLongPress: () => _showChatMenu(context, conversation),
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

  /// عمود حالة الصف: الوقت، ثم أيقونة الكتم، ثم شارة «غير مقروء» (كإنستغرام:
  /// المحادثة المكتومة تُظهر رمز الكتم بدل رقم غير المقروء).
  Widget _conversationTrailing(
    BuildContext context,
    Conversation conversation,
    bool unread,
    bool pinned,
    bool muted,
  ) {
    final colors = context.appColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (conversation.updatedAt.millisecondsSinceEpoch != 0)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (muted)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 4),
                  child: Icon(Icons.notifications_off_outlined,
                      size: 13, color: colors.textDim),
                ),
              Text(
                timeAgo(conversation.updatedAt),
                style: TextStyle(
                    color: unread ? colors.text : colors.textDim, fontSize: 11),
              ),
            ],
          ),
        if (unread && !muted)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _UnreadBadge(conversation: conversation),
          ),
      ],
    );
  }
}

/// شارة التثبيت على الصورة الرمزية (كإنستغرام).
class _PinBadge extends StatelessWidget {
  final Widget child;
  final bool pinned;
  const _PinBadge({required this.child, required this.pinned});

  @override
  Widget build(BuildContext context) {
    if (!pinned) return child;
    final colors = context.appColors;
    return Stack(
      children: [
        child,
        PositionedDirectional(
          start: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: colors.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.push_pin_rounded, size: 11, color: colors.text),
          ),
        ),
      ],
    );
  }
}

/// شارة «غير المقروء» في صف المحادثة: رقم (كإنستغرام) وإلا نقطة.
class _UnreadBadge extends StatefulWidget {
  final Conversation conversation;
  const _UnreadBadge({required this.conversation});

  @override
  State<_UnreadBadge> createState() => _UnreadBadgeState();
}

class _UnreadBadgeState extends State<_UnreadBadge> {
  /// كاش العدّ: نفس المحادثة بنفس آخر رسالة = نفس النتيجة (بلا قراءة جديدة).
  static final Map<String, Future<int>> _cache = {};

  Future<int> _count() {
    final conversation = widget.conversation;
    final me = SocialService.currentUid;
    final since =
        conversation.readAt[me] ?? DateTime.fromMillisecondsSinceEpoch(0);
    // في الدردشة الفردية نعدّ رسائل الطرف الآخر فقط.
    final fromUid =
        conversation.isGroup ? null : conversation.otherParticipant(me);
    final key =
        '${conversation.id}|${since.millisecondsSinceEpoch}|${conversation.lastMessageId}';
    if (_cache.length > 300) _cache.clear();
    return _cache.putIfAbsent(
      key,
      () => SocialService.unreadMessageCount(
        conversation.id,
        since,
        fromUid: fromUid,
      ).catchError((Object _) => 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    // نفس شارة الإشعارات: دائرة حمراء (لا مستطيل أفقي).
    const color = AppColors.notificationRed;
    return FutureBuilder<int>(
      future: _count(),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        if (count <= 0) {
          return Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(color: color, shape: BoxShape.circle),
          );
        }
        return Container(
          width: 20,
          height: 20,
          decoration: const BoxDecoration(color: color, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// معاينة مسودة محفوظة في صف المحادثة («مسودة: …»).
class _DraftLine extends StatelessWidget {
  final String text;
  const _DraftLine({required this.text});

  @override
  Widget build(BuildContext context) => Text(
        trf('مسودة: {0}', [text]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
            color: AppColors.likeRed, fontWeight: FontWeight.w600),
      );
}

/// صورة مجموعة: صورتُها إن وُجدت، وإلا كولاج صور الأعضاء (كإنستغرام).
class _GroupAvatar extends StatelessWidget {
  final Conversation conversation;
  final double radius;
  const _GroupAvatar({required this.conversation, required this.radius});

  @override
  Widget build(BuildContext context) => _GroupPhoto(
        participants: conversation.participants,
        photoUrl: conversation.groupPhoto,
        size: radius * 2,
      );
}

/// صورة المجموعة الموحّدة: صورة مخصّصة أو شبكة صور الأعضاء (حتى 4).
class _GroupPhoto extends StatelessWidget {
  final List<String> participants;
  final String photoUrl;
  final double size;
  final VoidCallback? onTap;

  const _GroupPhoto({
    required this.participants,
    required this.photoUrl,
    required this.size,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final photo = photoUrl.trim();
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: ClipOval(
          child: photo.isEmpty
              ? _collage(context)
              : Image.network(
                  photo,
                  fit: BoxFit.cover,
                  width: size,
                  height: size,
                  errorBuilder: (_, __, ___) => _collage(context),
                ),
        ),
      ),
    );
  }

  /// كولاج صور الأعضاء: مربّع واحد، أو عمودان (كإنستغرام).
  Widget _collage(BuildContext context) {
    final colors = context.appColors;
    final uids = participants.take(4).toList();
    if (uids.isEmpty) {
      return Container(
        color: colors.surfaceHigh,
        child:
            Icon(Icons.groups_rounded, size: size * 0.5, color: colors.textDim),
      );
    }
    return GridView.count(
      crossAxisCount: uids.length == 1 ? 1 : 2,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      children: [for (final uid in uids) UserAvatar(uid: uid, radius: size)],
    );
  }
}

/// سطر «شوهد بواسطة ...» أسفل رسالة في مجموعة (كإنستغرام).
class _SeenByLine extends StatelessWidget {
  final List<String> readers;
  final int total;

  const _SeenByLine({required this.readers, required this.total});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return FutureBuilder<List<String>>(
      future: Future.wait(readers.map((uid) async =>
          (await UserService.profileOf(uid))?.displayName ?? '')),
      builder: (context, snapshot) {
        final names = (snapshot.data ?? const <String>[])
            .where((name) => name.trim().isNotEmpty)
            .toList();
        if (names.isEmpty) return const SizedBox.shrink();
        // إن شاهدها الجميع: «شوهد بواسطة الجميع» (كإنستغرام).
        final text = total > 0 && readers.length >= total
            ? tr('شوهد بواسطة الجميع')
            : trf('شوهد بواسطة {0}', [names.join('، ')]);
        return Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colors.textDim, fontSize: 11),
        );
      },
    );
  }
}

/// اسم مرسل رسالة في مجموعة (بخط صغير ملوّن فوق الفقاعة).
class _SenderName extends StatelessWidget {
  final String uid;

  const _SenderName({required this.uid});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppUser?>(
      // من الذاكرة المؤقتة: لا قراءة إضافية من Firestore.
      future: UserService.profileOf(uid),
      builder: (context, snapshot) {
        final name = snapshot.data?.displayName ?? '';
        if (name.isEmpty) return const SizedBox.shrink();
        return Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.brandOrange,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        );
      },
    );
  }
}

/// شاشة المحادثات المؤرشفة (تُفتح من صف «المؤرشفة» أعلى الصندوق).
class _ArchivedChatsScreen extends StatelessWidget {
  /// يبني صف المحادثة نفسه المستعمل في الصندوق (بلا تكرار للتصميم).
  final Widget Function(BuildContext, Conversation) tileBuilder;

  const _ArchivedChatsScreen({required this.tileBuilder});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(title: Text(tr('المؤرشفة'))),
      body: StreamBuilder<List<Conversation>>(
        stream: SocialService.conversations(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(
                error: snapshot.error, title: tr('تعذر تحميل الرسائل'));
          }
          if (!snapshot.hasData) return const AppLoading();
          final items = snapshot.data!
              .where((conversation) =>
                  conversation.visibleFor(SocialService.currentUid) &&
                  conversation.archivedFor(SocialService.currentUid))
              .toList();
          if (items.isEmpty) {
            return _MessageState(
              message: tr('لا توجد محادثات مؤرشفة'),
              icon: Icons.archive_outlined,
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final conversation = items[index];
              return Column(
                key: ValueKey(conversation.id),
                mainAxisSize: MainAxisSize.min,
                children: [
                  tileBuilder(context, conversation),
                  Divider(height: 1, indent: 76, color: colors.surfaceHigh),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// صف «المحفوظات» في الصندوق: يظهر فقط عند وجود رسائل محفوظة.
class _SavedMessagesRow extends StatelessWidget {
  const _SavedMessagesRow();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return StreamBuilder<Set<String>>(
      stream: SocialService.savedMessageIds(),
      builder: (context, snapshot) {
        final count = snapshot.data?.length ?? 0;
        if (count == 0) return const SizedBox.shrink();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Icon(Icons.bookmark_border_rounded, color: colors.text),
              title: Text(tr('المحفوظات'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$count', style: TextStyle(color: colors.textDim)),
                  const SizedBox(width: 6),
                  Icon(
                    rtl
                        ? Icons.chevron_left_rounded
                        : Icons.chevron_right_rounded,
                    color: colors.textDim,
                  ),
                ],
              ),
              onTap: () => rootNavigatorOf(context).push(
                MaterialPageRoute(builder: (_) => const _SavedMessagesScreen()),
              ),
            ),
            Divider(height: 1, indent: 76, color: colors.surfaceHigh),
          ],
        );
      },
    );
  }
}

/// شاشة المحفوظات: رسائل حفظتها، والنقر يفتح المحادثة التي جاءت منها.
class _SavedMessagesScreen extends StatelessWidget {
  const _SavedMessagesScreen();

  IconData _iconFor(String kind) {
    switch (kind) {
      case 'image':
        return Icons.image_outlined;
      case 'share':
        return Icons.link_rounded;
      case 'location':
        return Icons.place_outlined;
      case 'sticker':
        return Icons.emoji_emotions_outlined;
      default:
        return Icons.chat_bubble_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(title: Text(tr('المحفوظات'))),
      body: StreamBuilder<List<SavedMessage>>(
        stream: SocialService.savedMessages(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(
                error: snapshot.error, title: tr('تعذر تحميل المحفوظات'));
          }
          if (!snapshot.hasData) return const AppLoading();
          final items = snapshot.data!;
          if (items.isEmpty) {
            return _MessageState(
              message:
                  tr('لا توجد رسائل محفوظة\nاضغط مطولاً على رسالة واختر «حفظ»'),
              icon: Icons.bookmark_border_rounded,
            );
          }
          return StreamBuilder<List<Conversation>>(
            stream: SocialService.conversations(),
            builder: (context, chatSnapshot) {
              final me = SocialService.currentUid;
              final chats = <String, Conversation>{
                for (final conversation
                    in chatSnapshot.data ?? const <Conversation>[])
                  conversation.id: conversation,
              };
              return ListView.separated(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, indent: 72, color: colors.surfaceHigh),
                itemBuilder: (context, index) {
                  final saved = items[index];
                  final chat = chats[saved.conversationId];
                  final otherUid =
                      chat == null ? '' : chat.otherParticipant(me);
                  return ListTile(
                    leading:
                        Icon(_iconFor(saved.message.kind), color: colors.text),
                    title: Text(
                      saved.message.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      timeAgo(saved.savedAt),
                      style: TextStyle(color: colors.textDim, fontSize: 11),
                    ),
                    onTap: otherUid.isEmpty
                        ? null
                        : () => rootNavigatorOf(context).push(
                              appRoute(
                                'chat',
                                {
                                  'cid': saved.conversationId,
                                  'uid': otherUid,
                                },
                                (_) => ChatScreen(
                                  conversationId: saved.conversationId,
                                  otherUid: otherUid,
                                ),
                              ),
                            ),
                    trailing: IconButton(
                      tooltip: tr('إزالة من المحفوظات'),
                      icon: const Icon(Icons.bookmark_remove_outlined),
                      onPressed: () => _removeSaved(context, saved.message.id),
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

/// إزالة رسالة من المحفوظات.
Future<void> _removeSaved(BuildContext context, String messageId) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await SocialService.unsaveMessage(messageId);
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(
          content:
              Text(friendlyError(error, fallback: tr('تعذر إزالة الرسالة')))),
    );
  }
}

/// طلبات الرسائل (كإنستغرام): محادثات بدأها آخرون ولم أردّ عليها بعد،
/// تُقبل أو تُحذف قبل أن تظهر في الصندوق.
class _MessageRequestsScreen extends StatefulWidget {
  const _MessageRequestsScreen();

  @override
  State<_MessageRequestsScreen> createState() => _MessageRequestsScreenState();
}

class _MessageRequestsScreenState extends State<_MessageRequestsScreen> {
  String? _busyId;

  Future<void> _run(
      String id, Future<void> Function() action, String failure) async {
    if (_busyId != null) return;
    setState(() => _busyId = id);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(error, fallback: failure))),
        );
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _accept(Conversation conversation) {
    final otherUid = conversation.otherParticipant(SocialService.currentUid);
    return _run(
      conversation.id,
      () async {
        await SocialService.acceptChatRequest(conversation.id);
        if (!mounted) return;
        await Navigator.of(context).push(appRoute(
          'chat',
          {'cid': conversation.id, 'uid': otherUid},
          (_) =>
              ChatScreen(conversationId: conversation.id, otherUid: otherUid),
        ));
      },
      tr('تعذر قبول الطلب'),
    );
  }

  Future<void> _delete(Conversation conversation) => _run(
        conversation.id,
        () => SocialService.clearChatForMe(conversation.id),
        tr('تعذر حذف الطلب'),
      );

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(title: Text(tr('طلبات الرسائل'))),
      body: StreamBuilder<List<Conversation>>(
        stream: SocialService.conversations(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(
                error: snapshot.error, title: tr('تعذر تحميل الطلبات'));
          }
          if (!snapshot.hasData) return const AppLoading();
          final me = SocialService.currentUid;
          final requests = snapshot.data!
              .where((c) => c.visibleFor(me) && c.isRequestFor(me))
              .toList();
          if (requests.isEmpty) {
            return _MessageState(
              message: tr('لا توجد طلبات رسائل'),
              icon: Icons.mark_email_read_outlined,
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 8),
                child: Text(
                  tr('طلبات الرسائل من أشخاص لا تتابعهم. لن يعرفوا أنك قرأت الرسالة حتى تقبلها.'),
                  style: TextStyle(color: colors.textDim, fontSize: 12),
                ),
              ),
              for (final conversation in requests)
                _requestTile(context, conversation, me),
            ],
          );
        },
      ),
    );
  }

  Widget _requestTile(
      BuildContext context, Conversation conversation, String me) {
    final colors = context.appColors;
    final otherUid = conversation.otherParticipant(me);
    final busy = _busyId == conversation.id;
    return FutureBuilder<AppUser?>(
      future: UserService.profileOf(otherUid),
      builder: (context, userSnapshot) {
        final user = userSnapshot.data;
        return Column(
          key: ValueKey(conversation.id),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: UserAvatar(
                uid: otherUid,
                fallbackName: user?.username ?? '',
                profile: user,
                radius: 24,
                showOnline: true,
              ),
              title: Text(user?.displayName ?? tr('مستخدم'),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('@${user?.username ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textDim)),
              onTap: busy ? null : () => _accept(conversation),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(78, 0, 16, 8),
              child: Text(
                conversation.lastMessage,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.text, fontSize: 13),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(74, 0, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: busy ? null : () => _accept(conversation),
                      child: Text(tr('قبول')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: busy ? null : () => _delete(conversation),
                      child: Text(tr('حذف')),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, indent: 76, color: colors.surfaceHigh),
          ],
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

/// قائمة الضغطة المطولة على محادثة: تثبيت أو إلغاء التثبيت، أو حذفها لديّ.
Future<void> _showChatMenu(
    BuildContext context, Conversation conversation) async {
  final pinned = conversation.pinnedFor(SocialService.currentUid);
  final muted = conversation.mutedFor(SocialService.currentUid);
  final archived = conversation.archivedFor(SocialService.currentUid);
  final markedUnread = SocialService.isManuallyUnread(conversation.id);
  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading:
                Icon(pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded),
            title: Text(pinned ? tr('إلغاء التثبيت') : tr('تثبيت المحادثة')),
            onTap: () => Navigator.pop(sheetContext, 'pin'),
          ),
          ListTile(
            leading: Icon(muted
                ? Icons.notifications_active_outlined
                : Icons.notifications_off_outlined),
            title: Text(muted ? tr('إلغاء الكتم') : tr('كتم المحادثة')),
            onTap: () => Navigator.pop(sheetContext, 'mute'),
          ),
          ListTile(
            leading: Icon(
                archived ? Icons.unarchive_outlined : Icons.archive_outlined),
            title: Text(archived ? tr('إلغاء الأرشفة') : tr('أرشفة المحادثة')),
            subtitle: archived
                ? null
                : Text(tr('تختفي من الصندوق وتعود عند وصول رسالة')),
            onTap: () => Navigator.pop(sheetContext, 'archive'),
          ),
          ListTile(
            leading: Icon(markedUnread
                ? Icons.mark_chat_read_outlined
                : Icons.mark_chat_unread_outlined),
            title: Text(
                markedUnread ? tr('تعليم كمقروء') : tr('تعليم كغير مقروء')),
            onTap: () => Navigator.pop(sheetContext, 'unread'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded),
            title: Text(tr('حذف المحادثة')),
            onTap: () => Navigator.pop(sheetContext, 'delete'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted || action == null) return;
  if (action == 'delete') {
    await _confirmAndClearChat(context, conversation.id);
    return;
  }
  if (action == 'unread') {
    SocialService.setChatUnread(conversation.id, !markedUnread);
    return;
  }
  try {
    if (action == 'mute') {
      if (muted) {
        await SocialService.setChatMuted(conversation.id, muted: false);
        if (context.mounted) {
          _chatMenuToast(context, tr('تم إلغاء كتم المحادثة'));
        }
      } else {
        final choice = await _pickMuteDuration(context);
        if (choice == null || !context.mounted) return;
        final now = DateTime.now();
        final until = choice == '1h'
            ? now.add(const Duration(hours: 1))
            : choice == '8h'
                ? now.add(const Duration(hours: 8))
                : choice == '24h'
                    ? now.add(const Duration(hours: 24))
                    : null;
        await SocialService.setChatMuted(conversation.id,
            muted: true, until: until);
        if (context.mounted) {
          _chatMenuToast(
            context,
            choice == 'forever'
                ? tr('تم كتم المحادثة')
                : tr('تم كتم المحادثة مؤقتاً'),
            onUndo: () =>
                SocialService.setChatMuted(conversation.id, muted: false),
          );
        }
      }
    } else if (action == 'archive') {
      await SocialService.setChatArchived(conversation.id, !archived);
    } else {
      await SocialService.setChatPinned(conversation.id, !pinned);
      if (context.mounted) {
        _chatMenuToast(
          context,
          pinned ? tr('تم إلغاء تثبيت المحادثة') : tr('تم تثبيت المحادثة'),
        );
      }
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                friendlyError(error, fallback: tr('تعذر تحديث المحادثة')))),
      );
    }
  }
}

/// رسالة قصيرة أسفل الشاشة بعد إجراء على المحادثة (كإنستغرام)، مع تراجع اختياري.
void _chatMenuToast(BuildContext context, String message,
    {VoidCallback? onUndo}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 3),
      action: onUndo == null
          ? null
          : SnackBarAction(label: tr('تراجع'), onPressed: onUndo),
    ),
  );
}

/// اختيار مدة الكتم (كإنستغرام). تُعيد '1h' / '8h' / '24h' / 'forever' أو null.
Future<String?> _pickMuteDuration(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.notifications_off_outlined),
            title: Text(tr('كتم المحادثة')),
            subtitle: Text(tr('لن تصلك إشعارات من هذه المحادثة')),
          ),
          const Divider(height: 1),
          ListTile(
            title: Text(tr('كتم لساعة واحدة')),
            onTap: () => Navigator.pop(sheetContext, '1h'),
          ),
          ListTile(
            title: Text(tr('كتم لـ 8 ساعات')),
            onTap: () => Navigator.pop(sheetContext, '8h'),
          ),
          ListTile(
            title: Text(tr('كتم لـ 24 ساعة')),
            onTap: () => Navigator.pop(sheetContext, '24h'),
          ),
          ListTile(
            title: Text(tr('كتم حتى إعادة التشغيل')),
            onTap: () => Navigator.pop(sheetContext, 'forever'),
          ),
        ],
      ),
    ),
  );
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
  late final Stream<UserNote?> _myNote = NoteService.myNote();
  late final Stream<Map<String, UserNote>> _friendNotes =
      NoteService.friendsNotes();
  final Map<String, Future<AppUser?>> _profiles = {};
  Timer? _expiryTick;

  @override
  void initState() {
    super.initState();
    // الملاحظة تنتهي بعد 24 ساعة: نعيد الرسم كل دقيقة لتختفي وهي مفتوحة.
    _expiryTick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _expiryTick?.cancel();
    super.dispose();
  }

  /// ملاحظتي: فارغة → كتابة ملاحظة، موجودة → خيارات (جديدة / حذف).
  void _openMyNote(UserNote? note) {
    if (note == null) {
      showNoteComposeSheet(context);
    } else {
      showMyNoteOptions(context, note);
    }
  }

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
      height: 150,
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

          return StreamBuilder<UserNote?>(
            stream: _myNote,
            builder: (context, mySnapshot) =>
                StreamBuilder<Map<String, UserNote>>(
              stream: _friendNotes,
              builder: (context, notesSnapshot) {
                final myNote = mySnapshot.data;
                // أخطاء الملاحظات لا تكسر الصف: نعرضه بلا ملاحظات.
                final notes = <String, UserNote>{
                  for (final entry
                      in (notesSnapshot.data ?? const <String, UserNote>{})
                          .entries)
                    if (entry.value.isActive) entry.key: entry.value,
                };
                // أصحاب الملاحظات أولاً (الأحدث أولاً) ثم بقية من أتابعهم.
                final withNotes = following.where(notes.containsKey).toList()
                  ..sort((a, b) =>
                      notes[b]!.createdAt.compareTo(notes[a]!.createdAt));
                final ordered = [
                  ...withNotes,
                  ...following.where((uid) => !notes.containsKey(uid)),
                ];
                final myUid = SocialService.currentUid;

                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 4),
                  itemCount: 1 + (ordered.isEmpty ? 1 : ordered.length),
                  separatorBuilder: (_, __) => const SizedBox(width: 4),
                  itemBuilder: (context, index) {
                    // أول عنصر: ملاحظتي (مثل إنستغرام).
                    if (index == 0) {
                      return NoteRailItem(
                        uid: myUid,
                        profile: UserService.me,
                        note: myNote,
                        isMine: true,
                        hasStory: false,
                        storySeen: false,
                        onAvatarTap: () => _openMyNote(myNote),
                        onNoteTap: () => _openMyNote(myNote),
                      );
                    }
                    if (ordered.isEmpty) {
                      return SizedBox(
                        width: 200,
                        child: Padding(
                          padding: const EdgeInsets.only(
                              top: NoteRailItem.bubbleZone),
                          child: Center(
                            child: Text(
                              widget.error == null
                                  ? tr('تابع أصدقاءك لتظهر حساباتهم هنا')
                                  : friendlyError(widget.error,
                                      fallback: tr('تعذر تحميل القصص')),
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(color: context.appColors.textDim),
                            ),
                          ),
                        ),
                      );
                    }
                    final uid = ordered[index - 1];
                    final storyIndex =
                        widget.stories.indexWhere((group) => group.uid == uid);
                    return FutureBuilder<AppUser?>(
                      future: _profile(uid),
                      builder: (context, userSnapshot) {
                        final user = userSnapshot.data;
                        if (userSnapshot.hasError) {
                          return SizedBox(
                            width: 76,
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
                            width: 76,
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
                        final note = notes[uid];
                        return NoteRailItem(
                          uid: uid,
                          profile: user,
                          note: note,
                          isMine: false,
                          hasStory: storyIndex >= 0,
                          storySeen: storyIndex >= 0 &&
                              StoryViewed.allSeen(widget.stories[storyIndex]),
                          onAvatarTap: () => _openUser(user),
                          // الضغط على الفقاعة: ردّ على الملاحظة (مثل إنستغرام).
                          onNoteTap: note == null
                              ? () => _openUser(user)
                              : () => showNoteReplySheet(
                                    context,
                                    note: note,
                                    owner: user,
                                  ),
                        );
                      },
                    );
                  },
                );
              },
            ),
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

/// إنشاء مجموعة جديدة: اسم + اختيار عضوين على الأقل من الأصدقاء المتبادلين.
class _NewGroupScreen extends StatefulWidget {
  const _NewGroupScreen();

  @override
  State<_NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends State<_NewGroupScreen> {
  final _name = TextEditingController();
  late Future<List<AppUser>> _friends = _loadFriends();
  final Set<String> _selected = <String>{};
  bool _creating = false;

  Future<List<AppUser>> _loadFriends() async {
    final ids = await SocialService.mutualFriendIds();
    final users = await Future.wait(ids.map(UserService.profileOf));
    return users.whereType<AppUser>().toList();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _canCreate =>
      !_creating && _name.text.trim().isNotEmpty && _selected.length >= 2;

  Future<void> _create() async {
    if (!_canCreate) return;
    setState(() => _creating = true);
    try {
      final id = await SocialService.createGroup(
        name: _name.text,
        memberUids: _selected.toList(),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        appRoute('chat', {'cid': id, 'uid': ''},
            (_) => ChatScreen(conversationId: id, otherUid: '', isGroup: true)),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                friendlyError(error, fallback: tr('تعذر إنشاء المجموعة')))));
        setState(() => _creating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: Text(tr('مجموعة جديدة')),
        actions: [
          TextButton(
            onPressed: _canCreate ? _create : null,
            child: _creating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(tr('إنشاء')),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _name,
              maxLength: SocialService.groupNameMax,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: tr('اسم المجموعة'),
                counterText: '',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: Row(
              children: [
                Text(tr('الأعضاء'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Text('${_selected.length}',
                    style: TextStyle(color: colors.textDim)),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<AppUser>>(
              future: _friends,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return ErrorState(
                      error: snapshot.error,
                      title: tr('تعذر تحميل قائمة الأصدقاء'),
                      onRetry: () => setState(() => _friends = _loadFriends()));
                }
                if (!snapshot.hasData) return const AppLoading();
                final friends = snapshot.data!;
                if (friends.isEmpty) {
                  return _MessageState(
                    message:
                        tr('تحتاج صديقين متبادلين على الأقل لإنشاء مجموعة'),
                    icon: Icons.people_outline_rounded,
                  );
                }
                return ListView.builder(
                  itemCount: friends.length,
                  itemBuilder: (context, index) {
                    final friend = friends[index];
                    final checked = _selected.contains(friend.uid);
                    return CheckboxListTile(
                      value: checked,
                      onChanged: _creating
                          ? null
                          : (value) => setState(() {
                                if (value == true) {
                                  _selected.add(friend.uid);
                                } else {
                                  _selected.remove(friend.uid);
                                }
                              }),
                      controlAffinity: ListTileControlAffinity.trailing,
                      secondary: UserAvatar(
                        uid: friend.uid,
                        fallbackName: friend.username,
                        radius: 22,
                      ),
                      title: Text(friend.displayName,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('@${friend.username}',
                          style: TextStyle(color: colors.textDim)),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// بحث عام: محادثاتي (بالاسم أو نص آخر رسالة) وحسابات المستخدمين معاً.
class _ChatSearchScreen extends StatefulWidget {
  /// نص ابتدائي (يأتي من البحث الفوري في الصندوق).
  final String initialQuery;

  const _ChatSearchScreen({this.initialQuery = ''});

  @override
  State<_ChatSearchScreen> createState() => _ChatSearchScreenState();
}

class _ChatMatch {
  final Conversation conversation;
  final AppUser user;
  const _ChatMatch(this.conversation, this.user);
}

class _SearchOutcome {
  final List<_ChatMatch> chats;
  final List<AppUser> users;
  const _SearchOutcome(this.chats, this.users);
}

class _ChatSearchScreenState extends State<_ChatSearchScreen> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  Future<_SearchOutcome>? _results;
  String _term = '';
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
    final initial = widget.initialQuery.trim();
    if (initial.isNotEmpty) {
      _query.text = initial;
      _term = initial;
      _results = _search(initial);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    final term = value.trim();
    _debounce?.cancel();
    if (term.isEmpty) {
      setState(() {
        _term = '';
        _results = null;
      });
      return;
    }
    setState(() => _term = term);
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _results = _search(term));
    });
  }

  Future<_SearchOutcome> _search(String term) async {
    final me = SocialService.currentUid;
    final needle = term.toLowerCase().replaceAll('@', '');
    final conversations = (await SocialService.conversations().first)
        .where((c) => c.visibleFor(me) && !c.isGroup)
        .toList();
    final profiles = await Future.wait(conversations
        .map((c) => UserService.profileOf(c.otherParticipant(me))));
    final chats = <_ChatMatch>[];
    for (var i = 0; i < conversations.length; i++) {
      final user = profiles[i];
      if (user == null) continue;
      final haystack = '${user.displayName} ${user.username} '
              '${conversations[i].lastMessage}'
          .toLowerCase();
      if (haystack.contains(needle)) {
        chats.add(_ChatMatch(conversations[i], user));
      }
    }
    final users = await UserService.search(term);
    return _SearchOutcome(chats, users);
  }

  Future<void> _openChat(String conversationId, String uid) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final cid = conversationId.isEmpty
          ? await SocialService.startConversation(uid)
          : conversationId;
      if (!mounted) return;
      await Navigator.of(context).push(appRoute(
        'chat',
        {'cid': cid, 'uid': uid},
        (_) => ChatScreen(conversationId: cid, otherUid: uid),
      ));
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

  Widget _resultTile({
    required String uid,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final colors = context.appColors;
    return ListTile(
      leading: UserAvatar(
        uid: uid,
        fallbackName: title,
        radius: 23,
        showOnline: true,
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colors.textDim)),
      onTap: _opening ? null : onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: TextField(
          controller: _query,
          focusNode: _focus,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          decoration: InputDecoration(
            hintText: tr('ابحث في المحادثات والأشخاص'),
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (_term.isNotEmpty)
            IconButton(
              tooltip: tr('مسح'),
              onPressed: () {
                _query.clear();
                _onChanged('');
              },
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
      body: _term.isEmpty
          ? _MessageState(
              message: tr('ابحث باسم الشخص أو باسم المستخدم أو نص الرسالة'),
              icon: Icons.search_rounded,
            )
          : FutureBuilder<_SearchOutcome>(
              future: _results,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  if (snapshot.hasError) {
                    return ErrorState(
                      error: snapshot.error,
                      title: tr('تعذر البحث'),
                      onRetry: () => setState(() => _results = _search(_term)),
                    );
                  }
                  return const AppLoading();
                }
                final outcome = snapshot.data!;
                if (outcome.chats.isEmpty && outcome.users.isEmpty) {
                  return _MessageState(
                    message: trf('لا نتائج لـ «{0}»', [_term]),
                    icon: Icons.search_off_rounded,
                  );
                }
                Widget header(String label) => Padding(
                      padding:
                          const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 6),
                      child: Text(label,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                    );
                return ListView(
                  padding: const EdgeInsets.only(bottom: 40),
                  children: [
                    if (outcome.chats.isNotEmpty) header(tr('المحادثات')),
                    for (final match in outcome.chats)
                      _resultTile(
                        uid: match.user.uid,
                        title: match.user.displayName,
                        subtitle: '@${match.user.username}',
                        onTap: () =>
                            _openChat(match.conversation.id, match.user.uid),
                      ),
                    if (outcome.users.isNotEmpty) header(tr('الأشخاص')),
                    for (final user in outcome.users)
                      _resultTile(
                        uid: user.uid,
                        title: user.displayName,
                        subtitle: '@${user.username}',
                        onTap: () => _openChat('', user.uid),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String otherUid;

  /// محادثة جماعية (يُعرف أيضاً من مستند المحادثة بعد التحميل).
  final bool isGroup;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.otherUid,
    this.isGroup = false,
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
  // مفتاح لكل رسالة: للانتقال إلى الرسالة الأصلية عند الضغط على «ردّ على رسالة».
  final Map<String, GlobalKey> _messageKeys = {};
  String? _highlightId;
  Timer? _highlightTimer;
  Timer? _draftTimer;
  late final Stream<ChatBlockState> _blockState;
  StreamSubscription<Map<String, DateTime>>? _typingSub;
  StreamSubscription<RemoteMessage>? _chatPushSub;
  Map<String, DateTime> _typingUsers = const {};
  ChatMessage? _replyTarget;
  // رسالة قيد التعديل (وضع التعديل يستعمل نفس حقل الإدخال) ومسودة ما قبله.
  ChatMessage? _editTarget;
  String _draftBeforeEdit = '';
  DateTime? _readAtWhenOpened;
  bool _capturedReadAtWhenOpened = false;
  bool _sending = false;

  // تسجيل الرسالة الصوتية (كإنستغرام): ميكروفون بدل زر الإرسال عند فراغ الحقل.
  VoiceRecorder? _voice;
  Timer? _voiceTimer;
  bool _recording = false;
  int _recSecs = 0;
  // وضع الضغط المطوّل: الإصبع على الميكروفون؛ السحب جانباً يلغي التسجيل.
  bool _recHold = false;
  bool _holdActive = false;
  bool _recCancel = false;
  bool _draftRestored = false;
  String? _failedText;
  List<Uint8List> _failedImages = const [];
  // صور مرفقة بانتظار الإرسال اليدوي (حتى 10، كإنستغرام).
  final List<Uint8List> _pendingImages = [];
  static const _maxAttach = 10;
  // وضع «مرة واحدة»: الصور المرفقة تُرسل بوسم viewOnce (تُعرض مرة واحدة فقط).
  bool _viewOnce = false;
  // وضع الاختفاء: الرسائل الجديدة تُختفي بعد مدة (expiresAt).
  bool _vanish = false;
  static const _vanishDuration = Duration(hours: 1);
  Set<String> _hidden = const {};
  StreamSubscription<Set<String>>? _hiddenSub;

  // وضع التحديد المتعدد: لحذف/نسخ/إعادة توجيه عدة رسائل دفعة واحدة.
  bool _selecting = false;
  final Set<String> _selectedIds = <String>{};

  // الرسائل: اشتراك واحد يُنشأ في initState (لا يُعاد إنشاؤه مع كل build).
  StreamSubscription<List<ChatMessage>>? _messagesSub;
  List<ChatMessage>? _live; // آخر الرسائل مباشرةً
  final List<ChatMessage> _older = []; // صفحات أقدم حُمّلت عند التمرير
  DateTime? _anchor; // بعد تحميل الأقدم: يبدأ المباشر من هنا بلا حدّ
  bool _hasMore = true;
  Object? _messagesError;
  bool _loadingMore = false;
  bool _foreground = true;

  // زر «النزول للأسفل»: يظهر عند التمرير إلى الأعلى، مع عدّاد الرسائل الجديدة
  // التي وصلت أثناء ذلك (القائمة معكوسة: pixels = 0 تعني أحدث رسالة).
  bool _awayFromBottom = false;
  int _newCount = 0;
  DateTime? _newestSeenAt;

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
  AppUser? _otherUser; // ملف الطرف الآخر (لاسمه في «شوهد بواسطة»)
  // خيارات خاصة بي (محلية): كنية الطرف الآخر ولون/خلفية المحادثة.
  String _nickname = '';
  ChatLook _look = const ChatLook();

  /// لون فقاعاتي في هذه المحادثة.
  Color get _mineColor => _look.bubble;
  bool? _friends; // null = لم يُعرف بعد (لا نقيّد الواجهة حتى يُعرف)

  /// محادثة جماعية (من الواجهة أو من مستند المحادثة بعد التحميل).
  bool get _isGroup => widget.isGroup || _chatData?['isGroup'] == true;

  /// المحادثة غير مقبولة بعد وليسا صديقين (لا ينطبق على المجموعات).
  bool get _restricted {
    if (_isGroup) return false;
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
    // فتح المحادثة يلغي تعليمها «غير مقروءة» يدوياً (كإنستغرام).
    SocialService.setChatUnread(widget.conversationId, false);
    _blockState = widget.otherUid.isEmpty
        ? Stream<ChatBlockState>.value(
            const ChatBlockState(blockedByMe: false, blockedByThem: false))
        : SocialService.blockState(widget.otherUid);
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
    // التسجيل لإشعارات الدفع يتم مرة عند الدخول (HomeShell) لا عند كل محادثة.
    _chatPushSub = SocialService.foregroundChatMessages.listen((message) {
      // الرسائل بيانات فقط على الويب: العنوان والنص في data.
      final body =
          message.notification?.body ?? (message.data['body'] as String?) ?? '';
      // لا نُظهر تنبيهاً عن المحادثة المفتوحة أمامي الآن.
      if (message.data['conversationId'] == widget.conversationId) return;
      if (!mounted || body.isEmpty) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(body),
          duration: const Duration(seconds: 3),
        ),
      );
    });
    _messageFocus.addListener(_syncTypingState);
    _messageFocus.addListener(_hideStickersOnFocus);
    _text.addListener(_syncTypingState);
    _text.addListener(_scheduleDraftSave);
    _text.addListener(_syncMicButton);
    _text.addListener(_updateMentionSuggestions);
    _restoreDraft();
    _loadChatPrefs();
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
    if (widget.otherUid.isNotEmpty) {
      SocialService.areMutualFriends(widget.otherUid).then((value) {
        if (mounted) setState(() => _friends = value);
      }).catchError((Object _) {});
      // اسم الطرف الآخر لسطر «شوهد بواسطة» (من الذاكرة المؤقتة، بلا قراءة إضافية).
      UserService.profileOf(widget.otherUid).then((value) {
        if (mounted && value != null) setState(() => _otherUser = value);
      }).catchError((Object _) {});
    }
    _subscribeMessages();
  }

  Future<void> _loadChatPrefs() async {
    final me = SocialService.currentUid;
    final look = await ChatPrefs.loadLook(me, widget.conversationId);
    final nick = (_isGroup || widget.otherUid.isEmpty)
        ? ''
        : await ChatPrefs.loadNickname(me, widget.otherUid);
    if (!mounted) return;
    setState(() {
      _look = look;
      _nickname = nick;
    });
  }

  Future<void> _editNickname() async {
    final real = _otherUser?.displayName ?? '';
    final result = await showNicknameDialog(context,
        current: _nickname, realName: real);
    if (result == null || !mounted) return;
    setState(() => _nickname = result);
    await ChatPrefs.saveNickname(
        SocialService.currentUid, widget.otherUid, result);
  }

  Future<void> _editChatLook() async {
    await showChatLookSheet(
      context,
      initial: _look,
      onChanged: (look) {
        if (mounted) setState(() => _look = look);
        ChatPrefs.saveLook(
            SocialService.currentUid, widget.conversationId, look);
      },
    );
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
    if (_typingSent) {
      _typingSent = false;
      SocialService.setTyping(widget.conversationId, isTyping: false)
          .catchError((_) {});
    }
    _text.removeListener(_scheduleDraftSave);
    _text.removeListener(_syncMicButton);
    _text.removeListener(_updateMentionSuggestions);
    _voiceTimer?.cancel();
    _voice?.cancel();
    _draftTimer?.cancel();
    _saveDraft();
    _messageFocus.dispose();
    _highlightTimer?.cancel();
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

  bool _typingSent = false;
  DateTime? _typingSentAt;

  /// يرسل «يكتب…» عند بدء الكتابة ويجدّده كل 4 ثوانٍ فقط (القراءة تعتبره
  /// منتهياً بعد 8)، ويمسحه مرة واحدة عند التوقف. لا قراءات ولا كتابة لكل حرف.
  void _syncTypingState() {
    if (!mounted) return;
    final shouldType = _messageFocus.hasFocus && _text.text.trim().isNotEmpty;
    if (shouldType) {
      final last = _typingSentAt;
      if (_typingSent &&
          last != null &&
          DateTime.now().difference(last).inSeconds < 4) {
        return;
      }
      _typingSent = true;
      _typingSentAt = DateTime.now();
    } else {
      if (!_typingSent) return;
      _typingSent = false;
      _typingSentAt = null;
    }
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
    // أثناء تعديل رسالة لا يُحفظ نصها كمسودة.
    if (_editTarget != null) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      final draft = _text.text;
      if (draft.trim().isEmpty) {
        await preferences.remove(_draftKey);
      } else {
        await preferences.setString(_draftKey, draft);
      }
      // يُحدّث معاينة المسودة في صندوق الرسائل.
      chatDraftsRevision.value++;
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
          // عدّاد «الجديد» يظهر على زر النزول للأسفل فقط إن كنت متمرّراً للأعلى.
          if (messages.isNotEmpty) {
            final newest = messages.last;
            final previous = _newestSeenAt;
            if (_awayFromBottom && previous != null) {
              for (final message in messages) {
                if (message.senderUid != SocialService.currentUid &&
                    message.createdAt.isAfter(previous)) {
                  _newCount++;
                }
              }
            }
            _newestSeenAt = newest.createdAt;
          }
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

  GlobalKey _keyFor(String messageId) =>
      _messageKeys.putIfAbsent(messageId, () => GlobalKey());

  /// ينتقل إلى الرسالة الأصلية ويضيئها لحظة. إن لم تكن محمّلة أو حُذفت يعرض تنبيهاً.
  Future<void> _jumpToMessage(String messageId) async {
    final loaded = _messages;
    if (loaded == null ||
        !loaded.any((m) => m.id == messageId && !_hidden.contains(m.id))) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('الرسالة الأصلية غير متاحة'))),
      );
      return;
    }
    final key = _keyFor(messageId);
    // القائمة معكوسة: الأقدم في الأعلى، فنمرّر للأعلى خطوة خطوة حتى تظهر.
    for (var i = 0; i < 80 && key.currentContext == null; i++) {
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      if (position.pixels >= position.maxScrollExtent) break;
      _scroll.jumpTo((position.pixels + position.viewportDimension * 0.8)
          .clamp(0.0, position.maxScrollExtent)
          .toDouble());
      await WidgetsBinding.instance.endOfFrame;
    }
    final targetContext = key.currentContext;
    if (!mounted) return;
    if (targetContext == null || !targetContext.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('الرسالة الأصلية غير متاحة'))),
      );
      return;
    }
    await Scrollable.ensureVisible(
      targetContext,
      alignment: 0.5,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    if (!mounted) return;
    setState(() => _highlightId = messageId);
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _highlightId = null);
    });
  }

  /// عند الوصول لأعلى القائمة (أقدم الرسائل) نحمّل صفحة أقدم فقط، دون إعادة
  /// قراءة ما سبق. وأيضاً يتابع هنا ظهور زر «النزول للأسفل».
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final away = _scroll.position.pixels > 260;
    if (away != _awayFromBottom) {
      setState(() {
        _awayFromBottom = away;
        if (!away) _newCount = 0;
      });
    }
    if (_loadingMore || !_hasMore) return;
    if (_live == null) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
      _loadOlder();
    }
  }

  /// ينزل إلى أحدث رسالة ويصفّر عدّاد الجديد.
  Future<void> _jumpToLatest() async {
    if (_newCount != 0) setState(() => _newCount = 0);
    if (!_scroll.hasClients) return;
    await _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
    if (mounted) setState(() => _awayFromBottom = false);
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

  bool _hadContent = false;

  /// يبدّل الكاميرا/الإرسال وإخفاء الميكروفون عند تغيّر فراغ الحقل فقط.
  // ---- الإشارة بـ @ في المجموعات ----
  /// اسم المستخدم (بحروف صغيرة) → معرّفه، لمن اخترتهم من القائمة.
  final Map<String, String> _mentionMap = {};
  List<AppUser>? _members;
  bool _membersLoading = false;
  List<AppUser> _mentionSuggestions = const [];
  static final RegExp _mentionQuery = RegExp(r'(?:^|\s)@([^\s@]{0,30})$');

  /// أعضاء المجموعة (بلا أنا): يُحمَّلون عند أول @ فقط.
  Future<void> _loadMembers() async {
    if (_membersLoading) return;
    final ids = (_chatData?['participants'] as List? ?? const [])
        .whereType<String>()
        .where((uid) => uid != SocialService.currentUid)
        .toList();
    if (ids.isEmpty) return;
    _membersLoading = true;
    try {
      final users = await Future.wait(ids.map(UserService.profileOf));
      _members = users
          .whereType<AppUser>()
          .where((user) => user.username.isNotEmpty)
          .toList();
    } catch (_) {
      // يُعاد المحاولة عند الضغط على @ مرة أخرى.
    } finally {
      _membersLoading = false;
    }
    if (mounted) _updateMentionSuggestions();
  }

  /// نص @ الجاري كتابته عند المؤشر (أو null).
  RegExpMatch? _activeMention(String text, int cursor) {
    final end = cursor.clamp(0, text.length);
    return _mentionQuery.firstMatch(text.substring(0, end));
  }

  void _updateMentionSuggestions() {
    List<AppUser> next = const [];
    if (_isGroup && _editTarget == null && !_recording) {
      final text = _text.text;
      final selection = _text.selection;
      final cursor = selection.isValid ? selection.baseOffset : text.length;
      final match = _activeMention(text, cursor);
      if (match != null) {
        final members = _members;
        if (members == null) {
          _loadMembers();
        } else {
          final query = match.group(1)!.toLowerCase();
          next = members
              .where((user) =>
                  query.isEmpty ||
                  user.username.toLowerCase().startsWith(query) ||
                  user.name.toLowerCase().contains(query))
              .take(6)
              .toList();
        }
      }
    }
    final same = next.length == _mentionSuggestions.length &&
        [for (var i = 0; i < next.length; i++) next[i].uid == _mentionSuggestions[i].uid]
            .every((e) => e);
    if (!same && mounted) setState(() => _mentionSuggestions = next);
  }

  void _pickMention(AppUser user) {
    final text = _text.text;
    final selection = _text.selection;
    final cursor = (selection.isValid ? selection.baseOffset : text.length)
        .clamp(0, text.length);
    final match = _activeMention(text, cursor);
    if (match == null) return;
    final atIndex = match.end - match.group(1)!.length - 1;
    final insert = '@${user.username} ';
    _mentionMap[user.username.toLowerCase()] = user.uid;
    _text.value = TextEditingValue(
      text: text.substring(0, atIndex) + insert + text.substring(cursor),
      selection: TextSelection.collapsed(offset: atIndex + insert.length),
    );
    _messageFocus.requestFocus();
  }

  /// من بقيت إشارتهم @ داخل النص فعلاً (يُهمَل من حُذف اسمه بعد اختياره).
  List<String> _mentionsIn(String text) {
    if (!_isGroup || _mentionMap.isEmpty) return const [];
    final out = <String>[];
    _mentionMap.forEach((username, uid) {
      final pattern = RegExp(
          '(?:^|\\s)@${RegExp.escape(username)}(?![A-Za-z0-9_.])',
          caseSensitive: false);
      if (pattern.hasMatch(text)) out.add(uid);
    });
    return out.take(10).toList();
  }

  Widget _buildMentionList() {
    final colors = context.appColors;
    return Container(
      constraints: const BoxConstraints(maxHeight: 230),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      decoration: BoxDecoration(
        color: colors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          for (final user in _mentionSuggestions)
            ListTile(
              dense: true,
              leading: UserAvatar(
                uid: user.uid,
                fallbackName: user.username,
                profile: user,
                radius: 16,
              ),
              title: Text(user.displayName,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('@${user.username}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textDim)),
              onTap: () => _pickMention(user),
            ),
        ],
      ),
    );
  }

  void _syncMicButton() {
    final now = _hasContent;
    if (now != _hadContent && mounted) setState(() => _hadContent = now);
  }

  bool get _canRecordVoice =>
      VoiceRecorder.supported &&
      !_sending &&
      _editTarget == null &&
      !_firstMessageToStranger &&
      _pendingImages.isEmpty &&
      _text.text.trim().isEmpty;

  Future<void> _startRecording({bool hold = false}) async {
    if (_recording || !_canRecordVoice) return;
    _holdActive = hold;
    _recCancel = false;
    final recorder = VoiceRecorder();
    try {
      await recorder.start();
    } catch (_) {
      recorder.cancel();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(tr('تعذر الوصول إلى الميكروفون، اسمح به من المتصفح'))),
        );
      }
      return;
    }
    if (!mounted || (hold && !_holdActive)) {
      // رُفع الإصبع قبل أن يبدأ التسجيل (مثلاً أثناء نافذة الصلاحية).
      recorder.cancel();
      return;
    }
    setState(() {
      _voice = recorder;
      _recording = true;
      _recHold = hold;
      _recSecs = 0;
    });
    _voiceTimer?.cancel();
    _voiceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _recSecs++);
      // الحد الأقصى دقيقتان: يُرسل التسجيل تلقائياً عند بلوغه.
      if (_recSecs >= voiceMaxSeconds) _finishRecording(send: true);
    });
  }

  Future<void> _finishRecording({required bool send}) async {
    final recorder = _voice;
    if (recorder == null || !_recording) return;
    _voiceTimer?.cancel();
    setState(() {
      _recording = false;
      _recHold = false;
      _recCancel = false;
      _voice = null;
    });
    _holdActive = false;
    if (!send) {
      recorder.cancel();
      return;
    }
    final replyTarget = _replyTarget;
    final expiresAt = _vanish ? DateTime.now().add(_vanishDuration) : null;
    setState(() => _sending = true);
    try {
      final clip = await recorder.stop();
      if (clip == null || clip.seconds < 1) return;
      await SocialService.sendAudio(
        widget.conversationId,
        clip.bytes,
        mime: clip.mime,
        ext: clip.ext,
        seconds: clip.seconds,
        wave: clip.wave,
        replyToMessageId: replyTarget?.id,
        replyToText: replyTarget?.text,
        replyToSenderUid: replyTarget?.senderUid,
        expiresAt: expiresAt,
      );
      if (mounted) setState(() => _replyTarget = null);
    } catch (e) {
      _showError(tr('تعذر إرسال الرسالة الصوتية'), e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _fmtSecs(int s) =>
      '${(s ~/ 60)}:${(s % 60).toString().padLeft(2, '0')}';

  bool get _hasContent =>
      _text.text.trim().isNotEmpty || _pendingImages.isNotEmpty;

  bool get _attachBlocked =>
      _sending || _firstMessageToStranger || _editTarget != null;

  /// قائمة «+»: الخيارات غير الظاهرة في الشريط (مرة واحدة، الموقع).
  /// يفتح ورقة GIF ويرسل المختار (مع الرد الحالي ووضع الاختفاء إن وُجدا).
  Future<void> _pickGif() async {
    final gif = await showModalBottomSheet<GifItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const GifPickerSheet(),
    );
    if (gif == null || !mounted) return;
    final replyTarget = _replyTarget;
    final expiresAt = _vanish ? DateTime.now().add(_vanishDuration) : null;
    try {
      await SocialService.sendGif(
        widget.conversationId,
        gif,
        replyToMessageId: replyTarget?.id,
        replyToText: replyTarget?.text,
        replyToSenderUid: replyTarget?.senderUid,
        expiresAt: expiresAt,
      );
      if (mounted) setState(() => _replyTarget = null);
    } catch (e) {
      _showError(tr('تعذر إرسال الـ GIF'), e);
    }
  }

  Future<void> _showPlusMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(_viewOnce
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_outlined),
              title: Text(_viewOnce
                  ? tr('إلغاء الإرسال مرة واحدة')
                  : tr('إرسال صورة مرة واحدة')),
              onTap: () => Navigator.pop(sheetContext, 'viewOnce'),
            ),
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: Text(tr('إرسال موقعي')),
              onTap: () => Navigator.pop(sheetContext, 'location'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'viewOnce') {
      setState(() => _viewOnce = !_viewOnce);
    } else if (action == 'location') {
      final place = await currentChatLocation();
      if (!mounted) return;
      if (place == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('تعذر تحديد موقعك، اسمح به من المتصفح'))),
        );
        return;
      }
      try {
        await SocialService.sendLocation(widget.conversationId,
            lat: place.lat, lng: place.lng);
      } catch (e) {
        _showError(tr('تعذر إرسال الموقع'), e);
      }
    }
  }

  /// شريط الإدخال على ترتيب إنستغرام: [كاميرا/إرسال] [حقل النص] [ميكروفون]
  /// [معرض] [ملصقات] [+] داخل كبسولة واحدة.
  Widget _buildComposerPill() {
    final colors = context.appColors;
    final hasContent = _hasContent;
    final blocked = _attachBlocked;
    final holding = _recording && _recHold;
    Widget small(IconData icon, String tip, VoidCallback? onTap,
            {Color? color}) =>
        IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          color: color,
          onPressed: onTap,
          icon: Icon(icon),
        );
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(5, 4, 4, 4),
      decoration: BoxDecoration(
        color: colors.surfaceHigh,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (!holding)
          IconButton.filled(
            tooltip: hasContent ? tr('إرسال') : tr('التقاط صورة'),
            onPressed: _sending
                ? null
                : (hasContent
                    ? _send
                    : (blocked ? null : () => _pickImage(ImageSource.camera))),
            style: IconButton.styleFrom(backgroundColor: AppColors.accent),
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Icon(
                    hasContent
                        ? Icons.send_rounded
                        : Icons.photo_camera_rounded,
                    color: Colors.white),
          ),
          if (holding)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    const Icon(Icons.fiber_manual_record_rounded,
                        color: Colors.redAccent, size: 14),
                    const SizedBox(width: 8),
                    Text(
                      _fmtSecs(_recSecs),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontFeatures: [FontFeature.tabularFigures()]),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _recCancel
                            ? tr('حرّر للإلغاء')
                            : tr('اسحب جانباً للإلغاء'),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            color: _recCancel
                                ? Colors.redAccent
                                : colors.textDim),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
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
                hintText: tr('مراسلة...'),
                counterText: '',
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
            ),
          ),
          // الميكروفون: ضغطة قصيرة = تسجيل مثبّت بشريط، ضغط مطوّل = يسجّل
          // ما دام الإصبع عليه (السحب جانباً يلغي). المفتاح يُبقي الإيماءة
          // حيّة حين يتبدّل الشريط أثناء الضغط.
          if ((!hasContent || holding) && VoiceRecorder.supported)
            GestureDetector(
              key: const ValueKey('voice-mic'),
              behavior: HitTestBehavior.opaque,
              onTap: _canRecordVoice ? () => _startRecording() : null,
              onLongPressStart: _canRecordVoice
                  ? (_) => _startRecording(hold: true)
                  : null,
              onLongPressMoveUpdate: (d) {
                if (!_recording || !_recHold) return;
                final cancel = d.offsetFromOrigin.dx.abs() > 80;
                if (cancel != _recCancel) setState(() => _recCancel = cancel);
              },
              onLongPressEnd: (_) {
                _holdActive = false;
                if (_recording && _recHold) {
                  _finishRecording(send: !_recCancel && _recSecs >= 1);
                }
              },
              onLongPressCancel: () {
                _holdActive = false;
                if (_recording && _recHold) _finishRecording(send: false);
              },
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: holding
                    ? BoxDecoration(
                        shape: BoxShape.circle,
                        color: _recCancel
                            ? Colors.redAccent
                            : AppColors.accent.withOpacity(0.25),
                      )
                    : null,
                child: Icon(
                  holding ? Icons.mic_rounded : Icons.mic_none_rounded,
                  color: _canRecordVoice || holding ? null : colors.textDim,
                ),
              ),
            ),
          if (!hasContent && !holding)
            small(Icons.image_outlined, tr('إرسال صورة'),
                blocked ? null : () => _pickImage(ImageSource.gallery)),
          if (!hasContent && !holding && GifService.enabled)
            small(Icons.gif_box_outlined, tr('GIF'),
                blocked || _firstMessageToStranger ? null : _pickGif),
          if (!holding)
            small(
                _showStickers
                    ? Icons.keyboard_alt_outlined
                    : Icons.emoji_emotions_outlined,
                tr('الملصقات والرموز التعبيرية'),
                _toggleStickers),
          if (!holding)
            small(Icons.add_circle_outline_rounded, tr('إضافة'),
                blocked ? null : _showPlusMenu,
                color: _viewOnce ? AppColors.accent : null),
        ],
      ),
    );
  }

  Widget _buildRecordingBar() {
    final colors = context.appColors;
    return Row(
      children: [
        IconButton(
          tooltip: tr('إلغاء'),
          onPressed: () => _finishRecording(send: false),
          icon: const Icon(Icons.delete_outline_rounded),
        ),
        Expanded(
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: colors.surfaceHigh,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                const Icon(Icons.fiber_manual_record_rounded,
                    color: Colors.redAccent, size: 14),
                const SizedBox(width: 8),
                Text(
                  _fmtSecs(_recSecs),
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()]),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: _recSecs / voiceMaxSeconds,
                      minHeight: 3,
                      backgroundColor: colors.surface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 5),
        IconButton.filled(
          tooltip: tr('إرسال'),
          onPressed: () => _finishRecording(send: true),
          style: IconButton.styleFrom(backgroundColor: AppColors.accent),
          icon: const Icon(Icons.send_rounded, color: Colors.white),
        ),
      ],
    );
  }

  /// يرسل الصورة المرفقة ثم النص (بهذا الترتيب) عند ضغط زر الإرسال فقط.
  /// رفع الصورة هو الجزء البطيء، لذلك يُعطَّل الزر أثناءه فقط.
  Future<void> _send() async {
    if (_sending) return;
    final editing = _editTarget;
    if (editing != null) {
      await _submitEdit(editing);
      return;
    }
    final text = _text.text.trim();
    final images = List<Uint8List>.of(_pendingImages);
    final replyTarget = _replyTarget;
    final viewOnce = _viewOnce;
    final expiresAt = _vanish ? DateTime.now().add(_vanishDuration) : null;
    if (text.isEmpty && images.isEmpty) return;
    final mentions = _mentionsIn(text);
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
            viewOnce: viewOnce,
            expiresAt: expiresAt,
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
              expiresAt: expiresAt,
            )
          : SocialService.sendMessage(
              widget.conversationId,
              text,
              replyToMessageId: replyTarget?.id,
              replyToText: replyTarget?.text,
              replyToSenderUid: replyTarget?.senderUid,
              expiresAt: expiresAt,
              mentions: mentions,
            );
      try {
        await sending;
        _mentionMap.clear();
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
    // «مرة واحدة» يخصّ الصور المرفقة: يُصفَّر بعد الإرسال (كإنستغرام).
    if (viewOnce && mounted && _viewOnce) {
      setState(() => _viewOnce = false);
    }
  }

  /// يبدأ تعديل رسالتي: يضع نصها في حقل الإدخال ويحتفظ بمسودتي الحالية.
  void _startEdit(ChatMessage message) {
    setState(() {
      _draftBeforeEdit = _editTarget == null ? _text.text : _draftBeforeEdit;
      _editTarget = message;
      _replyTarget = null;
      _showStickers = false;
    });
    _text.text = message.text;
    _text.selection = TextSelection.collapsed(offset: _text.text.length);
    _messageFocus.requestFocus();
  }

  /// يخرج من وضع التعديل ويعيد مسودتي السابقة إلى الحقل.
  void _cancelEdit() {
    if (_editTarget == null) return;
    final draft = _draftBeforeEdit;
    setState(() {
      _editTarget = null;
      _draftBeforeEdit = '';
    });
    _text.text = draft;
  }

  Future<void> _submitEdit(ChatMessage target) async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    if (text == target.text.trim()) {
      _cancelEdit();
      return;
    }
    setState(() => _sending = true);
    try {
      await SocialService.editMessage(widget.conversationId, target.id, text);
      if (mounted) _cancelEdit();
    } catch (e) {
      _showError(tr('تعذر تعديل الرسالة'), e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _openNetworkImage(String url, {String? senderUid, DateTime? sentAt}) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _NetworkImageViewer(
            url: url, senderUid: senderUid, sentAt: sentAt),
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
    if (action == 'info') {
      Navigator.of(context).push(appRoute(
        'chatInfo',
        {'cid': widget.conversationId, 'uid': widget.otherUid},
        (_) => _isGroup
            ? _GroupInfoScreen(
                conversationId: widget.conversationId,
                data: _chatData,
              )
            : ChatInfoScreen(
                conversationId: widget.conversationId,
                otherUid: widget.otherUid,
              ),
      ));
      return;
    }
    if (action == 'nickname') {
      await _editNickname();
      return;
    }
    if (action == 'look') {
      await _editChatLook();
      return;
    }
    if (action == 'vanish') {
      setState(() => _vanish = !_vanish);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_vanish
                ? tr('تم تفعيل وضع الاختفاء: الرسائل الجديدة تختفي بعد ساعة')
                : tr('تم إيقاف وضع الاختفاء')),
          ),
        );
      }
      return;
    }
    if (action == 'leave') {
      await _leaveGroup();
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

  /// حالة رسالتي: 'read' شوهدت، 'delivered' وصلت، 'sent' أُرسلت فقط.
  /// في المجموعة تُعدّ مقروءة/مسلَّمة فقط حين يقرأها/يستلمها كل الأعضاء.
  String _receiptOf(ChatMessage message) {
    final others = (_chatData?['participants'] as List? ?? const [])
        .cast<String>()
        .where((uid) => uid != SocialService.currentUid)
        .toList();
    if (others.isEmpty) {
      if (widget.otherUid.isEmpty) return 'sent';
      others.add(widget.otherUid);
    }
    bool done(String uid, String field) {
      final at = _stampOf(field, uid);
      final listed = field == 'readAt'
          ? message.readBy.contains(uid)
          : message.deliveredTo.contains(uid);
      return listed || (at != null && !message.createdAt.isAfter(at));
    }

    if (others.every((uid) => done(uid, 'readAt'))) return 'read';
    if (others.every((uid) => done(uid, 'deliveredAt'))) return 'delivered';
    return 'sent';
  }

  /// عنوان شريط المجموعة: الصورة والاسم وعدد الأعضاء (يُفتح منه معلومات المجموعة).
  Widget _groupAppBarTitle(BuildContext context) {
    final colors = context.appColors;
    final name = ((_chatData?['groupName'] as String?) ?? '').trim();
    final photo = ((_chatData?['groupPhoto'] as String?) ?? '').trim();
    final participants =
        (_chatData?['participants'] as List? ?? const []).cast<String>();
    return InkWell(
      onTap: _openGroupInfo,
      child: Row(
        children: [
          _GroupPhoto(
            participants: participants,
            photoUrl: photo,
            size: 38,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name.isEmpty ? tr('مجموعة') : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  trf('{0} عضو', [participants.length]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textDim, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// يفتح شاشة معلومات المجموعة (تعديل الاسم/الصورة وإدارة الأعضاء).
  void _openGroupInfo() {
    Navigator.of(context).push(appRoute(
      'chatInfo',
      {'cid': widget.conversationId, 'uid': ''},
      (_) => _GroupInfoScreen(
        conversationId: widget.conversationId,
        data: _chatData,
      ),
    ));
  }

  /// مغادرة المجموعة بعد تأكيد، ثم الرجوع إلى الصندوق.
  Future<void> _leaveGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('مغادرة المجموعة؟')),
        content: Text(tr('لن تستقبل رسائل هذه المجموعة بعد الآن.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr('إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr('مغادرة')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await SocialService.leaveGroup(widget.conversationId);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      _showError(tr('تعذر مغادرة المجموعة'), error);
    }
  }

  /// يثبّت رسالة داخل المحادثة (يراها الطرفان) أو يلغي التثبيت بتمرير null.
  Future<void> _setPinnedMessage(String? messageId) async {
    try {
      await SocialService.setPinnedMessage(widget.conversationId, messageId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(messageId == null
                  ? tr('تم إلغاء التثبيت')
                  : tr('تم تثبيت الرسالة'))),
        );
      }
    } catch (error) {
      _showError(tr('تعذر تثبيت الرسالة'), error);
    }
  }

  Future<void> _showMessageActions(ChatMessage message, bool mine) async {
    if (message.deleted) {
      // أثر محذوف: الوحيد المتاح «حذف لدي فقط» لإخفائه عندي.
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: context.appColors.surface,
        builder: (sheetContext) => SafeArea(
          child: ListTile(
            leading: const Icon(Icons.delete_outline_rounded),
            title: Text(tr('حذف لدي فقط')),
            onTap: () async {
              Navigator.pop(sheetContext);
              try {
                await SocialService.hideMessageForMe(
                    widget.conversationId, message.id);
              } catch (error) {
                _showError(tr('تعذر حذف الرسالة'), error);
              }
            },
          ),
        ),
      );
      return;
    }
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

    // التفاعلات: صف ملصقات سريع أعلى الورقة بدل «إضافة تفاعل»، وزر + يفتح كل الملصقات
    // داخل نفس الورقة.
    const quick = ['❤️', '😂', '😮', '😢', '🔥', '👍'];
    final myReaction = message.reactions[SocialService.currentUid];
    // إيصال رسالتي: تم الإرسال / تم التسليم / شوهد بواسطة الطرف الآخر.
    final receipt = mine ? _receiptOf(message) : null;
    final pinnedId = (_chatData?['pinnedMessageId'] as String?) ?? '';
    final isPinned = pinnedId == message.id;
    var expanded = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.appColors.surface,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: expanded
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: IconButton(
                        tooltip: tr('رجوع'),
                        onPressed: () => setSheetState(() => expanded = false),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    ),
                    StickerPanel(
                      height: 320,
                      onPick: (sticker) {
                        Navigator.pop(sheetContext);
                        _reactToMessage(message, sticker);
                      },
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final emoji in quick)
                            GestureDetector(
                              onTap: () {
                                Navigator.pop(sheetContext);
                                _reactToMessage(message, emoji);
                              },
                              child: Container(
                                width: 46,
                                height: 46,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: myReaction == emoji
                                      ? AppColors.brandPurple.withOpacity(0.18)
                                      : Colors.transparent,
                                ),
                                child: StickerGlyph(emoji, size: 32),
                              ),
                            ),
                          GestureDetector(
                            onTap: () => setSheetState(() => expanded = true),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: context.appColors.surfaceHigh,
                              ),
                              child: Icon(Icons.add_rounded,
                                  color: context.appColors.text),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: context.appColors.surfaceHigh),
                    // إيصال رسالتي: تم الإرسال / تم التسليم / شوهد بواسطة الطرف.
                    if (receipt != null)
                      ListTile(
                        leading: Icon(
                          receipt == 'sent'
                              ? Icons.done_rounded
                              : Icons.done_all_rounded,
                          color: receipt == 'read'
                              ? const Color(0xFF4FC3F7)
                              : context.appColors.textDim,
                        ),
                        title: Text(switch (receipt) {
                          'read' => tr('شوهد'),
                          'delivered' => tr('تم التسليم'),
                          _ => tr('تم الإرسال'),
                        }),
                        subtitle: receipt == 'read' && _otherUser != null
                            ? Text('${tr('شوهد بواسطة')} '
                                '${_nickname.isNotEmpty ? _nickname : _otherUser!.displayName}')
                            : null,
                      ),
                    ListTile(
                      leading: Icon(
                          isPinned ? Icons.push_pin : Icons.push_pin_outlined),
                      title: Text(isPinned
                          ? tr('إلغاء تثبيت الرسالة')
                          : tr('تثبيت الرسالة')),
                      subtitle: Text(tr('تظهر أعلى المحادثة للطرفين')),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _setPinnedMessage(isPinned ? null : message.id);
                      },
                    ),
                    StreamBuilder<Set<String>>(
                      stream: SocialService.savedMessageIds(),
                      builder: (context, savedSnapshot) {
                        // المحفوظات لا تدعم GIF.
                        if (message.kind == 'gif') {
                          return const SizedBox.shrink();
                        }
                        final saved =
                            savedSnapshot.data?.contains(message.id) ?? false;
                        return ListTile(
                          leading: Icon(saved
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded),
                          title: Text(
                              saved ? tr('إلغاء الحفظ') : tr('حفظ الرسالة')),
                          subtitle: Text(tr('تجدها في «المحفوظات»')),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _toggleSaved(message, saved);
                          },
                        );
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
                    if (message.kind == 'text' && message.text.trim().isNotEmpty)
                      ListTile(
                        leading: const Icon(Icons.translate_rounded),
                        title: Text(tr('ترجمة')),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          if (mounted) {
                            showTranslationSheet(context, message.text);
                          }
                        },
                      ),
                    if (_canForward(message))
                      ListTile(
                        leading: const Icon(Icons.shortcut_rounded),
                        title: Text(tr('إعادة توجيه')),
                        subtitle: Text(tr('أرسلها إلى محادثة أخرى')),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          if (mounted) _openForwardSheet([message]);
                        },
                      ),
                    ListTile(
                      leading: const Icon(Icons.checklist_rounded),
                      title: Text(tr('تحديد')),
                      subtitle:
                          Text(tr('حدّد عدة رسائل لحذفها أو توجيهها معاً')),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _enterSelection(message);
                      },
                    ),
                    if (mine &&
                        message.kind == 'text' &&
                        DateTime.now().difference(message.createdAt) <=
                            SocialService.messageEditWindow)
                      ListTile(
                        leading: const Icon(Icons.edit_rounded),
                        title: Text(tr('تعديل الرسالة')),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          if (mounted) _startEdit(message);
                        },
                      ),
                    if (mine)
                      ListTile(
                        leading: const Icon(Icons.delete_forever_rounded,
                            color: AppColors.brandPurple),
                        title: Text(tr('حذف لدى الجميع')),
                        subtitle:
                            Text(tr('يظهر عند الطرفين أنها حُذفت')),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          run(
                            () => SocialService.deleteMessage(
                                widget.conversationId, message.id),
                            tr('تعذر حذف الرسالة'),
                          );
                        },
                      ),
                    if (!mine && !message.deleted)
                      ListTile(
                        leading: const Icon(Icons.flag_outlined),
                        title: Text(tr('إبلاغ عن الرسالة')),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _reportMessage(message);
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
      ),
    );
  }

  /// الإبلاغ عن رسالة وردتني: يختار المستخدم السبب ثم يُرسل البلاغ للمشرف.
  Future<void> _reportMessage(ChatMessage message) async {
    final messenger = ScaffoldMessenger.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.appColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(tr('إبلاغ عن هذه الرسالة'),
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: context.appColors.text)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                    tr('اختر السبب الأقرب. لن يعرف المرسل أنك من أبلغ.'),
                    style: TextStyle(
                        fontSize: 12, color: context.appColors.textDim)),
              ),
            ),
            for (final reason in SocialService.reportReasons.entries)
              ListTile(
                title: Text(tr(reason.value)),
                trailing: const Icon(Icons.chevron_left_rounded),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  try {
                    await SocialService.reportMessage(widget.conversationId,
                        message.id, message.senderUid, reason.key,
                        snippet: message.text);
                    messenger.showSnackBar(SnackBar(
                        content: Text(tr('تم إرسال البلاغ، شكراً لك'))));
                  } catch (error) {
                    messenger.showSnackBar(SnackBar(
                        content: Text(friendlyError(error,
                            fallback: tr('تعذر إرسال البلاغ')))));
                  }
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// حفظ الرسالة عندي أو إلغاء حفظها (كإنستغرام).
  Future<void> _toggleSaved(ChatMessage message, bool saved) async {
    try {
      if (saved) {
        await SocialService.unsaveMessage(message.id);
      } else {
        await SocialService.saveMessage(widget.conversationId, message);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(saved ? tr('أُلغي الحفظ') : tr('حُفظت الرسالة'))),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(error, fallback: tr('تعذر حفظ الرسالة'))),
        ),
      );
    }
  }

  /// شريط التطبيق في وضع التحديد المتعدد: العدد + إجراءات جماعية.
  PreferredSizeWidget _selectionAppBar(BuildContext context) {
    final count = _selectedIds.length;
    return AppBar(
      backgroundColor: context.appColors.surface,
      leading: IconButton(
        tooltip: tr('إلغاء'),
        onPressed: _exitSelection,
        icon: const Icon(Icons.close_rounded),
      ),
      title: Text(trf('{0} محددة', [count])),
      actions: [
        IconButton(
          tooltip: tr('إعادة توجيه'),
          onPressed: count == 0 ? null : _forwardSelected,
          icon: const Icon(Icons.shortcut_rounded),
        ),
        IconButton(
          tooltip: tr('نسخ'),
          onPressed: count == 0 ? null : _copySelected,
          icon: const Icon(Icons.copy_rounded),
        ),
        IconButton(
          tooltip: tr('حذف لدي فقط'),
          onPressed: count == 0 ? null : _deleteSelected,
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    );
  }

  void _enterSelection(ChatMessage message) {
    setState(() {
      _selecting = true;
      _selectedIds
        ..clear()
        ..add(message.id);
    });
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
  }

  void _toggleMessageSelected(String id) {
    setState(() {
      if (!_selectedIds.remove(id)) _selectedIds.add(id);
    });
  }

  /// الرسائل المحددة بترتيب زمني (الأقدم أولاً) للنسخ/التوجيه.
  List<ChatMessage> get _selectedMessages {
    final messages = _messages ?? const <ChatMessage>[];
    return messages
        .where((m) => _selectedIds.contains(m.id) && !_hidden.contains(m.id))
        .toList();
  }

  /// هل يمكن إعادة توجيه هذه الرسالة (نص/ملصق/صورة/موقع)؟
  bool _canForward(ChatMessage message) =>
      message.kind == 'text' ||
      message.kind == 'sticker' ||
      (message.kind == 'gif' && message.gifUrl != null) ||
      (message.kind == 'image' &&
          (message.imageUrl != null || message.imageBytes != null)) ||
      (message.kind == 'audio' &&
          message.audioUrl != null &&
          message.audioSecs != null) ||
      (message.kind == 'location' &&
          message.lat != null &&
          message.lng != null);

  void _copySelected() {
    final text = _selectedMessages.map((m) => m.text).join('\n').trim();
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('تم نسخ الرسالة'))),
      );
    }
  }

  void _forwardSelected() {
    final messages = _selectedMessages.where(_canForward).toList();
    if (messages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('لا يمكن إعادة توجيه هذه الرسائل'))),
      );
      return;
    }
    _openForwardSheet(messages);
  }

  Future<void> _deleteSelected() async {
    final ids = _selectedMessages.map((m) => m.id).toList();
    if (ids.isEmpty) return;
    _exitSelection();
    var failed = false;
    for (final id in ids) {
      try {
        await SocialService.hideMessageForMe(widget.conversationId, id);
      } catch (_) {
        failed = true;
      }
    }
    if (mounted && failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('تعذر حذف بعض الرسائل'))),
      );
    }
  }

  /// يفتح ورقة اختيار محادثة (أو أكثر) لإعادة توجيه رسالة أو أكثر إليها.
  Future<void> _openForwardSheet(List<ChatMessage> messages) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.appColors.surface,
      builder: (_) => _ForwardSheet(
        messages: messages,
        exceptConversationId: widget.conversationId,
      ),
    );
  }

  /// يفتح وجهة بطاقة المشاركة: الملف الشخصي، أو المنشور، أو الرابط الخارجي.
  Future<void> _openShareTarget(ChatMessage message) async {
    final messenger = ScaffoldMessenger.of(context);
    final type = message.shareType;
    final id = message.shareId;
    if (type == 'profile' && id != null && id.isNotEmpty) {
      openProfile(context, id);
      return;
    }
    if (type == 'post' && id != null && id.isNotEmpty) {
      Post? post;
      try {
        post = await PostService.postById(id);
      } catch (error) {
        messenger.showSnackBar(SnackBar(
            content:
                Text(friendlyError(error, fallback: tr('تعذر فتح المنشور')))));
        return;
      }
      if (!mounted) return;
      if (post == null) {
        messenger.showSnackBar(
            SnackBar(content: Text(tr('هذا المنشور لم يعد متاحاً'))));
        return;
      }
      final opened = post;
      Navigator.of(context).push<void>(appRoute<void>(
        'post',
        {'id': opened.id},
        (_) => PostDetailScreen(post: opened),
      ));
      return;
    }
    if (type == 'story' && id != null && id.isNotEmpty) {
      Post? story;
      try {
        story = await PostService.storyById(id);
      } catch (error) {
        messenger.showSnackBar(SnackBar(
            content:
                Text(friendlyError(error, fallback: tr('تعذر فتح القصة')))));
        return;
      }
      if (!mounted) return;
      if (story == null) {
        messenger.showSnackBar(
            SnackBar(content: Text(tr('هذه القصة لم تعد متاحة'))));
        return;
      }
      final opened = story;
      await rootNavigatorOf(context).push<void>(PageRouteBuilder<void>(
        opaque: true,
        pageBuilder: (_, __, ___) => StoryViewer(
          groups: [
            StoryGroup(
                uid: opened.uid, username: opened.username, stories: [opened])
          ],
          initial: 0,
        ),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
      ));
      return;
    }
    final link = message.shareLink;
    final uri = link == null ? null : Uri.tryParse(link);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// يفتح موقعاً مُرسلاً في خرائط جوجل.
  Future<void> _openLocation(ChatMessage message) async {
    final lat = message.lat;
    final lng = message.lng;
    if (lat == null || lng == null) return;
    final uri = Uri.parse('https://maps.google.com/?q=$lat,$lng');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(friendlyError(error, fallback: tr('تعذر فتح الموقع')))));
    }
  }

  /// يطلب موقع الجهاز الحالي ويرسله كبطاقة في المحادثة.
  /// يضع تفاعلاً على الرسالة؛ والضغط على نفس تفاعلي الحالي يزيله.
  /// من تفاعل على الرسالة وبماذا؛ ضغطة على تفاعلي تزيله (كإنستغرام).
  Future<void> _showReactions(ChatMessage message) async {
    if (message.reactions.isEmpty) return;
    final me = SocialService.currentUid;
    final entries = message.reactions.entries.toList()
      ..sort((a, b) => a.key == me ? -1 : (b.key == me ? 1 : 0));
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.appColors.surface,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.6),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(tr('التفاعلات'),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              for (final entry in entries)
                FutureBuilder<AppUser?>(
                  future: UserService.profileOf(entry.key),
                  builder: (context, snapshot) {
                    final user = snapshot.data;
                    final isMe = entry.key == me;
                    return ListTile(
                      leading: UserAvatar(
                        uid: entry.key,
                        fallbackName: user?.name ?? '',
                        radius: 20,
                        profile: user,
                      ),
                      title: Text(
                          isMe ? tr('أنت') : (user?.displayName ?? '...')),
                      subtitle: isMe ? Text(tr('اضغط لإزالة تفاعلك')) : null,
                      trailing: StickerGlyph(entry.value, size: 28),
                      onTap: isMe
                          ? () {
                              Navigator.pop(sheetContext);
                              _reactToMessage(message, entry.value);
                            }
                          : null,
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _reactToMessage(ChatMessage message, String reaction) async {
    final same = message.reactions[SocialService.currentUid] == reaction;
    HapticFeedback.lightImpact();
    try {
      await SocialService.setMessageReaction(
        widget.conversationId,
        message.id,
        same ? null : reaction,
      );
    } catch (error) {
      _showError(tr('تعذر تحديث التفاعل'), error);
    }
  }

  /// النقر مرتين على رسالة: تفاعل ❤️ سريع (وإن كان موجوداً يُزال)، كإنستغرام.
  /// بقية التفاعلات من الضغط المطوّل ← صف الملصقات أعلى الورقة.
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

  Widget _messageBody(String text,
      {required bool mine, bool mentions = false}) {
    final style = TextStyle(
      color: mine ? Colors.white : context.appColors.text,
      fontSize: 15,
      height: 1.35,
    );
    // رسالة فيها إشارات @: تُبرَز الأسماء مع الروابط.
    final linkPattern = mentions
        ? RegExp(r'https?://\S+|www\.\S+|(?<![A-Za-z0-9_])@[A-Za-z0-9_.]{2,30}')
        : RegExp(r'https?://\S+|www\.\S+');
    final matches = linkPattern.allMatches(text);
    if (matches.isEmpty) {
      return Text.rich(
        TextSpan(children: inlineEmojiSpans(text, style)),
        textDirection: SocialService.inferTextDirection(text),
        style: style,
      );
    }

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        spans.addAll(
            inlineEmojiSpans(text.substring(cursor, match.start), style));
      }
      var matchEnd = match.end;
      final isMention = text[match.start] == '@';
      if (isMention) {
        // النقطة الأخيرة علامة ترقيم لا من الاسم.
        while (matchEnd > match.start + 1 && text[matchEnd - 1] == '.') {
          matchEnd--;
        }
        spans.add(TextSpan(
          text: text.substring(match.start, matchEnd),
          style: style.copyWith(
            color: mine ? Colors.white : AppColors.brandPurple,
            fontWeight: FontWeight.w700,
          ),
        ));
        cursor = matchEnd;
        continue;
      }
      final url = text.substring(match.start, matchEnd);
      spans.add(TextSpan(
        text: url,
        style: style.copyWith(
          color: mine ? Colors.white : AppColors.brandPurple,
          decoration: TextDecoration.underline,
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () => launchUrl(Uri.parse(url)),
      ));
      cursor = matchEnd;
    }
    if (cursor < text.length) {
      spans.addAll(inlineEmojiSpans(text.substring(cursor), style));
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
            canPop: !_showStickers && !_selecting,
            onPopInvoked: (didPop) {
              if (didPop) return;
              if (_showStickers) {
                setState(() => _showStickers = false);
              } else if (_selecting) {
                _exitSelection();
              }
            },
            child: Scaffold(
              backgroundColor: colors.bg,
              appBar: _selecting
                  ? _selectionAppBar(context)
                  : AppBar(
                      titleSpacing: 0,
                      title: _isGroup
                          ? _groupAppBarTitle(context)
                          : StreamBuilder<AppUser?>(
                              stream:
                                  UserService.profileStream(widget.otherUid),
                              builder: (context, snapshot) {
                                final user = snapshot.data;
                                return Row(
                                  children: [
                                    UserAvatar(
                                      uid: widget.otherUid,
                                      fallbackName: user?.username ?? '',
                                      radius: 19,
                                      showOnline: true,
                                      onTap: () =>
                                          openProfile(context, widget.otherUid),
                                    ),
                                    const SizedBox(width: 10),
                                    Flexible(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _nickname.isNotEmpty
                                                ? _nickname
                                                : (user?.displayName ??
                                                    tr('محادثة')),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (user != null)
                                            StreamBuilder<bool>(
                                              stream: PresenceService.isOnline(
                                                  widget.otherUid),
                                              builder:
                                                  (context, onlineSnapshot) {
                                                final typing = _typingUsers.keys
                                                    .any((uid) =>
                                                        uid !=
                                                        SocialService
                                                            .currentUid);
                                                final online =
                                                    onlineSnapshot.data == true;
                                                final String label;
                                                if (typing) {
                                                  label = tr('يكتب…');
                                                } else if (online) {
                                                  label = tr('نشط الآن');
                                                } else {
                                                  // غير متصل: «نشط قبل 5 دقائق».
                                                  return LastActiveText(
                                                    uid: widget.otherUid,
                                                    fallback:
                                                        '@${user.username}',
                                                    style: TextStyle(
                                                      color: context
                                                          .appColors.textDim,
                                                      fontSize: 12,
                                                    ),
                                                  );
                                                }
                                                return Text(
                                                  label,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: (typing || online)
                                                        ? AppColors.success
                                                        : context
                                                            .appColors.textDim,
                                                    fontSize: 12,
                                                    fontWeight:
                                                        (typing || online)
                                                            ? FontWeight.w600
                                                            : FontWeight.normal,
                                                  ),
                                                );
                                              },
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
                            if (!_isGroup)
                              PopupMenuItem(
                                value: 'profile',
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.person_outline),
                                  title: Text(tr('عرض الملف الشخصي')),
                                ),
                              ),
                            PopupMenuItem(
                              value: 'info',
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(_isGroup
                                    ? Icons.groups_outlined
                                    : Icons.info_outline_rounded),
                                title: Text(_isGroup
                                    ? tr('معلومات المجموعة')
                                    : tr('معلومات المحادثة')),
                              ),
                            ),
                            if (!_isGroup)
                              PopupMenuItem(
                                value: 'nickname',
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.badge_outlined),
                                  title: Text(tr('الكنية')),
                                  subtitle: _nickname.isEmpty
                                      ? null
                                      : Text(_nickname,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                ),
                              ),
                            PopupMenuItem(
                              value: 'look',
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.palette_outlined,
                                    color: _look.isDefault
                                        ? null
                                        : _look.bubble),
                                title: Text(tr('ألوان المحادثة')),
                              ),
                            ),
                            if (!_isGroup)
                              PopupMenuItem(
                                value: 'vanish',
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(_vanish
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined),
                                  title: Text(_vanish
                                      ? tr('إيقاف وضع الاختفاء')
                                      : tr('وضع الاختفاء')),
                                  subtitle: _vanish
                                      ? null
                                      : Text(tr('تختفي الرسائل بعد ساعة')),
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
                            if (_isGroup)
                              PopupMenuItem(
                                value: 'leave',
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.logout_rounded,
                                      color: AppColors.likeRed),
                                  title: Text(tr('مغادرة المجموعة'),
                                      style: const TextStyle(
                                          color: AppColors.likeRed)),
                                ),
                              )
                            else
                              PopupMenuItem(
                                value: blockState.blockedByMe
                                    ? 'unblock'
                                    : 'block',
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
              body: DecoratedBox(
                decoration: _look.backgroundDecoration(colors.bg) ??
                    BoxDecoration(color: colors.bg),
                child: Column(
                children: [
                  if (blockState.blocked)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      color: colors.surfaceHigh,
                      child: Text(
                        blockState.blockedByMe
                            ? tr(
                                'حظرت هذا المستخدم. ألغِ الحظر لإرسال الرسائل.')
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
                        final now = DateTime.now();
                        final messages = _messages!
                            .where((m) =>
                                !_hidden.contains(m.id) &&
                                // وضع الاختفاء: تُخفى الرسائل المنتهية صلاحيتها.
                                (m.expiresAt == null ||
                                    m.expiresAt!.isAfter(now)) &&
                                (cleared == null ||
                                    m.createdAt.isAfter(cleared)))
                            .toList();
                        if (messages.isEmpty) {
                          if (!_isGroup) {
                            return _ChatIntroCard(otherUid: widget.otherUid);
                          }
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
                                  message.createdAt
                                      .isAfter(_readAtWhenOpened!))) {
                            unreadDividerAfter = i;
                          }
                        }
                        final unreadDividerPosition = unreadDividerAfter == null
                            ? null
                            : unreadDividerAfter + 1;
                        // الرسالة المثبّتة: تُعرض فقط إن كانت ضمن المحمّل ولم
                        // يحذفها الطرف لديّه.
                        final pinnedId =
                            (_chatData?['pinnedMessageId'] as String?) ?? '';
                        ChatMessage? pinnedMessage;
                        if (pinnedId.isNotEmpty &&
                            !_hidden.contains(pinnedId)) {
                          for (final message in messages) {
                            if (message.id == pinnedId) {
                              pinnedMessage = message;
                              break;
                            }
                          }
                        }
                        final list = ListView.builder(
                          controller: _scroll,
                          reverse: true,
                          // تمرير أنعم: يبني هامشاً من الرسائل خارج الشاشة.
                          cacheExtent: 900,
                          // مساحة أعلى القائمة تُترك لشريط الرسالة المثبّتة.
                          padding: EdgeInsetsDirectional.fromSTEB(
                              14, pinnedMessage == null ? 12 : 62, 14, 12),
                          itemCount: messages.length +
                              (unreadDividerPosition == null ? 0 : 1) +
                              (_loadingMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (_loadingMore &&
                                index ==
                                    messages.length +
                                        (unreadDividerPosition == null
                                            ? 0
                                            : 1)) {
                              return const Padding(
                                padding: EdgeInsets.all(12),
                                child: Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                ),
                              );
                            }
                            if (index == unreadDividerPosition) {
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
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
                            final messageIndex =
                                unreadDividerPosition != null &&
                                        index > unreadDividerPosition
                                    ? index - 1
                                    : index;
                            final message =
                                messages[messages.length - 1 - messageIndex];
                            final mine =
                                message.senderUid == SocialService.currentUid;
                            // رمز تعبيري واحد فقط: يُعرض كبيراً بلا فقاعة كالملصق.
                            final bigEmoji = message.kind == 'text' &&
                                !message.deleted &&
                                singleEmoji(message.text) != null;
                            final sticker =
                                message.kind == 'sticker' || bigEmoji;
                            final isGif = message.kind == 'gif' &&
                                message.gifUrl != null &&
                                !message.deleted;
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
                            // المجموعة: «شوهد بواسطة ...» بدل علامات الإيصال
                            // (كإنستغرام)، وتظهر أسفل أحدث رسالة أرسلتُها فقط.
                            final groupOthers = _isGroup
                                ? ((_chatData?['participants'] as List? ??
                                        const [])
                                    .cast<String>()
                                    .where((uid) =>
                                        uid != SocialService.currentUid)
                                    .toList())
                                : const <String>[];
                            final groupReaders = _isGroup
                                ? groupOthers.where((uid) {
                                    final at = _stampOf('readAt', uid);
                                    return message.readBy.contains(uid) ||
                                        (at != null &&
                                            !message.createdAt.isAfter(at));
                                  }).toList()
                                : const <String>[];
                            // تجميع الرسائل المتتالية لنفس المرسل (كإنستغرام):
                            // الصورة والوقت يظهران على أحدث رسالة في المجموعة فقط.
                            final newer = messageIndex >= 1
                                ? messages[messages.length - messageIndex]
                                : null;
                            final grouped = newer != null &&
                                newer.senderUid == message.senderUid &&
                                _sameDay(newer.createdAt, message.createdAt) &&
                                newer.createdAt
                                        .difference(message.createdAt)
                                        .inMinutes <
                                    5;
                            // المجموعة: اسم المرسل يظهر أعلى أول رسالة في التجميع.
                            final older = messageIndex + 1 < messages.length
                                ? messages[messages.length - 2 - messageIndex]
                                : null;
                            final startsRun = _isGroup &&
                                !mine &&
                                (older == null ||
                                    older.senderUid != message.senderUid ||
                                    !_sameDay(
                                        older.createdAt, message.createdAt) ||
                                    message.createdAt
                                            .difference(older.createdAt)
                                            .inMinutes >=
                                        5);
                            final reactionCounts = <String, int>{};
                            for (final reaction in message.reactions.values) {
                              reactionCounts.update(
                                  reaction, (count) => count + 1,
                                  ifAbsent: () => 1);
                            }
                            // رسالة صورة: تُعرض بلا فقاعة (لا خلفية ولا حشو)
                            // كإنستغرام، والنص المصاحب يظهر داخل فقاعة أسفلها.
                            final hasImage = message.kind == 'image' &&
                                (message.imageUrl != null ||
                                    message.imageBytes != null);
                            // صورة «تُعرض مرة واحدة»: لا تُعرض للمرسل، ومبهمة
                            // للمستلم حتى يفتحها.
                            final isViewOnce = hasImage && message.viewOnce;
                            final viewOnceOpened = !isViewOnce
                                ? false
                                : (mine
                                    ? message.viewedBy.any(
                                        (u) => u != SocialService.currentUid)
                                    : message.viewedBy
                                        .contains(SocialService.currentUid));
                            // مشاركة غنية (بطاقة منشور/ملف شخصي): بلا فقاعة.
                            final isShare = message.kind == 'share';
                            // رسالة محذوفة لدى الجميع: أثر «تم حذف الرسالة».
                            final isDeleted = message.deleted;
                            final isAudio = message.kind == 'audio' &&
                                message.audioUrl != null;
                            // موقع مُرسل: بطاقة بلا فقاعة (كإنستغرام).
                            final isLocation = message.kind == 'location' &&
                                message.lat != null &&
                                message.lng != null;
                            // نص افتراضي للصور بلا تعليق: لا يُعرض كتعليق.
                            final rawCaption =
                                hasImage ? message.text.trim() : '';
                            final caption = (rawCaption == '📷 صورة' ||
                                    rawCaption == '📷 Photo')
                                ? ''
                                : rawCaption;
                            final hasQuote = message.replyToMessageId != null &&
                                (message.replyToText ?? '').trim().isNotEmpty;
                            // عرض إنستغرام: الصورة تملأ عرض الفقاعة (بحد أقصى 340)
                            // حتى تندمج مع فقاعة النص بنفس العرض تماماً.
                            final fullMax = MediaQuery.sizeOf(context).width *
                                (mine ? 0.78 : 0.70);
                            final maxW = (hasImage || isShare || isLocation || isGif) &&
                                    fullMax > 340.0
                                ? 340.0
                                : fullMax;
                            final selected = _selectedIds.contains(message.id);
                            final bubble = GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              // في وضع التحديد يتولّى الصف كله النقر لتحديد الرسالة.
                              onDoubleTap: (_selecting || isDeleted)
                                  ? null
                                  : () => _quickHeart(message),
                              onLongPress: _selecting
                                  ? null
                                  : () => _showMessageActions(message, mine),
                              child: Container(
                                constraints: BoxConstraints(maxWidth: maxW),
                                margin: EdgeInsets.only(top: grouped ? 2 : 4),
                                padding: hasImage
                                    ? (hasQuote
                                        ? const EdgeInsetsDirectional.fromSTEB(
                                            6, 6, 6, 0)
                                        : EdgeInsets.zero)
                                    : (sticker || isGif || isShare || isLocation || isDeleted
                                        ? EdgeInsets.zero
                                        : const EdgeInsets.symmetric(
                                            horizontal: 13, vertical: 9)),
                                decoration: (sticker ||
                                        isGif ||
                                        hasImage ||
                                        isShare ||
                                        isLocation ||
                                        isDeleted)
                                    ? null
                                    : BoxDecoration(
                                        color: mine
                                            ? _mineColor
                                            : colors.surfaceHigh,
                                        borderRadius:
                                            BorderRadiusDirectional.only(
                                          topStart: const Radius.circular(18),
                                          topEnd: const Radius.circular(18),
                                          // ذيل الفقاعة يظهر على أحدث رسالة فقط.
                                          bottomStart: Radius.circular(
                                              mine ? 18 : (grouped ? 18 : 4)),
                                          bottomEnd: Radius.circular(
                                              mine ? (grouped ? 18 : 4) : 18),
                                        ),
                                      ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    // وسم إعادة التوجيه أعلى الفقاعة (كإنستغرام).
                                    if (message.forwarded && !hasImage)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 3),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.shortcut_rounded,
                                              size: 13,
                                              color: mine
                                                  ? Colors.white70
                                                  : colors.textDim,
                                            ),
                                            const SizedBox(width: 3),
                                            Text(
                                              tr('مُعاد توجيهه'),
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontStyle: FontStyle.italic,
                                                color: mine
                                                    ? Colors.white70
                                                    : colors.textDim,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (message.replyToMessageId != null &&
                                        (message.replyToText ?? '')
                                            .trim()
                                            .isNotEmpty)
                                      GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: NoteService.isNoteReplyId(
                                                message.replyToMessageId)
                                            ? null
                                            : () => _jumpToMessage(
                                                message.replyToMessageId!),
                                        child: Container(
                                          width: double.infinity,
                                          margin:
                                              const EdgeInsets.only(bottom: 6),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: mine
                                                ? Colors.white.withOpacity(0.12)
                                                : colors.surface,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: Border.all(
                                              color: mine
                                                  ? Colors.white
                                                      .withOpacity(0.2)
                                                  : colors.surfaceHigh,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                NoteService.isNoteReplyId(
                                                        message
                                                            .replyToMessageId)
                                                    ? tr('ردّ على ملاحظة')
                                                    : tr('ردّ على رسالة'),
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
                                                textDirection: SocialService
                                                    .inferTextDirection(
                                                        message.replyToText ??
                                                            ''),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    if (hasImage)
                                      isViewOnce
                                          ? _ViewOnceImage(
                                              url: message.imageUrl,
                                              bytes: message.imageBytes,
                                              width: maxW,
                                              mine: mine,
                                              opened: viewOnceOpened,
                                              borderRadius:
                                                  BorderRadiusDirectional.only(
                                                topStart:
                                                    const Radius.circular(18),
                                                topEnd:
                                                    const Radius.circular(18),
                                                bottomStart: Radius.circular(
                                                    caption.isEmpty ? 18 : 0),
                                                bottomEnd: Radius.circular(
                                                    caption.isEmpty ? 18 : 0),
                                              ),
                                              onReveal: () async {
                                                try {
                                                  await SocialService
                                                      .markMessageViewed(
                                                          widget.conversationId,
                                                          message.id);
                                                } catch (_) {}
                                              },
                                            )
                                          : _ChatImage(
                                              url: message.imageUrl,
                                              bytes: message.imageBytes,
                                              width: maxW,
                                              // مع نص: تندمج الصورة مع الفقاعة
                                              // أسفلها (زوايا مشتركة) كإنستغرام.
                                              borderRadius:
                                                  BorderRadiusDirectional.only(
                                                topStart:
                                                    const Radius.circular(18),
                                                topEnd:
                                                    const Radius.circular(18),
                                                bottomStart: Radius.circular(
                                                    caption.isEmpty ? 18 : 0),
                                                bottomEnd: Radius.circular(
                                                    caption.isEmpty ? 18 : 0),
                                              ),
                                              onTap: () =>
                                                  message.imageUrl != null
                                                      ? _openNetworkImage(message.imageUrl!,
                                                          senderUid:
                                                              message.senderUid,
                                                          sentAt: message
                                                              .createdAt)
                                                      : _openImage(
                                                          message.imageBytes!),
                                            )
                                    else if (isDeleted)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 13, vertical: 9),
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(18),
                                          border: Border.all(
                                              color: colors.textDim
                                                  .withOpacity(0.5)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.block_rounded,
                                                size: 15,
                                                color: colors.textDim),
                                            const SizedBox(width: 6),
                                            Text(
                                              tr('تم حذف الرسالة'),
                                              style: TextStyle(
                                                  color: colors.textDim,
                                                  fontStyle: FontStyle.italic,
                                                  fontSize: 14),
                                            ),
                                          ],
                                        ),
                                      )
                                    else if (sticker)
                                      StickerMessage(
                                        bigEmoji
                                            ? message.text.trim()
                                            : message.text,
                                        base: bigEmoji ? 72 : 56,
                                      )
                                    else if (isGif)
                                      _GifBubble(
                                        url: message.gifUrl!,
                                        width: message.gifW ?? 200,
                                        height: message.gifH ?? 200,
                                        maxWidth: maxW > 260.0 ? 260.0 : maxW,
                                      )
                                    else if (isAudio)
                                      _VoiceBubble(
                                        key: ValueKey('voice-${message.id}'),
                                        url: message.audioUrl!,
                                        seconds: message.audioSecs ?? 0,
                                        wave: message.audioWave,
                                        mine: mine,
                                      )
                                    else if (isShare)
                                      _ShareCard(
                                        message: message,
                                        mine: mine,
                                        width: maxW,
                                        onTap: () => _openShareTarget(message),
                                      )
                                    else if (isLocation)
                                      _LocationCard(
                                        message: message,
                                        mine: mine,
                                        width: maxW,
                                        onTap: () => _openLocation(message),
                                      )
                                    else
                                      Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          _messageBody(message.text,
                                              mine: mine,
                                              mentions:
                                                  message.mentions.isNotEmpty),
                                          // الرابط يتحول إلى بطاقة بعنوان وصورة.
                                          if (message.kind == 'text' &&
                                              firstLink(message.text) != null)
                                            LinkPreviewCard(
                                              key: ValueKey(
                                                  'lp-${message.id}'),
                                              url: firstLink(message.text)!,
                                              mine: mine,
                                            ),
                                        ],
                                      ),
                                    // نص مصاحب للصورة: فقاعة ملتصقة أسفلها.
                                    if (caption.isNotEmpty)
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: mine
                                              ? _mineColor
                                              : colors.surfaceHigh,
                                          borderRadius:
                                              BorderRadiusDirectional.only(
                                            bottomStart: Radius.circular(
                                                mine ? 18 : (grouped ? 18 : 4)),
                                            bottomEnd: Radius.circular(
                                                mine ? (grouped ? 18 : 4) : 18),
                                          ),
                                        ),
                                        child:
                                            _messageBody(caption, mine: mine),
                                      ),
                                    if (reactionCounts.isNotEmpty)
                                      GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () => _showReactions(message),
                                        child: Padding(
                                        padding: const EdgeInsets.only(top: 5),
                                        child: Wrap(
                                          spacing: 4,
                                          children: [
                                            for (final reaction
                                                in reactionCounts.entries)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: (sticker || hasImage)
                                                      ? colors.surfaceHigh
                                                      : (mine
                                                          ? Colors.white
                                                              .withOpacity(0.16)
                                                          : colors.surface),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  '${reaction.key} ${reaction.value}',
                                                  style: const TextStyle(
                                                      fontSize: 11),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                            // علامتا القراءة والوقت أسفل الفقاعة (خارجها).
                            final meta = Padding(
                              padding: const EdgeInsetsDirectional.only(
                                  top: 2, bottom: 4, start: 4, end: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // المجموعة: لا علامات إيصال (كإنستغرام).
                                  if (mine && !_isGroup) ...[
                                    Icon(
                                      isDelivered
                                          ? Icons.done_all_rounded
                                          : Icons.done_rounded,
                                      size: 16,
                                      // قُرئت: علامتان زرقاوان (مثل واتساب).
                                      color: isRead
                                          ? const Color(0xFF4FC3F7)
                                          : isDelivered
                                              ? colors.textDim
                                              : colors.textDim.withOpacity(0.6),
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                  if (message.edited) ...[
                                    Text(
                                      tr('معدّلة'),
                                      style: TextStyle(
                                        color: colors.textDim,
                                        fontSize: 10,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                  Text(
                                    _clock(message.createdAt),
                                    style: TextStyle(
                                      color: colors.textDim,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            );
                            final bubbleWithMeta = Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: mine
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                // اسم المرسل أعلى فقاعة المجموعة (لمن ليس أنا).
                                if (startsRun)
                                  Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                        start: 4, bottom: 2),
                                    child: _SenderName(uid: message.senderUid),
                                  ),
                                bubble,
                                // الوقت والإيصال على أحدث رسالة في المجموعة فقط.
                                if (!grouped) meta,
                                // «شوهد بواسطة ...» أسفل أحدث رسالة أرسلتُها (كإنستغرام).
                                if (mine &&
                                    _isGroup &&
                                    !grouped &&
                                    messageIndex == 0 &&
                                    groupReaders.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                        start: 4, bottom: 4),
                                    child: _SeenByLine(
                                      readers: groupReaders,
                                      total: groupOthers.length,
                                    ),
                                  ),
                              ],
                            );
                            final alignedRow = Align(
                              alignment: mine
                                  ? AlignmentDirectional.centerEnd
                                  : AlignmentDirectional.centerStart,
                              child: mine
                                  ? bubbleWithMeta
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        // الصورة تظهر لأول رسالة في المجموعة فقط،
                                        // والنقر عليها يفتح حساب المرسل.
                                        if (grouped)
                                          const SizedBox(width: 34)
                                        else
                                          Padding(
                                            padding: const EdgeInsetsDirectional
                                                .only(
                                              end: 6,
                                              bottom: 22,
                                            ),
                                            child: UserAvatar(
                                              uid: message.senderUid,
                                              radius: 14,
                                              onTap: () => openProfile(
                                                  context, message.senderUid),
                                            ),
                                          ),
                                        Flexible(child: bubbleWithMeta),
                                      ],
                                    ),
                            );
                            // السحب يميناً أو يساراً = ردّ على الرسالة (كإنستغرام)،
                            // وفي وضع التحديد يستبدل الصف بنقرة تحديد.
                            final rowBody = _selecting
                                ? GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () =>
                                        _toggleMessageSelected(message.id),
                                    child: Row(
                                      children: [
                                        Padding(
                                          padding:
                                              const EdgeInsetsDirectional.only(
                                                  start: 4, end: 8),
                                          child: Icon(
                                            selected
                                                ? Icons.check_circle_rounded
                                                : Icons.circle_outlined,
                                            size: 22,
                                            color: selected
                                                ? AppColors.brandPurple
                                                : colors.textDim,
                                          ),
                                        ),
                                        Expanded(child: alignedRow),
                                      ],
                                    ),
                                  )
                                : isDeleted
                                    ? alignedRow
                                    : _SwipeToReply(
                                    alignment: mine
                                        ? AlignmentDirectional.centerEnd
                                        : AlignmentDirectional.centerStart,
                                    onReply: () =>
                                        setState(() => _replyTarget = message),
                                    child: alignedRow,
                                  );
                            final row = KeyedSubtree(
                              key: _keyFor(message.id),
                              // عزل إعادة الرسم لكل رسالة: تمرير أنعم في القوائم الطويلة.
                              child: RepaintBoundary(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? AppColors.brandPurple
                                            .withOpacity(0.12)
                                        : (_highlightId == message.id
                                            ? AppColors.brandOrange
                                                .withOpacity(0.18)
                                            : Colors.transparent),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: rowBody,
                                ),
                              ),
                            );
                            // فاصل التاريخ فوق أول رسالة في كل يوم.
                            final previous = messageIndex + 1 < messages.length
                                ? messages[messages.length - 2 - messageIndex]
                                : null;
                            if (previous != null &&
                                _sameDay(
                                    previous.createdAt, message.createdAt)) {
                              return row;
                            }
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
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
                        return Stack(
                          children: [
                            Positioned.fill(child: list),
                            // شريط الرسالة المثبّتة أعلى القائمة (مثل إنستغرام).
                            if (pinnedMessage != null)
                              PositionedDirectional(
                                top: 0,
                                start: 0,
                                end: 0,
                                child: _PinnedMessageBanner(
                                  message: pinnedMessage,
                                  onOpen: () =>
                                      _jumpToMessage(pinnedMessage!.id),
                                  onUnpin: () => _setPinnedMessage(null),
                                ),
                              ),
                            // زر النزول لأحدث رسالة مع عدّاد الجديد.
                            if (_awayFromBottom)
                              PositionedDirectional(
                                bottom: 14,
                                end: 14,
                                child: _JumpToLatestButton(
                                  count: _newCount,
                                  onTap: _jumpToLatest,
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                  if (_typingUsers.keys
                      .any((uid) => uid != SocialService.currentUid))
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
                        child: _TypingBubble(
                          // في المجموعة: صورة آخر من يكتب فعلاً.
                          otherUid: _isGroup
                              ? _typingUsers.keys.firstWhere(
                                  (uid) => uid != SocialService.currentUid,
                                  orElse: () => widget.otherUid)
                              : widget.otherUid,
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
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
                    if (_mentionSuggestions.isNotEmpty) _buildMentionList(),
                    if (_pendingImages.isNotEmpty)
                      _PendingImagesStrip(
                        images: _pendingImages,
                        onRemove: (index) =>
                            setState(() => _pendingImages.removeAt(index)),
                      ),
                    if (_viewOnce || _vanish)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: colors.surfaceHigh,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.visibility_off_outlined,
                                size: 16, color: colors.textDim),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _viewOnce && _vanish
                                    ? tr(
                                        'الصورة ستُعرض مرة واحدة · والرسائل تختفي بعد ساعة')
                                    : _viewOnce
                                        ? tr('الصورة التالية ستُعرض مرة واحدة')
                                        : tr(
                                            'وضع الاختفاء: الرسائل تختفي بعد ساعة'),
                                style: TextStyle(
                                    color: colors.textDim, fontSize: 12),
                              ),
                            ),
                            if (_viewOnce)
                              IconButton(
                                onPressed: () =>
                                    setState(() => _viewOnce = false),
                                icon: const Icon(Icons.close_rounded, size: 16),
                                visualDensity: VisualDensity.compact,
                                tooltip: tr('إلغاء «مرة واحدة»'),
                              ),
                          ],
                        ),
                      ),
                    if (_replyTarget != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
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
                                style: TextStyle(
                                    color: colors.textDim, fontSize: 12),
                                textDirection: SocialService.inferTextDirection(
                                    _replyTarget!.text),
                              ),
                            ),
                            IconButton(
                              onPressed: () =>
                                  setState(() => _replyTarget = null),
                              icon: const Icon(Icons.close_rounded, size: 18),
                              tooltip: tr('إلغاء الرد'),
                            ),
                          ],
                        ),
                      ),
                    if (_editTarget != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        padding: const EdgeInsetsDirectional.only(
                            start: 12, top: 4, bottom: 4),
                        decoration: BoxDecoration(
                          color: colors.surfaceHigh,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.edit_rounded,
                                size: 16, color: colors.textDim),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${tr('تعديل الرسالة')}: ${_editTarget!.text}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: colors.textDim, fontSize: 12),
                                textDirection: SocialService.inferTextDirection(
                                    _editTarget!.text),
                              ),
                            ),
                            IconButton(
                              onPressed: _sending ? null : _cancelEdit,
                              icon: const Icon(Icons.close_rounded, size: 18),
                              tooltip: tr('إلغاء التعديل'),
                            ),
                          ],
                        ),
                      ),
                    SafeArea(
                      top: false,
                      bottom: !_showStickers,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
                        child: _recording && !_recHold
                            ? _buildRecordingBar()
                            : _buildComposerPill(),
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
              ),
            ));
      },
    );
  }
}

/// شريط الرسالة المثبّتة أعلى قائمة المحادثة: يفتح الرسالة أو يلغي التثبيت.
class _PinnedMessageBanner extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback onOpen;
  final VoidCallback onUnpin;

  const _PinnedMessageBanner({
    required this.message,
    required this.onOpen,
    required this.onUnpin,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final raw = message.kind == 'image'
        ? tr('صورة')
        : (message.text.trim().isEmpty ? tr('مرفق') : message.text.trim());
    return Material(
      color: colors.surface,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 4, 6),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.surfaceHigh)),
          ),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.brandPurple,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('رسالة مثبّتة'),
                      style: const TextStyle(
                        color: AppColors.brandPurple,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      raw,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.text, fontSize: 12),
                      textDirection: SocialService.inferTextDirection(raw),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: onUnpin,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(Icons.push_pin_outlined,
                      size: 18, color: colors.textDim),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// زر العودة إلى أحدث رسالة مع شارة عدد الرسائل الجديدة الواردة.
class _JumpToLatestButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _JumpToLatestButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: colors.surfaceHigh,
      elevation: 3,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.keyboard_arrow_down_rounded, color: colors.text),
              if (count > 0) ...[
                const SizedBox(width: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// السحب أفقياً على الرسالة = ردّ عليها (كإنستغرام)، مع أيقونة تظهر أثناء السحب.
class _SwipeToReply extends StatefulWidget {
  final AlignmentGeometry alignment;
  final VoidCallback onReply;
  final Widget child;

  const _SwipeToReply({
    required this.alignment,
    required this.onReply,
    required this.child,
  });

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> {
  static const double _threshold = 54;
  static const double _maxDrag = 72;
  double _drag = 0; // مقدار السحب للداخل (موجب دائماً).
  bool _triggered = false;

  /// اتجاه السحب الفيزيائي (x) الذي يُعدّ «نحو الوسط» حسب جهة الفقاعة واللغة.
  double _inwardSign(BuildContext context) {
    final mine = widget.alignment == AlignmentDirectional.centerEnd;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return (mine ? -1.0 : 1.0) * (rtl ? -1.0 : 1.0);
  }

  void _update(BuildContext context, double dx) {
    if (_triggered) return;
    final inward = dx * _inwardSign(context);
    final next = (_drag + inward).clamp(0.0, _maxDrag).toDouble();
    if (next == _drag) return;
    setState(() => _drag = next);
    if (_drag >= _threshold) {
      _triggered = true;
      HapticFeedback.selectionClick();
      widget.onReply();
    }
  }

  void _reset() {
    if (_drag == 0 && !_triggered) return;
    setState(() {
      _drag = 0;
      _triggered = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // الأيقونة تظهر في الجهة المقابلة للفقاعة (حيث تتكوّن المساحة).
    final iconAlignment = widget.alignment == AlignmentDirectional.centerEnd
        ? AlignmentDirectional.centerStart
        : AlignmentDirectional.centerEnd;
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onHorizontalDragUpdate: (details) => _update(context, details.delta.dx),
      onHorizontalDragEnd: (_) => _reset(),
      onHorizontalDragCancel: _reset,
      child: Stack(
        alignment: iconAlignment,
        children: [
          Opacity(
            opacity: (_drag / _threshold).clamp(0.0, 1.0),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.brandPurple.withOpacity(0.15),
              ),
              child: const Icon(Icons.reply_rounded,
                  size: 18, color: AppColors.brandPurple),
            ),
          ),
          Transform.translate(
            offset: Offset(_drag * _inwardSign(context), 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

/// معلومات المحادثة: ملف الطرف الآخر + شبكة الصور المشتركة (كإنستغرام).
class ChatInfoScreen extends StatelessWidget {
  final String conversationId;
  final String otherUid;

  const ChatInfoScreen({
    super.key,
    required this.conversationId,
    required this.otherUid,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(title: Text(tr('معلومات المحادثة'))),
      body: StreamBuilder<AppUser?>(
        stream: UserService.profileStream(otherUid),
        builder: (context, snapshot) {
          final user = snapshot.data;
          return ListView(
            children: [
              const SizedBox(height: 18),
              Center(
                child: UserAvatar(
                  uid: otherUid,
                  fallbackName: user?.username ?? '',
                  radius: 44,
                  profile: user,
                  onTap: () => openProfile(context, otherUid),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  user?.displayName ?? '',
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if ((user?.username ?? '').isNotEmpty) ...[
                const SizedBox(height: 3),
                Center(
                  child: Text(
                    '@${user!.username}',
                    style: TextStyle(color: colors.textDim, fontSize: 13),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: OutlinedButton.icon(
                  onPressed: () => openProfile(context, otherUid),
                  icon: const Icon(Icons.person_outline, size: 18),
                  label: Text(tr('عرض الملف الشخصي')),
                ),
              ),
              const SizedBox(height: 22),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.photo_library_outlined,
                        size: 18, color: colors.textDim),
                    const SizedBox(width: 8),
                    Text(
                      tr('الصور في المحادثة'),
                      style: TextStyle(
                          color: colors.text, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              _ChatMediaGrid(conversationId: conversationId),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

/// شاشة معلومات المجموعة: تعديل الاسم/الصورة وإدارة الأعضاء والمشرفين.
class _GroupInfoScreen extends StatefulWidget {
  final String conversationId;

  /// آخر نسخة معروفة من مستند المحادثة (لتجنّب انتظار أول تحديث).
  final Map<String, dynamic>? data;

  const _GroupInfoScreen({required this.conversationId, this.data});

  @override
  State<_GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<_GroupInfoScreen> {
  final _picker = ImagePicker();
  StreamSubscription<Map<String, dynamic>?>? _sub;
  Map<String, dynamic>? _data;
  bool _busy = false;

  String get _me => SocialService.currentUid;

  @override
  void initState() {
    super.initState();
    _data = widget.data;
    _sub = SocialService.chatStream(widget.conversationId).listen((data) {
      if (mounted && data != null) setState(() => _data = data);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  List<String> get _participants =>
      ((_data?['participants'] as List?) ?? const []).cast<String>();

  List<String> get _admins =>
      ((_data?['admins'] as List?) ?? const []).cast<String>();

  String get _createdBy => (_data?['createdBy'] as String?) ?? '';
  String get _name => ((_data?['groupName'] as String?) ?? '').trim();
  String get _photo => ((_data?['groupPhoto'] as String?) ?? '').trim();

  /// أنا مشرف؟ (المنشئ مشرف دائماً.)
  bool get _iAmAdmin => _createdBy == _me || _admins.contains(_me);

  /// ترتيب الأعضاء: المنشئ أولاً ثم المشرفون ثم البقية.
  List<String> get _sortedMembers {
    int rank(String uid) {
      if (uid == _createdBy) return 0;
      return _admins.contains(uid) ? 1 : 2;
    }

    final list = [..._participants];
    list.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : a.compareTo(b);
    });
    return list;
  }

  Future<void> _run(Future<void> Function() action, String failure) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(error, fallback: failure))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: _name);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('اسم المجموعة')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: SocialService.groupNameMax,
          decoration: InputDecoration(hintText: tr('اسم المجموعة')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(tr('إلغاء')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: Text(tr('حفظ')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty || value == _name) return;
    await _run(() => SocialService.setGroupName(widget.conversationId, value),
        tr('تعذر تعديل اسم المجموعة'));
  }

  Future<void> _changePhoto() async {
    final picked =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 88);
    if (picked == null) return;
    await _run(() async {
      final bytes = await fitImageUnderLimit(await picked.readAsBytes());
      final url = await PostService.uploadChatImage(bytes);
      if (url == null) {
        throw StateError(
            tr('تغيير صورة المجموعة يتطلب تفعيل Cloudinary أو Storage'));
      }
      await SocialService.setGroupPhoto(widget.conversationId, url);
    }, tr('تعذر تغيير صورة المجموعة'));
  }

  Future<void> _addMembers() async {
    await Navigator.of(context).push<bool>(appRoute(
      'groupAdd',
      {'cid': widget.conversationId},
      (_) => _AddGroupMembersScreen(
        conversationId: widget.conversationId,
        existing: _participants,
      ),
    ));
  }

  Future<void> _toggleAdmin(String uid) async {
    final admin = !_admins.contains(uid);
    await _run(
      () => SocialService.setGroupAdmin(widget.conversationId, uid, admin),
      admin ? tr('تعذر ترقية العضو') : tr('تعذر إزالة الإشراف'),
    );
  }

  Future<void> _removeMember(String uid) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('إزالة العضو؟')),
        content: Text(tr('سيخرج هذا العضو من المجموعة.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr('إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr('إزالة')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(
        () => SocialService.removeGroupMember(widget.conversationId, uid),
        tr('تعذر إزالة العضو'));
  }

  Future<void> _leave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('مغادرة المجموعة؟')),
        content: Text(tr('لن تستقبل رسائل هذه المجموعة بعد الآن.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr('إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr('مغادرة')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await SocialService.leaveGroup(widget.conversationId);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                friendlyError(error, fallback: tr('تعذر مغادرة المجموعة')))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (_data == null) {
      return Scaffold(
        backgroundColor: colors.bg,
        appBar: AppBar(title: Text(tr('معلومات المجموعة'))),
        body: const AppLoading(),
      );
    }
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(title: Text(tr('معلومات المجموعة'))),
      body: ListView(
        children: [
          const SizedBox(height: 18),
          Center(
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                _GroupPhoto(
                  participants: _participants,
                  photoUrl: _photo,
                  size: 88,
                  onTap: _iAmAdmin && !_busy ? _changePhoto : null,
                ),
                if (_iAmAdmin)
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.surface,
                      border: Border.all(color: colors.surfaceHigh, width: 2),
                    ),
                    child: Icon(Icons.photo_camera_outlined,
                        size: 16, color: colors.text),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              _name.isEmpty ? tr('مجموعة') : _name,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.text,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Center(
            child: Text(
              trf('{0} عضو', [_participants.length]),
              style: TextStyle(color: colors.textDim, fontSize: 13),
            ),
          ),
          if (_iAmAdmin) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _editName,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(tr('تعديل اسم المجموعة')),
              ),
            ),
          ],
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 8, 8),
            child: Row(
              children: [
                Icon(Icons.people_outline_rounded,
                    size: 18, color: colors.textDim),
                const SizedBox(width: 8),
                Text(
                  tr('الأعضاء'),
                  style: TextStyle(
                      color: colors.text, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (_iAmAdmin)
                  TextButton.icon(
                    onPressed: _busy ? null : _addMembers,
                    icon: const Icon(Icons.person_add_alt_1, size: 18),
                    label: Text(tr('إضافة')),
                  ),
              ],
            ),
          ),
          for (final uid in _sortedMembers)
            _GroupMemberTile(
              uid: uid,
              isAdmin: _admins.contains(uid),
              isCreator: uid == _createdBy,
              // المنشئ لا يرقّي/يُزال.
              canManage: _iAmAdmin && uid != _createdBy && uid != _me,
              onToggleAdmin: () => _toggleAdmin(uid),
              onRemove: () => _removeMember(uid),
            ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: AppColors.likeRed),
            title: Text(tr('مغادرة المجموعة'),
                style: const TextStyle(color: AppColors.likeRed)),
            onTap: _busy ? null : _leave,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// صف عضو في مجموعة: الاسم والدور وقائمة إدارة (ترقية/إزالة).
class _GroupMemberTile extends StatelessWidget {
  final String uid;
  final bool isAdmin;
  final bool isCreator;
  final bool canManage;
  final VoidCallback? onToggleAdmin;
  final VoidCallback? onRemove;

  const _GroupMemberTile({
    required this.uid,
    required this.isAdmin,
    required this.isCreator,
    required this.canManage,
    this.onToggleAdmin,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final me = SocialService.currentUid;
    return FutureBuilder<AppUser?>(
      future: UserService.profileOf(uid),
      builder: (context, snapshot) {
        final user = snapshot.data;
        final name = user?.displayName ?? tr('مستخدم');
        return ListTile(
          leading: UserAvatar(
            uid: uid,
            fallbackName: user?.username ?? '',
            radius: 22,
            onTap: () => openProfile(context, uid),
          ),
          title: Text(
            uid == me ? '$name · ${tr('أنت')}' : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            isCreator
                ? tr('المنشئ')
                : isAdmin
                    ? tr('مشرف')
                    : '@${user?.username ?? ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textDim),
          ),
          trailing: canManage
              ? PopupMenuButton<String>(
                  tooltip: tr('إدارة العضو'),
                  onSelected: (value) {
                    if (value == 'admin') onToggleAdmin?.call();
                    if (value == 'remove') onRemove?.call();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'admin',
                      child: Text(
                          isAdmin ? tr('إزالة الإشراف') : tr('ترقية إلى مشرف')),
                    ),
                    PopupMenuItem(
                      value: 'remove',
                      child: Text(tr('إزالة من المجموعة'),
                          style: const TextStyle(color: AppColors.likeRed)),
                    ),
                  ],
                )
              : null,
        );
      },
    );
  }
}

/// شاشة إضافة أعضاء إلى مجموعة (من الأصدقاء المتبادلين غير الموجودين).
class _AddGroupMembersScreen extends StatefulWidget {
  final String conversationId;
  final List<String> existing;

  const _AddGroupMembersScreen(
      {required this.conversationId, required this.existing});

  @override
  State<_AddGroupMembersScreen> createState() => _AddGroupMembersScreenState();
}

class _AddGroupMembersScreenState extends State<_AddGroupMembersScreen> {
  final Set<String> _selected = <String>{};
  bool _busy = false;
  late Future<List<AppUser>> _friends = _load();

  Future<List<AppUser>> _load() async {
    final ids = await SocialService.mutualFriendIds();
    final users = await Future.wait(ids.map(UserService.profileOf));
    return users
        .whereType<AppUser>()
        .where((user) => !widget.existing.contains(user.uid))
        .toList();
  }

  Future<void> _add() async {
    if (_selected.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await SocialService.addGroupMembers(
          widget.conversationId, _selected.toList());
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                friendlyError(error, fallback: tr('تعذر إضافة الأعضاء')))));
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: Text(tr('إضافة أعضاء')),
        actions: [
          TextButton(
            onPressed: (_busy || _selected.isEmpty) ? null : _add,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(tr('إضافة')),
          ),
        ],
      ),
      body: FutureBuilder<List<AppUser>>(
        future: _friends,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(
                error: snapshot.error,
                title: tr('تعذر تحميل قائمة الأصدقاء'),
                onRetry: () => setState(() => _friends = _load()));
          }
          if (!snapshot.hasData) return const AppLoading();
          final friends = snapshot.data!;
          if (friends.isEmpty) {
            return _MessageState(
              message: tr('لا يوجد أصدقاء متبادلون لإضافتهم'),
              icon: Icons.person_add_alt_1_outlined,
            );
          }
          return ListView.builder(
            itemCount: friends.length,
            itemBuilder: (context, index) {
              final friend = friends[index];
              final checked = _selected.contains(friend.uid);
              return CheckboxListTile(
                value: checked,
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                          if (value == true) {
                            _selected.add(friend.uid);
                          } else {
                            _selected.remove(friend.uid);
                          }
                        }),
                controlAffinity: ListTileControlAffinity.trailing,
                secondary: UserAvatar(
                  uid: friend.uid,
                  fallbackName: friend.username,
                  radius: 22,
                ),
                title: Text(friend.displayName,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('@${friend.username}',
                    style: TextStyle(color: colors.textDim)),
              );
            },
          );
        },
      ),
    );
  }
}

/// شبكة الصور المتبادلة في المحادثة (الأحدث أولاً).
class _ChatMediaGrid extends StatefulWidget {
  final String conversationId;
  const _ChatMediaGrid({required this.conversationId});

  @override
  State<_ChatMediaGrid> createState() => _ChatMediaGridState();
}

class _ChatMediaGridState extends State<_ChatMediaGrid> {
  late final Future<List<ChatMessage>> _future =
      SocialService.chatImages(widget.conversationId);

  void _open(ChatMessage message) {
    final url = message.imageUrl;
    if (url != null && url.isNotEmpty) {
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => _NetworkImageViewer(
              url: url,
              senderUid: message.senderUid,
              sentAt: message.createdAt),
        ),
      );
      return;
    }
    final bytes = message.imageBytes;
    if (bytes != null) openFullScreenImage(context, bytes);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return FutureBuilder<List<ChatMessage>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text(tr('تعذر تحميل الوسائط'),
                  style: TextStyle(color: colors.textDim)),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final images = snapshot.data!
            .where((m) =>
                !m.viewOnce &&
                ((m.imageUrl != null && m.imageUrl!.isNotEmpty) ||
                    m.imageBytes != null))
            .toList();
        if (images.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text(tr('لا توجد صور بعد'),
                  style: TextStyle(color: colors.textDim)),
            ),
          );
        }
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: images.length,
          itemBuilder: (context, index) {
            final message = images[index];
            final url = message.imageUrl;
            return GestureDetector(
              onTap: () => _open(message),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: (url != null && url.isNotEmpty)
                    ? Image.network(
                        PostService.optimizedImageUrl(url, 400),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Container(color: colors.surfaceHigh),
                      )
                    : Image.memory(message.imageBytes!, fit: BoxFit.cover),
              ),
            );
          },
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
    if (needsLogin(context)) return;
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
        content: Text(tr(
            'سيتمكن هذا المستخدم من مراسلتك مجدداً إذا كنتما تتابعان بعضكما.')),
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

/// فقاعة GIF: تُحجز مساحتها من الأبعاد المحفوظة فلا يقفز التمرير أثناء التحميل.
class _GifBubble extends StatelessWidget {
  final String url;
  final int width;
  final int height;
  final double maxWidth;

  const _GifBubble({
    required this.url,
    required this.width,
    required this.height,
    required this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final w = width < 1 ? 200 : width;
    final h = height < 1 ? 200 : height;
    // أقصى ارتفاع 300 حتى لا تملأ الصور الطويلة الشاشة.
    var boxW = maxWidth;
    var boxH = boxW * h / w;
    if (boxH > 300) {
      boxH = 300;
      boxW = boxH * w / h;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: boxW,
        height: boxH,
        color: colors.surfaceHigh,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => Center(
            child: Icon(Icons.gif_box_outlined, color: colors.textDim),
          ),
        ),
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

/// بطاقة تظهر في محادثة فردية فارغة: صورة الطرف الآخر واسمه ونصائح السلامة.
class _ChatIntroCard extends StatelessWidget {
  final String otherUid;

  const _ChatIntroCard({required this.otherUid});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final tips = [
      tr('لا تشارك كلمة المرور أو رموز التحقق مع أي شخص.'),
      tr('احذر الروابط والطلبات المالية من حسابات لا تعرفها.'),
      tr('لا ترسل صوراً خاصة لمن لا تثق به.'),
      tr('يمكنك حظر الحساب أو الإبلاغ عنه في أي وقت.'),
    ];
    return FutureBuilder<AppUser?>(
      future: UserService.profileOf(otherUid),
      builder: (context, snapshot) {
        final user = snapshot.data;
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                UserAvatar(
                  uid: otherUid,
                  fallbackName: user?.username ?? '',
                  profile: user,
                  radius: 44,
                ),
                const SizedBox(height: 12),
                Text(
                  user?.displayName ?? tr('مستخدم'),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700),
                ),
                if (user != null && user.username.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('@${user.username}',
                        style: TextStyle(color: colors.textDim)),
                  ),
                const SizedBox(height: 14),
                Text(
                  tr('أرسل أول رسالة لبدء المحادثة'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textDim),
                ),
                const SizedBox(height: 22),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    tr('نصائح متعلقة بالسلامة'),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 8),
                for (final tip in tips)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.shield_outlined,
                            size: 15, color: colors.textDim),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(tip,
                              style: TextStyle(
                                  fontSize: 12.5, color: colors.textDim)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// ورقة اختيار المحادثات لإعادة توجيه رسالة أو أكثر إليها (اختيار متعدد
/// كإنستغرام).
class _ForwardSheet extends StatefulWidget {
  final List<ChatMessage> messages;
  final String exceptConversationId;

  const _ForwardSheet({
    required this.messages,
    required this.exceptConversationId,
  });

  @override
  State<_ForwardSheet> createState() => _ForwardSheetState();
}

class _ForwardSheetState extends State<_ForwardSheet> {
  final Set<String> _selected = <String>{};
  bool _sending = false;

  Future<void> _send() async {
    if (_selected.isEmpty || _sending) return;
    setState(() => _sending = true);
    final targets = _selected.toList();
    final messenger = ScaffoldMessenger.of(context);
    var sent = 0;
    Object? error;
    for (final conversationId in targets) {
      try {
        for (final message in widget.messages) {
          await SocialService.forwardMessage(conversationId, message);
        }
        sent++;
      } catch (failure) {
        error = failure;
      }
    }
    if (!mounted) return;
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(
      content: Text(sent == 0
          ? friendlyError(error, fallback: tr('تعذر إعادة التوجيه'))
          : sent == 1
              ? tr('تمت إعادة التوجيه')
              : '${tr('تمت إعادة التوجيه')} ($sent)'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(tr('إعادة التوجيه إلى'),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              if (_selected.isNotEmpty)
                TextButton(
                  onPressed: _sending ? null : _send,
                  child: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text('${tr('إرسال')} (${_selected.length})'),
                ),
            ],
          ),
        ),
        Divider(height: 1, color: colors.surfaceHigh),
        Flexible(
          child: StreamBuilder<List<Conversation>>(
            stream: SocialService.conversations(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return SizedBox(
                  height: 220,
                  child: ErrorState(
                      error: snapshot.error, title: tr('تعذر تحميل الرسائل')),
                );
              }
              if (!snapshot.hasData) {
                return const SizedBox(height: 220, child: AppLoading());
              }
              final items = snapshot.data!
                  .where((conversation) =>
                      conversation.visibleFor(SocialService.currentUid) &&
                      conversation.id != widget.exceptConversationId)
                  .toList();
              if (items.isEmpty) {
                return SizedBox(
                  height: 220,
                  child: _MessageState(
                    message: tr('لا توجد محادثات أخرى'),
                    icon: Icons.chat_bubble_outline_rounded,
                  ),
                );
              }
              return ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final conversation = items[index];
                  final otherUid =
                      conversation.otherParticipant(SocialService.currentUid);
                  final selected = _selected.contains(conversation.id);
                  return FutureBuilder<AppUser?>(
                    future: UserService.profileOf(otherUid),
                    builder: (context, userSnapshot) {
                      final user = userSnapshot.data;
                      return ListTile(
                        leading: UserAvatar(
                          uid: otherUid,
                          fallbackName: user?.username ?? '',
                          profile: user,
                          radius: 22,
                        ),
                        title: Text(
                          user?.displayName ?? tr('مستخدم'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Icon(
                          selected
                              ? Icons.check_circle_rounded
                              : Icons.circle_outlined,
                          color:
                              selected ? AppColors.brandPurple : colors.textDim,
                        ),
                        onTap: () => setState(() {
                          if (!_selected.remove(conversation.id)) {
                            _selected.add(conversation.id);
                          }
                        }),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// بطاقة مشاركة غنية داخل المحادثة (منشور/ملف شخصي) قابلة للنقر.
class _ShareCard extends StatelessWidget {
  final ChatMessage message;
  final bool mine;
  final double width;
  final VoidCallback onTap;
  const _ShareCard({
    required this.message,
    required this.mine,
    required this.width,
    required this.onTap,
  });

  /// بطاقة ردّ/تفاعل على قصة: معاينة القصة (صورة أو مقتطف نص) ثم نص الردّ.
  Widget _storyReplyCard(BuildContext context, String? image, String caption) {
    final colors = context.appColors;
    final text = message.text.trim();
    final isReaction = text.runes.length <= 4 &&
        !RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(text);
    final label = isReaction
        ? (mine ? tr('تفاعلك على القصة') : tr('تفاعل على قصتك'))
        : (mine ? tr('ردّك على القصة') : tr('ردّ على قصتك'));
    final hasImage = image != null && image.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: mine ? colors.surface : colors.surfaceHigh,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: mine
                ? AppColors.brandPurple.withOpacity(0.7)
                : colors.surfaceHigh,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.auto_stories_rounded,
                      size: 15, color: colors.textDim),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: colors.textDim,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            if (hasImage)
              Image.network(
                PostService.optimizedImageUrl(image, 400),
                width: double.infinity,
                height: 150,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              )
            else
              Container(
                width: double.infinity,
                height: 90,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(gradient: storyGradient(null)),
                child: Text(
                  caption.isEmpty ? tr('قصة') : caption,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(
                text,
                textDirection: SocialService.inferTextDirection(text),
                style: TextStyle(
                  color: colors.text,
                  fontSize: isReaction ? 30 : 15,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final image = message.shareImage;
    final subtitle = (message.shareSubtitle ?? '').trim();
    final isProfile = message.shareType == 'profile';
    if (message.shareType == 'story') {
      return _storyReplyCard(context, image, subtitle);
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: mine ? colors.surface : colors.surfaceHigh,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: mine
                ? AppColors.brandPurple.withOpacity(0.7)
                : colors.surfaceHigh,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    isProfile ? Icons.person_rounded : Icons.grid_on_rounded,
                    size: 15,
                    color: colors.textDim,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      message.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (image != null && image.isNotEmpty)
              GestureDetector(
                onTap: onTap,
                child: Image.network(
                  PostService.optimizedImageUrl(image, 600),
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            if (subtitle.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textDim, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// بطاقة موقع داخل المحادثة (كإنستغرام): تُفتح في خرائط جوجل بالنقر.
class _LocationCard extends StatelessWidget {
  final ChatMessage message;
  final bool mine;
  final double width;
  final VoidCallback onTap;
  const _LocationCard({
    required this.message,
    required this.mine,
    required this.width,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final lat = message.lat ?? 0;
    final lng = message.lng ?? 0;
    final label = message.text.trim();
    final showLabel = label.isNotEmpty && label != tr('📍 موقع');
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: mine ? colors.surface : colors.surfaceHigh,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: mine
                ? AppColors.brandPurple.withOpacity(0.7)
                : colors.surfaceHigh,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              height: 150,
              color: colors.surfaceHigh,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.map_rounded, size: 56, color: colors.textDim),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  Icon(Icons.location_on_rounded,
                      size: 16, color: AppColors.brandPurple),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      showLabel ? label : tr('📍 موقع'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    tr('فتح'),
                    style: TextStyle(
                      color: AppColors.brandPurple,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// صورة داخل المحادثة: بلا إطار (كإنستغرام)، تحافظ على نسبة الأبعاد مع حدّ
/// أقصى للارتفاع، وتعود للرابط الأصلي إن فشل الرابط المُحسَّن.
class _ChatImage extends StatelessWidget {
  final String? url;
  final Uint8List? bytes;
  final double width;
  final BorderRadiusGeometry borderRadius;
  final VoidCallback onTap;
  const _ChatImage({
    this.url,
    this.bytes,
    required this.width,
    required this.borderRadius,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final maxHeight = (MediaQuery.sizeOf(context).height * 0.6)
        .clamp(240.0, 460.0)
        .toDouble();
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
        onError: () =>
            optimized == raw ? failed() : network(raw, onError: failed),
      );
    } else {
      image = Image.memory(bytes!, width: width, fit: BoxFit.cover);
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: image,
        ),
      ),
    );
  }
}

/// صورة «تُعرض مرة واحدة»: تظهر مبهمة للمستلم حتى يضغطها فيُسجَّل فتحها
/// وتُعرض لثوانٍ ثم تختفي. المرسل لا يرى الصورة بعد الإرسال (كإنستغرام).
class _ViewOnceImage extends StatefulWidget {
  final String? url;
  final Uint8List? bytes;
  final double width;
  final bool mine;
  final bool opened;
  final BorderRadiusGeometry borderRadius;
  final VoidCallback onReveal;

  const _ViewOnceImage({
    this.url,
    this.bytes,
    required this.width,
    required this.mine,
    required this.opened,
    required this.borderRadius,
    required this.onReveal,
  });

  @override
  State<_ViewOnceImage> createState() => _ViewOnceImageState();
}

class _ViewOnceImageState extends State<_ViewOnceImage> {
  bool _revealed = false;
  bool _consumed = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _reveal() async {
    if (widget.mine || widget.opened || _revealed || _consumed) return;
    setState(() => _revealed = true);
    widget.onReveal();
    // تُفتح بملء الشاشة وتبقى حتى يغلقها المستلم، ثم تُقفل نهائياً.
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              tooltip: tr('إغلاق'),
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            ),
          ),
          body: SizedBox.expand(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Center(
                child: widget.url != null
                    ? Image.network(widget.url!, fit: BoxFit.contain)
                    : Image.memory(widget.bytes!, fit: BoxFit.contain),
              ),
            ),
          ),
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _revealed = false;
      _consumed = true;
    });
  }

  Widget _rawImage({double? height}) {
    final w = widget.width;
    if (widget.url != null) {
      final optimized = PostService.optimizedImageUrl(widget.url!, 800);
      return Image.network(
        optimized,
        width: w,
        height: height,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : SizedBox(
                width: w,
                height: height ?? 200,
                child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
        errorBuilder: (context, _, __) => SizedBox(
          width: w,
          height: height ?? 120,
          child: const Center(child: Icon(Icons.broken_image_outlined)),
        ),
      );
    }
    return Image.memory(widget.bytes!,
        width: w, height: height, fit: BoxFit.cover);
  }

  Widget _hint(IconData icon, String label, Color color) => SizedBox(
        width: widget.width,
        height: 190,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.06),
            borderRadius: widget.borderRadius,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32, color: color),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: color, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // المرسل: لا يرى المحتوى، فقط حالة الفتح.
    if (widget.mine) {
      return _hint(
        widget.opened
            ? Icons.visibility_outlined
            : Icons.visibility_off_outlined,
        widget.opened
            ? tr('فتح المستلم الصورة')
            : tr('صورة مرة واحدة · لم تُفتح بعد'),
        colors.textDim,
      );
    }
    // المستلم: بعد الفتح مرة واحدة تُقفل نهائياً.
    if (widget.opened || _consumed) {
      return _hint(
          Icons.visibility_off_outlined, tr('انتهت الصورة'), colors.textDim);
    }
    if (_revealed) {
      final maxHeight = (MediaQuery.sizeOf(context).height * 0.6)
          .clamp(240.0, 460.0)
          .toDouble();
      return ClipRRect(
        borderRadius: widget.borderRadius,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: _rawImage(),
        ),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _reveal,
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: SizedBox(
          width: widget.width,
          height: 190,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: _rawImage(height: 190),
              ),
              Container(color: Colors.black.withOpacity(0.28)),
              const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.touch_app_outlined, color: Colors.white, size: 30),
                  SizedBox(height: 6),
                ],
              ),
              Center(
                child: Text(
                  tr('اضغط للعرض مرة واحدة'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// عرض الصورة بملء الشاشة (رابط) بأسلوب إنستغرام: اسم المرسل ووقت الإرسال،
/// تكبير بالقرص، إغلاق بالسحب للأسفل، وقائمة ⋮ لحفظ الصورة.
class _NetworkImageViewer extends StatefulWidget {
  final String url;
  final String? senderUid;
  final DateTime? sentAt;
  const _NetworkImageViewer({required this.url, this.senderUid, this.sentAt});

  @override
  State<_NetworkImageViewer> createState() => _NetworkImageViewerState();
}

class _NetworkImageViewerState extends State<_NetworkImageViewer> {
  final TransformationController _transform = TransformationController();
  Offset? _downPosition;
  int _pointers = 0;
  bool _multiTouch = false;
  double _dragDy = 0;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  bool get _zoomed => _transform.value.getMaxScaleOnAxis() > 1.02;

  void _showMore() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: Text(tr('حفظ في الجهاز')),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final messenger = ScaffoldMessenger.of(context);
                final ok = await saveImageFromUrl(widget.url);
                messenger.showSnackBar(SnackBar(
                    content: Text(
                        ok ? tr('تم حفظ الصورة') : tr('تعذر حفظ الصورة'))));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _title() {
    final uid = widget.senderUid;
    final time = widget.sentAt;
    if (uid == null && time == null) return const SizedBox.shrink();
    return FutureBuilder<AppUser?>(
      future: uid == null ? null : UserService.profileOf(uid),
      builder: (context, snapshot) {
        final name = snapshot.data?.name ?? '';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (name.isNotEmpty)
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
            if (time != null)
              Text(timeAgo(time),
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.url;
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
        titleSpacing: 0,
        title: _title(),
        leading: IconButton(
          tooltip: tr('إغلاق'),
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            tooltip: tr('المزيد'),
            icon: const Icon(Icons.more_vert_rounded),
            onPressed: _showMore,
          ),
        ],
      ),
      body: Listener(
        onPointerDown: (e) {
          _pointers++;
          if (_pointers > 1) _multiTouch = true;
          if (_pointers == 1) {
            _downPosition = e.position;
            _multiTouch = false;
            _dragDy = 0;
          }
        },
        onPointerMove: (e) {
          if (_downPosition != null) _dragDy = e.position.dy - _downPosition!.dy;
        },
        onPointerUp: (e) {
          _pointers = (_pointers - 1).clamp(0, 10);
          if (_pointers == 0) {
            if (!_multiTouch && !_zoomed && _dragDy > 120 && mounted) {
              Navigator.of(context).pop();
            }
            _downPosition = null;
          }
        },
        onPointerCancel: (_) {
          _pointers = (_pointers - 1).clamp(0, 10);
          if (_pointers == 0) _downPosition = null;
        },
        child: SizedBox.expand(
          child: InteractiveViewer(
            transformationController: _transform,
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
    final size = MediaQuery.sizeOf(context);
    final height = (size.height * 0.42).clamp(260.0, 420.0).toDouble();
    final single = images.length == 1;
    final itemWidth = single ? size.width - 28 : size.width * 0.72;
    return SizedBox(
      height: height + 14,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
        itemCount: images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) => SizedBox(
          width: itemWidth,
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    color: Colors.black,
                    child: Image.memory(images[index], fit: BoxFit.contain),
                  ),
                ),
              ),
              PositionedDirectional(
                top: 8,
                end: 8,
                child: GestureDetector(
                  onTap: () => onRemove(index),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(
                        color: Colors.black87, shape: BoxShape.circle),
                    child: const Icon(Icons.close_rounded,
                        size: 20, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// فقاعة «يكتب الآن» مثل إنستغرام: صورة الشخص مع ثلاث نقاط متحركة.
class _TypingBubble extends StatefulWidget {
  final String otherUid;
  const _TypingBubble({required this.otherUid});

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        UserAvatar(uid: widget.otherUid, radius: 12),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: colors.surfaceHigh,
            borderRadius: BorderRadius.circular(18),
          ),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final t = (_controller.value + i * 0.18) % 1.0;
                final wave =
                    Curves.easeInOut.transform(t < 0.5 ? t * 2 : 2 - t * 2);
                return Container(
                  width: 7,
                  height: 7,
                  margin: EdgeInsets.only(left: i == 0 ? 0 : 4),
                  transform: Matrix4.translationValues(0, -4 * wave, 0),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.textDim.withOpacity(0.45 + 0.45 * wave),
                  ),
                );
              }),
            ),
          ),
        ),
      ],
    );
  }
}


/// فقاعة رسالة صوتية: زر تشغيل/إيقاف + موجة صوتية تتلوّن مع التقدم + المدة
/// + سرعة التشغيل (1x / 1.5x / 2x).
class _VoiceBubble extends StatefulWidget {
  final String url;
  final int seconds;
  final String? wave;
  final bool mine;
  const _VoiceBubble({
    super.key,
    required this.url,
    required this.seconds,
    required this.mine,
    this.wave,
  });

  @override
  State<_VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<_VoiceBubble> {
  VoicePlayer? _player;
  double _speed = 1;
  late final List<double> _bars = _parseBars();

  /// أعمدة الموجة من الرقم المخزّن، أو شكل ثابت مشتق من الرابط للرسائل
  /// القديمة التي بلا موجة.
  List<double> _parseBars() {
    final w = widget.wave ?? '';
    if (w.length >= 8) {
      return [for (final c in w.codeUnits) ((c - 48).clamp(0, 9)) / 9];
    }
    var h = 7;
    for (final c in widget.url.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return [
      for (var i = 0; i < 40; i++)
        0.25 + 0.75 * (((h = (h * 1103515245 + 12345) & 0x7fffffff) >> 8) % 100) / 100,
    ];
  }

  VoicePlayer _ensurePlayer() {
    var player = _player;
    if (player == null) {
      player = VoicePlayer(widget.url);
      player.addListener(_onTick);
      _player = player;
    }
    return player;
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  Future<void> _toggle() async {
    if (!VoicePlayer.supported) {
      await launchUrl(Uri.parse(widget.url),
          mode: LaunchMode.externalApplication);
      return;
    }
    try {
      final player = _ensurePlayer();
      player.speed = _speed;
      await player.toggle();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('تعذر تشغيل الرسالة الصوتية'))),
        );
      }
    }
  }

  void _cycleSpeed() {
    setState(() {
      _speed = _speed == 1 ? 1.5 : (_speed == 1.5 ? 2 : 1);
    });
    _player?.speed = _speed;
  }

  @override
  void dispose() {
    _player?.removeListener(_onTick);
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final fg = widget.mine ? Colors.white : colors.text;
    final total = widget.seconds < 1 ? 1 : widget.seconds;
    final player = _player;
    final playing = player?.playing ?? false;
    final pos = player?.position ?? 0.0;
    final progress = (pos / total).clamp(0.0, 1.0);
    final shown = playing || pos > 0 ? pos.floor() : total;
    final label =
        '${shown ~/ 60}:${(shown % 60).toString().padLeft(2, '0')}';
    final speedLabel = _speed == 1 ? '1x' : (_speed == 1.5 ? '1.5x' : '2x');
    return SizedBox(
      width: 236,
      child: Row(
        children: [
          InkWell(
            customBorder: const CircleBorder(),
            onTap: _toggle,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.mine
                    ? Colors.white.withOpacity(0.2)
                    : colors.surface,
              ),
              child: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: fg),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 28,
              child: CustomPaint(
                painter: _WavePainter(
                  bars: _bars,
                  progress: progress,
                  active: fg,
                  idle: fg.withOpacity(0.35),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  color: fg,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          if (playing || _speed != 1) ...[
            const SizedBox(width: 6),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _cycleSpeed,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: fg.withOpacity(0.18),
                ),
                child: Text(speedLabel,
                    style: TextStyle(
                        color: fg,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final List<double> bars;
  final double progress;
  final Color active;
  final Color idle;
  const _WavePainter({
    required this.bars,
    required this.progress,
    required this.active,
    required this.idle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;
    final slot = size.width / bars.length;
    final barW = slot * 0.6;
    for (var i = 0; i < bars.length; i++) {
      final h = (3 + bars[i] * (size.height - 3)).clamp(3.0, size.height);
      final x = i * slot + (slot - barW) / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, (size.height - h) / 2, barW, h),
        const Radius.circular(2),
      );
      final played = (i + 0.5) / bars.length <= progress;
      canvas.drawRRect(rect, Paint()..color = played ? active : idle);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.progress != progress || old.bars != bars || old.active != active;
}
