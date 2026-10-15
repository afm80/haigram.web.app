import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/post_service.dart';
import '../services/presence_service.dart';
import '../services/social_service.dart';
import '../services/user_service.dart';
import '../theme.dart';
import 'common_widgets.dart';
import 'create_flow.dart' show CreateKind, startCreate;
import 'photo_tools.dart';
import 'post_widgets.dart';
import 'settings_screen.dart';
import 'social_screens.dart' show ChatScreen;
import 'story_widgets.dart' show StoryViewer;
import '../route_state.dart';

/// تبويب الملف الشخصي للمستخدم الحالي.
class ProfileScreen extends StatelessWidget {
  final ThemeMode themeMode;
  final Future<void> Function(ThemeMode) onThemeModeChanged;

  const ProfileScreen({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ProfileView(
        uid: PostService.uidOrEmpty,
        isMe: true,
        themeMode: themeMode,
        onThemeModeChanged: onThemeModeChanged,
      ),
    );
  }
}

/// ملف مستخدم آخر (يُفتح عند الضغط على اسمه أو صورته أو من قائمة المتابعين).
class UserProfileScreen extends StatelessWidget {
  final String uid;
  const UserProfileScreen({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    final isMe = uid == PostService.uidOrEmpty;
    return Scaffold(
      appBar: AppBar(
        title: FutureBuilder<AppUser?>(
          future: UserService.profileOf(uid),
          builder: (_, s) => Text(s.data?.username ?? '',
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ),
        actions: [if (!isMe) _ProfileMoreMenu(uid: uid)],
      ),
      body: SafeArea(child: ProfileView(uid: uid, isMe: isMe)),
    );
  }
}

/// حالة الوصول إلى محتوى الملف: مفتوح، خاص (للمتابعين)، أو محظور.
enum _Access { loading, open, privateLocked, blockedByMe, blockedByThem }

/// محتوى الملف الشخصي المشترك: رأس بنمط إنستغرام/تيك توك + تبويبات المحتوى.
class ProfileView extends StatefulWidget {
  final String uid;
  final bool isMe;
  final ThemeMode? themeMode;
  final Future<void> Function(ThemeMode)? onThemeModeChanged;

  const ProfileView({
    super.key,
    required this.uid,
    required this.isMe,
    this.themeMode,
    this.onThemeModeChanged,
  });

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  late final Stream<AppUser?> _userStream =
      UserService.profileStream(widget.uid);
  late final Stream<ChatBlockState>? _blockStream =
      widget.isMe ? null : SocialService.blockState(widget.uid);
  late final Stream<bool>? _followingStream =
      widget.isMe ? null : PostService.isFollowing(widget.uid);
  bool _visitRecorded = false;

  /// يسجّل زيارتي لهذا الملف مرة واحدة (إن فعّل الطرفان الميزة ولا يوجد حظر).
  void _recordVisit(AppUser user, _Access access) {
    if (_visitRecorded || widget.isMe) return;
    if (access == _Access.loading ||
        access == _Access.blockedByMe ||
        access == _Access.blockedByThem) {
      return;
    }
    _visitRecorded = true;
    if (!user.profileVisits || UserService.me?.profileVisits == false) return;
    SocialService.recordProfileVisit(widget.uid).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppUser?>(
      stream: _userStream,
      builder: (context, userSnap) {
        final user = userSnap.data ?? (widget.isMe ? UserService.me : null);
        if (user == null) {
          if (userSnap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(32),
              child: EmptyState(
                  icon: Icons.person_off_outlined,
                  title: 'تعذر تحميل الملف الشخصي',
                  message: '${userSnap.error}'),
            );
          }
          return const Padding(
              padding: EdgeInsets.all(48),
              child: AppLoading(message: 'جارٍ تحميل الملف الشخصي...'));
        }
        if (widget.isMe) return _body(context, user, _Access.open);
        return StreamBuilder<ChatBlockState>(
          stream: _blockStream,
          builder: (context, blockSnap) => StreamBuilder<bool>(
            stream: _followingStream,
            builder: (context, followSnap) {
              final settled = (blockSnap.hasData || blockSnap.hasError) &&
                  (followSnap.hasData || followSnap.hasError);
              final block = blockSnap.data;
              final access = !settled
                  ? _Access.loading
                  : (block?.blockedByMe ?? false)
                      ? _Access.blockedByMe
                      : (block?.blockedByThem ?? false)
                          ? _Access.blockedByThem
                          : (user.isPrivate && followSnap.data != true)
                              ? _Access.privateLocked
                              : _Access.open;
              _recordVisit(user, access);
              return _body(context, user, access);
            },
          ),
        );
      },
    );
  }

  Widget _accessMessage(_Access access) => switch (access) {
        _Access.loading => const AppLoading(),
        _Access.privateLocked => const EmptyState(
            icon: Icons.lock_outline_rounded,
            title: 'هذا الحساب خاص',
            message:
                'أرسل طلب متابعة، وعند موافقة صاحب الحساب ستشاهد منشوراته ومقاطعه.',
          ),
        _Access.blockedByMe => const EmptyState(
            icon: Icons.block,
            title: 'لقد حظرت هذا الحساب',
            message: 'لن يتمكن من مراسلتك. يمكنك إلغاء الحظر من الزر أعلاه.',
          ),
        _Access.blockedByThem => const EmptyState(
            icon: Icons.person_off_outlined,
            title: 'هذا الحساب غير متاح',
          ),
        _Access.open => const SizedBox.shrink(),
      };

  Widget _body(BuildContext context, AppUser user, _Access access) {
    final header = _Header(
      uid: widget.uid,
      user: user,
      isMe: widget.isMe,
      access: access,
      themeMode: widget.themeMode,
      onThemeModeChanged: widget.onThemeModeChanged,
    );
    if (access != _Access.open) {
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: header),
          SliverFillRemaining(
              hasScrollBody: false, child: _accessMessage(access)),
        ],
      );
    }

    // الصور، المنشورات النصية، الفيديو، والمحفوظات (لصاحب الحساب فقط).
    // لون أيقونات التبويبات يتبع الوضع (داكن/فاتح) عبر labelColor و unselectedLabelColor.
    final tabs = <Tab>[
      const Tab(icon: Icon(Icons.photo_library_outlined)),
      const Tab(icon: Icon(Icons.play_circle_outline_rounded)),
      const Tab(icon: Icon(Icons.article_outlined)),
      if (widget.isMe) const Tab(icon: Icon(Icons.bookmark_border_rounded)),
    ];
    final pinnedIds = user.pinnedPostIds.toSet();
    return DefaultTabController(
      key: ValueKey(tabs.length),
      initialIndex: 0,
      length: tabs.length,
      child: _PinnedPosts(
        ids: user.pinnedPostIds,
        builder: (context, pinned) => NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverToBoxAdapter(child: header),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabsDelegate(
                TabBar(
                  labelColor: context.appColors.text,
                  unselectedLabelColor: context.appColors.textDim,
                  indicatorColor: context.appColors.text,
                  tabs: tabs,
                ),
              ),
            ),
          ],
          body: TabBarView(
            children: [
              _PostsTab(
                uid: widget.uid,
                isMe: widget.isMe,
                type: PostType.photo,
                pinned: pinned,
                pinnedIds: pinnedIds,
              ),
              _PostsTab(
                uid: widget.uid,
                isMe: widget.isMe,
                type: PostType.text,
                video: true,
                pinned: pinned,
                pinnedIds: pinnedIds,
              ),
              _PostsTab(
                uid: widget.uid,
                isMe: widget.isMe,
                type: PostType.text,
                video: false,
                pinned: pinned,
                pinnedIds: pinnedIds,
              ),
              if (widget.isMe) const _SavedGrid(),
            ],
          ),
        ),
      ),
    );
  }
}

/// يجلب المنشورات المثبّتة بمعرّفاتها (حتى 3) ويعيد بناء الواجهة عند تغيّرها.
/// يُبقي النتيجة السابقة أثناء إعادة التحميل حتى لا تومض الشبكة.
class _PinnedPosts extends StatefulWidget {
  final List<String> ids;
  final Widget Function(BuildContext context, List<Post> pinned) builder;
  const _PinnedPosts({required this.ids, required this.builder});

  @override
  State<_PinnedPosts> createState() => _PinnedPostsState();
}

class _PinnedPostsState extends State<_PinnedPosts> {
  List<Post> _posts = const [];
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _PinnedPosts old) {
    super.didUpdateWidget(old);
    if (!listEquals(old.ids, widget.ids)) _load();
  }

  Future<void> _load() async {
    final ids = widget.ids;
    final request = ++_request;
    if (ids.isEmpty) {
      _posts = const [];
      return;
    }
    try {
      final posts = await PostService.postsByIds(ids);
      if (!mounted || request != _request) return;
      setState(() => _posts = posts);
    } catch (_) {
      // نُبقي القائمة السابقة؛ التثبيت تحسين وليس أساسياً.
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = {
      for (var i = 0; i < widget.ids.length; i++) widget.ids[i]: i,
    };
    final visible = _posts.where((p) => order.containsKey(p.id)).toList()
      ..sort((a, b) => order[a.id]!.compareTo(order[b.id]!));
    return widget.builder(context, visible);
  }
}

class _TabsDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  const _TabsDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;
  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      ColoredBox(color: context.appColors.bg, child: tabBar);
  @override
  bool shouldRebuild(covariant _TabsDelegate old) => true;
}

class _Header extends StatelessWidget {
  final String uid;
  final AppUser user;
  final bool isMe;
  final _Access access;
  final ThemeMode? themeMode;
  final Future<void> Function(ThemeMode)? onThemeModeChanged;

  const _Header({
    required this.uid,
    required this.user,
    required this.isMe,
    required this.access,
    this.themeMode,
    this.onThemeModeChanged,
  });

  void _openSettings(BuildContext context) {
    final onChanged = onThemeModeChanged;
    if (onChanged == null) return;
    Navigator.of(context).push(
      appRoute<void>(
        'settings',
        const {},
        (_) => SettingsScreen(onThemeModeChanged: onChanged),
      ),
    );
  }

  void _showProfileShareSheet(BuildContext context, AppUser user) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.appColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ProfileShareSheet(user: user),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = user;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        children: [
          // زر القائمة (الإعدادات) يظهر فقط لصاحب الحساب في تبويب ملفه الشخصي،
          // ولا يظهر عند فتح أي ملف آخر (أو ملفه نفسه من منشور/بحث).
          if (isMe && onThemeModeChanged != null)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Builder(builder: (context) {
                // الأيقونة مرسومة بثلاث خطوط (وليست خط أيقونات) لتظهر
                // دائماً، ولونها يتبدل: أبيض على داكن وأسود على فاتح.
                final isDark =
                    Theme.of(context).brightness == Brightness.dark;
                final lineColor = isDark ? Colors.white : Colors.black87;
                Widget bar() => Container(
                      width: 20,
                      height: 2.5,
                      decoration: BoxDecoration(
                        color: lineColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    );
                return Tooltip(
                  message: 'الإعدادات',
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _openSettings(context),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              bar(),
                              const SizedBox(height: 5),
                              bar(),
                              const SizedBox(height: 5),
                              bar(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          Row(
            children: [
              _avatar(u),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _LiveStat(
                        label: 'منشورات',
                        load: () => PostService.countPosts(uid),
                      ),
                    ),
                    Expanded(
                      child: _LiveStat(
                        label: 'متابعين',
                        load: () => PostService.countFollowers(uid),
                        onTap: () => _showFollowSheet(context, uid, 0),
                      ),
                    ),
                    Expanded(
                      child: _LiveStat(
                        label: 'أتابعه',
                        load: () => PostService.countFollowing(uid),
                        onTap: () => _showFollowSheet(context, uid, 1),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              u.displayName,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              '@${u.username}',
              style:
                  TextStyle(fontSize: 14, color: context.appColors.textDim),
            ),
          ),
          if (u.bio.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(u.bio,
                  style: const TextStyle(fontSize: 14, height: 1.45)),
            ),
          ],
          if (u.website.isNotEmpty) ...[
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: GestureDetector(
                onTap: () => _openWebsite(context, u.website),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.link_rounded,
                        size: 16, color: context.appColors.text),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        u.website.replaceFirst(RegExp(r'^https?://'), ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (isMe) _myButtons(context, u) else _otherButtons(context, u),
        ],
      ),
    );
  }

  Future<void> _openWebsite(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        messenger.showSnackBar(const SnackBar(content: Text('تعذر فتح الرابط')));
      }
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('تعذر فتح الرابط')));
    }
  }

  Future<void> _openStory(
    BuildContext context,
    List<StoryGroup> groups,
    String ownerUid,
  ) async {
    final index = groups.indexWhere((group) => group.uid == ownerUid);
    if (index < 0) return;
    await rootNavigatorOf(context).push<void>(
      PageRouteBuilder(
        opaque: true,
        // نعرض قصص هذا المستخدم فقط، وعند انتهائها يعود المشاهد للملف.
        pageBuilder: (_, __, ___) =>
            StoryViewer(groups: [groups[index]], initial: 0),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  Widget _avatar(AppUser u) {
    final image = u.avatarImage;
    return StreamBuilder<List<StoryGroup>>(
      stream: PostService.storyGroups(),
      builder: (context, stories) {
        final hasStory =
            stories.data?.any((group) => group.uid == u.uid) ?? false;
        final avatar = CircleAvatar(
          radius: hasStory ? 43 : 46,
          backgroundColor: AppColors.accent,
          backgroundImage: image,
          child: image == null
              ? Text(u.initial,
                  style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w700,
                      color: Colors.white))
              : null,
        );
        return StreamBuilder<bool>(
          stream: PresenceService.isOnline(u.uid),
          builder: (context, presence) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            // الضغط على الصورة: إن كان لصاحب الملف قصة فتُفتح (له ولغيره).
            onTap: hasStory
                ? () => _openStory(context, stories.data!, u.uid)
                : null,
            onLongPress: () => showProfilePhoto(context, u),
            child: SizedBox(
            width: 96,
            height: 96,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (hasStory)
                  Container(
                    width: 96,
                    height: 96,
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppColors.storyGradient,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: context.appColors.bg),
                      child: Center(child: avatar),
                    ),
                  )
                else
                  avatar,
                if (presence.data == true)
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: const Color(0xFF31C75A),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: context.appColors.bg, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ),
        );
      },
    );
  }

  Widget _myButtons(BuildContext context, AppUser u) {
    return Row(
      children: [
        Expanded(
          child: _pillButton(
              context,
              'تعديل الملف الشخصي',
              () => rootNavigatorOf(context).push(appRoute(
                  'editProfile',
                  const {},
                  (_) => const EditProfileScreen()))),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _pillButton(
            context,
            'مشاركة الملف الشخصي',
            () => _showProfileShareSheet(context, u),
          ),
        ),
      ],
    );
  }

  Widget _otherButtons(BuildContext context, AppUser u) {
    if (access == _Access.blockedByThem) return const SizedBox.shrink();
    if (access == _Access.blockedByMe) {
      return _pillButton(context, 'إلغاء الحظر', () async {
        final messenger = ScaffoldMessenger.of(context);
        try {
          await SocialService.setBlocked(uid, false);
        } catch (error) {
          messenger.showSnackBar(
            SnackBar(content: Text('تعذر إلغاء الحظر: $error')),
          );
        }
      });
    }
    return Row(
      children: [
        Expanded(child: FollowActionButton(uid: uid, compact: true)),
        const SizedBox(width: 8),
        Expanded(child: _MessageActionButton(uid: uid)),
        const SizedBox(width: 8),
        SizedBox(
          width: 42,
          height: 42,
          child: IconButton(
            tooltip: 'مشاركة الملف الشخصي',
            style: IconButton.styleFrom(
              backgroundColor: context.appColors.surfaceHigh,
              foregroundColor: context.appColors.text,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => _showProfileShareSheet(context, u),
            icon: const Icon(Icons.share_outlined),
          ),
        ),
      ],
    );
  }

  Widget _pillButton(BuildContext context, String text, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: context.appColors.surfaceHigh,
        side: BorderSide.none,
        minimumSize: const Size.fromHeight(40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(text,
          style: TextStyle(
              color: context.appColors.text, fontWeight: FontWeight.w600)),
    );
  }

  void _showFollowSheet(BuildContext context, String uid, int initialTab) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.appColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) =>
          _FollowSheet(uid: uid, initialTab: initialTab, outerContext: context),
    );
  }
}

class FollowActionButton extends StatelessWidget {
  final String uid;
  final bool compact;

  const FollowActionButton({
    super.key,
    required this.uid,
    this.compact = false,
  });

  Future<void> _onPressed(BuildContext context, FollowState state) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      switch (state) {
        case FollowState.following:
          await PostService.unfollow(uid);
        case FollowState.requested:
          await PostService.cancelFollowRequest(uid);
          messenger.showSnackBar(
              const SnackBar(content: Text('تم إلغاء طلب المتابعة')));
        case FollowState.none:
          final result = await PostService.follow(uid);
          if (result == FollowState.requested) {
            messenger.showSnackBar(const SnackBar(
                content: Text('تم إرسال طلب المتابعة، بانتظار الموافقة')));
          }
      }
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر تحديث المتابعة: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<FollowState>(
      stream: PostService.followState(uid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text(
            'تعذر تحميل حالة المتابعة',
            style: TextStyle(color: context.appColors.textDim, fontSize: 11),
          );
        }
        if (!snapshot.hasData) {
          return SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: context.appColors.textDim,
            ),
          );
        }

        final state = snapshot.data!;
        final neutral = state != FollowState.none;
        final style = FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(42),
          padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 14),
          backgroundColor:
              neutral ? context.appColors.surfaceHigh : AppColors.brandPurple,
          foregroundColor: neutral ? context.appColors.text : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        );
        final label = Text(
          switch (state) {
            FollowState.following => 'إلغاء المتابعة',
            FollowState.requested => 'تم إرسال الطلب',
            FollowState.none => 'متابعة',
          },
          style: TextStyle(
              fontSize: compact ? 14 : 15, fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
        if (compact) {
          return FilledButton(
            onPressed: () => _onPressed(context, state),
            style: style,
            child: label,
          );
        }
        return FilledButton.icon(
          onPressed: () => _onPressed(context, state),
          icon: Icon(
            switch (state) {
              FollowState.following => Icons.person_remove_alt_1,
              FollowState.requested => Icons.hourglass_top_rounded,
              FollowState.none => Icons.person_add_alt_1,
            },
            size: 18,
          ),
          label: label,
          style: style,
        );
      },
    );
  }
}

class _MessageActionButton extends StatefulWidget {
  final String uid;

  const _MessageActionButton({required this.uid});

  @override
  State<_MessageActionButton> createState() => _MessageActionButtonState();
}

class _MessageActionButtonState extends State<_MessageActionButton> {
  bool _opening = false;

  Future<void> _openChat() async {
    setState(() => _opening = true);
    try {
      await openChatWith(context, widget.uid);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return OutlinedButton.icon(
      onPressed: _opening ? null : _openChat,
      icon: _opening
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.textDim,
              ),
            )
          : const Icon(Icons.chat_bubble_outline_rounded, size: 18),
      label: const Text(
        'مراسلة',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(42),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        backgroundColor: colors.surfaceHigh,
        foregroundColor: colors.text,
        side: BorderSide.none,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

/// يبدأ (أو يفتح) محادثة مع مستخدم ويعرضها فوق الشريط السفلي.
Future<void> openChatWith(BuildContext context, String uid) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = rootNavigatorOf(context);
  try {
    final conversationId = await SocialService.startConversation(uid);
    await navigator.push<void>(
      appRoute<void>(
        'chat',
        {'cid': conversationId, 'uid': uid},
        (_) => ChatScreen(conversationId: conversationId, otherUid: uid),
      ),
    );
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text('تعذر فتح المحادثة: $error')),
    );
  }
}

class _ProfileShareSheet extends StatefulWidget {
  final AppUser user;

  const _ProfileShareSheet({required this.user});

  @override
  State<_ProfileShareSheet> createState() => _ProfileShareSheetState();
}

class _ProfileShareSheetState extends State<_ProfileShareSheet> {
  late final Future<List<AppUser>> _friends = _loadFriends();
  String? _sharingUid;

  Future<List<AppUser>> _loadFriends() async {
    final ids = await SocialService.mutualFriendIds();
    final users = await Future.wait(ids.map(UserService.profileOf));
    return users.whereType<AppUser>().toList();
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: widget.user.link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ رابط الملف الشخصي')),
    );
  }

  Uri _shareUri(String platform) {
    final link = widget.user.link;
    final text = 'شاهد ملف @${widget.user.username} على Haigram';
    return switch (platform) {
      'whatsapp' => Uri.https('wa.me', '/', {'text': '$text $link'}),
      'telegram' => Uri.https(
          't.me',
          '/share/url',
          {'url': link, 'text': text},
        ),
      'facebook' => Uri.https(
          'www.facebook.com',
          '/sharer/sharer.php',
          {'u': link},
        ),
      'x' => Uri.https(
          'twitter.com',
          '/intent/tweet',
          {'url': link, 'text': text},
        ),
      _ => throw ArgumentError.value(platform, 'platform'),
    };
  }

  Future<void> _shareExternally(String platform) async {
    try {
      final opened = await launchUrl(
        _shareUri(platform),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw StateError('تعذر فتح تطبيق المشاركة');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذرت المشاركة: $error')),
        );
      }
    }
  }

  Future<void> _shareWithFriend(AppUser friend) async {
    if (_sharingUid != null) return;
    setState(() => _sharingUid = friend.uid);
    try {
      final conversationId = await SocialService.startConversation(friend.uid);
      await SocialService.sendMessage(
        conversationId,
        'شاهد ملف @${widget.user.username} على Haigram\n${widget.user.link}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تمت مشاركة الملف مع @${friend.username}')),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذرت مشاركة الملف: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharingUid = null);
    }
  }

  Widget _socialOption(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return SizedBox(
      width: 56,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              CircleAvatar(
                radius: 21,
                backgroundColor: color,
                foregroundColor: Colors.white,
                child: Icon(icon, size: 21),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(color: context.appColors.textDim, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final sheetHeight = MediaQuery.sizeOf(context).height * 0.84;
    return SafeArea(
      child: SizedBox(
        height: sheetHeight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            children: [
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textDim.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'مشاركة الملف الشخصي',
                style:
                    TextStyle(color: colors.text, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  UserAvatar(
                    uid: widget.user.uid,
                    fallbackName: widget.user.username,
                    radius: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.user.displayName,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        Text('@${widget.user.username}',
                            style: TextStyle(color: colors.textDim)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                runAlignment: WrapAlignment.center,
                spacing: 4,
                runSpacing: 4,
                children: [
                  _socialOption(
                    'واتساب',
                    Icons.chat_rounded,
                    const Color(0xFF25D366),
                    () => _shareExternally('whatsapp'),
                  ),
                  _socialOption(
                    'تلغرام',
                    Icons.send_rounded,
                    const Color(0xFF229ED9),
                    () => _shareExternally('telegram'),
                  ),
                  _socialOption(
                    'فيسبوك',
                    Icons.facebook,
                    const Color(0xFF1877F2),
                    () => _shareExternally('facebook'),
                  ),
                  _socialOption(
                    'X',
                    Icons.alternate_email_rounded,
                    colors.text,
                    () => _shareExternally('x'),
                  ),
                  _socialOption(
                    'نسخ الرابط',
                    Icons.copy_rounded,
                    colors.surfaceHigh,
                    _copyLink,
                  ),
                ],
              ),
              const Divider(height: 24),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  'إرسال إلى الأصدقاء',
                  style: TextStyle(
                      color: colors.text, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: FutureBuilder<List<AppUser>>(
                  future: _friends,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'تعذر تحميل الأصدقاء\n${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.textDim),
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const AppLoading();
                    }
                    final friends = snapshot.data!;
                    if (friends.isEmpty) {
                      return Center(
                        child: Text(
                          'ستظهر هنا الحسابات التي تتابعك وتتابعها.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.textDim),
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: friends.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, color: colors.surfaceHigh),
                      itemBuilder: (context, index) {
                        final friend = friends[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: UserAvatar(
                            uid: friend.uid,
                            fallbackName: friend.username,
                            radius: 21,
                            showOnline: true,
                          ),
                          title: Text(friend.displayName,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('@${friend.username}',
                              style: TextStyle(color: colors.textDim)),
                          trailing: _sharingUid == friend.uid
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.send_rounded),
                          onTap: _sharingUid == null
                              ? () => _shareWithFriend(friend)
                              : null,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// قائمة متابعي / أتابعه: بحث داخلي، والضغط على أي مستخدم يفتح ملفه الشخصي.
class _FollowSheet extends StatelessWidget {
  final String uid;
  final int initialTab;
  final BuildContext outerContext;
  const _FollowSheet(
      {required this.uid,
      required this.initialTab,
      required this.outerContext});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: context.appColors.textDim,
                    borderRadius: BorderRadius.circular(2))),
            const TabBar(tabs: [Tab(text: 'متابعين'), Tab(text: 'أتابعه')]),
            Expanded(
              child: TabBarView(
                children: [
                  _UserList(
                      loader: () => PostService.followerIdsOnce(uid),
                      empty: 'لا يوجد متابعون بعد',
                      outerContext: outerContext),
                  _UserList(
                      loader: () => PostService.followingIdsOnce(uid),
                      empty: 'لا يتابع أحداً بعد',
                      outerContext: outerContext),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserList extends StatefulWidget {
  final Future<List<String>> Function() loader;
  final String empty;
  final BuildContext outerContext;
  const _UserList(
      {required this.loader, required this.empty, required this.outerContext});

  @override
  State<_UserList> createState() => _UserListState();
}

class _UserListState extends State<_UserList> {
  late final Future<List<AppUser>> _users = _load();
  String _q = '';

  Future<List<AppUser>> _load() async {
    final ids = await widget.loader();
    final users = await Future.wait(ids.map(UserService.profileOf));
    return users.whereType<AppUser>().toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(
                hintText: 'بحث', prefixIcon: Icon(Icons.search_rounded)),
            onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<AppUser>>(
            future: _users,
            builder: (context, snap) {
              if (snap.hasError)
                return Center(
                    child: Text('تعذر التحميل\n${snap.error}',
                        textAlign: TextAlign.center));
              if (!snap.hasData)
                return const AppLoading();
              final list = snap.data!
                  .where((u) =>
                      u.username.contains(_q) ||
                      u.name.toLowerCase().contains(_q))
                  .toList();
              if (list.isEmpty) return Center(child: Text(widget.empty));
              return ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final u = list[i];
                  final isMe = u.uid == PostService.uidOrEmpty;
                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16),
                    onTap: () {
                      Navigator.pop(context);
                      openProfile(widget.outerContext, u.uid);
                    },
                    leading: UserAvatar(
                      uid: u.uid,
                      profile: u,
                      fallbackName: u.username,
                      radius: 22,
                    ),
                    title: Text(
                      u.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: u.name.isEmpty
                        ? null
                        : Text(
                            u.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: context.appColors.textDim),
                          ),
                    // عرض وارتفاع ثابتان: الزر يطلب عرضاً لا نهائياً بطبيعته
                    // فيلتهم مساحة الاسم والصورة داخل ListTile.
                    trailing: isMe
                        ? null
                        : SizedBox(
                            width: 118,
                            height: 38,
                            child: Center(
                              child:
                                  FollowActionButton(uid: u.uid, compact: true),
                            ),
                          ),
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

/// تعديل الملف الشخصي: الاسم، اسم المستخدم، النبذة.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final _name = TextEditingController(text: UserService.me?.name ?? '');
  late final _username =
      TextEditingController(text: UserService.me?.username ?? '');
  late final _bio = TextEditingController(text: UserService.me?.bio ?? '');
  late final _website =
      TextEditingController(text: UserService.me?.website ?? '');
  late String? _photoB64 = UserService.me?.photoB64;
  bool _busy = false;
  String? _error;

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      // تصغير إلى 320px وجودة 70% فيصبح حجم الصورة بضع عشرات الكيلوبايت.
      // نلتقطها بدقة أعلى ثم يقصّها المستخدم ويحجّمها قبل الإضافة.
      final f = await ImagePicker().pickImage(
          source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 90);
      if (f == null) return;
      final Uint8List original = await f.readAsBytes();
      if (!mounted) return;
      final Uint8List? bytes = await cropProfilePhoto(context, original);
      if (bytes == null) return;
      if (bytes.length > 150 * 1024) {
        setState(() => _error = 'الصورة كبيرة جداً، جرّب صورة أخرى');
        return;
      }
      setState(() {
        _photoB64 = base64Encode(bytes);
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'تعذر اختيار الصورة: $e');
    }
  }

  void _photoMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.appColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('التقاط صورة'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('اختيار من ملفات الجهاز'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.gallery);
              },
            ),
            if (_photoB64 != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: AppColors.accent2),
                title: const Text('إزالة الصورة'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _photoB64 = null);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _photoPicker() {
    final me = UserService.me;
    ImageProvider? image;
    if (_photoB64 != null && _photoB64!.isNotEmpty) {
      image = MemoryImage(base64Decode(_photoB64!));
    } else if (_photoB64 == null && me?.photoB64 == null) {
      image = me?.photoUrl != null && me!.photoUrl!.isNotEmpty
          ? me.avatarImage
          : null;
    }
    return Column(
      children: [
        GestureDetector(
          onTap: _photoMenu,
          child: Stack(
            children: [
              CircleAvatar(
                radius: 50,
                backgroundColor: AppColors.accent,
                backgroundImage: image,
                child: image == null
                    ? Text(me?.initial ?? '?',
                        style: const TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.w700,
                            color: Colors.white))
                    : null,
              ),
              PositionedDirectional(
                end: 0,
                bottom: 0,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.accent,
                      border:
                          Border.all(color: context.appColors.bg, width: 2)),
                  child: const Icon(Icons.photo_camera_rounded, size: 17),
                ),
              ),
            ],
          ),
        ),
        TextButton(
            onPressed: _photoMenu, child: const Text('تغيير الصورة الشخصية')),
      ],
    );
  }

  Future<void> _save() async {
    final username = UserService.normalize(_username.text);
    final err = UserService.validate(username);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    final website = UserService.normalizeWebsite(_website.text);
    if (website == null) {
      setState(() => _error = 'الرابط غير صالح، مثال: example.com');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await UserService.updateProfile(
          website: website,
          name: _name.text.trim(),
          username: username,
          bio: _bio.text.trim(),
          photoB64: _photoB64);
      if (mounted) Navigator.of(context).pop();
    } on UsernameTaken {
      setState(() {
        _busy = false;
        _error = 'اسم المستخدم محجوز، اختر اسماً آخر';
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _error = 'تعذر الحفظ: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تعديل الملف الشخصي'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _photoPicker(),
            const SizedBox(height: 12),
            Text('الاسم', style: TextStyle(color: context.appColors.textDim)),
            const SizedBox(height: 6),
            TextField(
                controller: _name,
                maxLength: 50,
                decoration: const InputDecoration(
                    hintText: 'اسمك كما يظهر لمتابعيك', counterText: '')),
            const SizedBox(height: 16),
            Text('اسم المستخدم',
                style: TextStyle(color: context.appColors.textDim)),
            const SizedBox(height: 6),
            TextField(
              controller: _username,
              maxLength: 24,
              textDirection: TextDirection.ltr,
              autocorrect: false,
              decoration: const InputDecoration(
                  hintText: 'username', prefixText: '@', counterText: ''),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('أحرف إنجليزية صغيرة وأرقام و _ و . (3 إلى 24 حرفاً)',
                  style: TextStyle(
                      color: context.appColors.textDim, fontSize: 12)),
            ),
            const SizedBox(height: 16),
            Text('النبذة', style: TextStyle(color: context.appColors.textDim)),
            const SizedBox(height: 6),
            TextField(
                controller: _bio,
                minLines: 3,
                maxLines: 5,
                maxLength: 150,
                decoration: const InputDecoration(hintText: 'عرّف بنفسك')),
            const SizedBox(height: 16),
            Text('الرابط', style: TextStyle(color: context.appColors.textDim)),
            const SizedBox(height: 6),
            TextField(
              controller: _website,
              maxLength: 100,
              keyboardType: TextInputType.url,
              textDirection: TextDirection.ltr,
              autocorrect: false,
              decoration: const InputDecoration(
                  hintText: 'example.com',
                  prefixIcon: Icon(Icons.link_rounded),
                  counterText: ''),
            ),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(_error!,
                      style: TextStyle(color: context.appColors.text))),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('حفظ')),
          ],
        ),
      ),
    );
  }
}

// ---------------- شبكات المحتوى ----------------

int _profileGridColumns(double width) => (width / 150).floor().clamp(3, 6);

/// عدّاد يعيد تحميل نفسه فور أي فعل يغيّر الأعداد (متابعة، إعجاب، نشر، حذف)،
/// ويُبقي القيمة السابقة ظاهرة أثناء التحديث.
class _LiveStat extends StatefulWidget {
  final String label;
  final Future<int> Function() load;
  final VoidCallback? onTap;

  const _LiveStat({required this.label, required this.load, this.onTap});

  @override
  State<_LiveStat> createState() => _LiveStatState();
}

class _LiveStatState extends State<_LiveStat> {
  int? _value;
  Object? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    PostService.statsTick.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    PostService.statsTick.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    final request = ++_request;
    try {
      final value = await widget.load();
      if (!mounted || request != _request) return;
      setState(() {
        _value = value;
        _error = null;
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() => _error = error);
    }
  }

  static String _compact(int n) {
    String fmt(double v, String unit) {
      final t = v >= 10 ? v.round().toString() : v.toStringAsFixed(1);
      return '${t.endsWith('.0') ? t.substring(0, t.length - 2) : t}$unit';
    }

    if (n >= 1000000) return fmt(n / 1000000, 'M');
    if (n >= 1000) return fmt(n / 1000, 'K');
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    const numberStyle = TextStyle(fontSize: 18, fontWeight: FontWeight.w800);
    final Widget number;
    if (_value != null) {
      number = Text(_compact(_value!), style: numberStyle);
    } else if (_error != null) {
      number = Tooltip(
        message: 'تعذر تحميل الإحصائية: $_error',
        child: const Text('—', style: numberStyle),
      );
    } else {
      number = SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: context.appColors.textDim,
        ),
      );
    }
    return InkWell(
      onTap: widget.onTap,
      child: Column(
        children: [
          number,
          Text(widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.appColors.textDim, fontSize: 12)),
        ],
      ),
    );
  }
}

/// زر «أنشئ ...» داخل الحالات الفارغة في ملفك الشخصي.
class _CreateButton extends StatelessWidget {
  final String label;
  final CreateKind kind;
  const _CreateButton({required this.label, required this.kind});

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: () => startCreate(context, kind),
      icon: const Icon(Icons.add_rounded, size: 20),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.brandPurple,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class _PinBadge extends StatelessWidget {
  const _PinBadge();

  @override
  Widget build(BuildContext context) {
    return PositionedDirectional(
      top: 6,
      end: 6,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: const BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.push_pin, size: 13, color: Colors.white),
      ),
    );
  }
}

/// ضغطة مطوّلة على منشور في ملفك: تثبيت في الأعلى أو إلغاء التثبيت.
void _showPinSheet(BuildContext context, Post post, bool pinned) {
  final colors = context.appColors;
  final messenger = ScaffoldMessenger.of(context);
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(pinned ? Icons.push_pin_outlined : Icons.push_pin),
            title: Text(pinned ? 'إلغاء التثبيت' : 'تثبيت في أعلى الملف'),
            subtitle: pinned
                ? null
                : Text('حتى ${UserService.maxPinned} منشورات أو مقاطع',
                    style: TextStyle(color: colors.textDim, fontSize: 12)),
            onTap: () async {
              Navigator.of(sheetContext).pop();
              try {
                await UserService.setPinned(post.id, !pinned);
              } catch (error) {
                messenger.showSnackBar(SnackBar(
                  content: Text(error is PinLimitReached
                      ? '$error'
                      : 'تعذر تحديث التثبيت: $error'),
                ));
              }
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

List<Post> _pinnedFirst(List<Post> pinned, List<Post> rest) {
  final ids = {for (final p in pinned) p.id};
  return [...pinned, ...rest.where((p) => !ids.contains(p.id))];
}

/// تبويب في الملف الشخصي: الصور (photo) أو المنشورات النصية (text بدون فيديو)
/// أو الفيديو (text فيه رابط يوتيوب). [video]: null = بلا تصفية.
class _PostsTab extends StatefulWidget {
  final String uid;
  final bool isMe;
  final PostType type;
  final bool? video;
  final List<Post> pinned;
  final Set<String> pinnedIds;
  const _PostsTab({
    required this.uid,
    required this.isMe,
    required this.type,
    this.video,
    this.pinned = const [],
    this.pinnedIds = const <String>{},
  });

  @override
  State<_PostsTab> createState() => _PostsTabState();
}

class _PostsTabState extends State<_PostsTab> {
  late final Stream<List<Post>> _stream =
      PostService.stream(widget.type, uid: widget.uid);

  bool get _isPhotos => widget.type == PostType.photo;
  bool get _isVideos => widget.video == true;

  bool _keep(Post p) =>
      p.type == widget.type &&
      (widget.video == null || p.hasVideo == widget.video);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Post>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
              child: Text('تعذر التحميل\n${snap.error}',
                  textAlign: TextAlign.center));
        }
        if (!snap.hasData) return const AppLoading();
        // المثبّت يظهر أولاً في التبويب الذي ينتمي إليه فقط.
        final pinned = widget.pinned.where(_keep).toList();
        final list = _pinnedFirst(pinned, snap.data!.where(_keep).toList());
        if (list.isEmpty) {
          final me = widget.isMe;
          return EmptyState(
            icon: _isPhotos
                ? Icons.photo_library_outlined
                : _isVideos
                    ? Icons.play_circle_outline_rounded
                    : Icons.article_outlined,
            title: _isPhotos
                ? (me ? 'ابدأ بأول صورة' : 'لا توجد صور بعد')
                : _isVideos
                    ? (me ? 'ابدأ بأول فيديو' : 'لا توجد فيديوهات بعد')
                    : (me ? 'ابدأ بأول منشور' : 'لا توجد منشورات بعد'),
            message: _isPhotos
                ? (me
                    ? 'شارك صورة وستظهر هنا في ملفك.'
                    : 'ستظهر صور هذا الحساب هنا.')
                : _isVideos
                    ? (me
                        ? 'شارك رابط فيديو من يوتيوب وسيظهر هنا في ملفك.'
                        : 'ستظهر فيديوهات هذا الحساب هنا.')
                    : (me
                        ? 'شارك فكرة أو خاطرة وستظهر هنا في ملفك.'
                        : 'ستظهر منشورات هذا الحساب هنا.'),
            action: me
                ? _CreateButton(
                    label: _isPhotos
                        ? 'أضف أول صورة'
                        : _isVideos
                            ? 'أضف أول فيديو'
                            : 'أنشئ أول منشور',
                    kind: _isVideos ? CreateKind.video : CreateKind.post)
                : null,
          );
        }
        return _PostGrid(
            list: list, pinnedIds: widget.pinnedIds, canPin: widget.isMe);
      },
    );
  }
}

class _PostGrid extends StatelessWidget {
  final List<Post> list;
  final Set<String> pinnedIds;
  final bool canPin;
  const _PostGrid({
    required this.list,
    this.pinnedIds = const <String>{},
    this.canPin = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        padding: const EdgeInsets.all(2),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _profileGridColumns(constraints.maxWidth),
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
        ),
        itemCount: list.length,
        itemBuilder: (_, i) {
          final post = list[i];
          return GestureDetector(
            onTap: () {
              Navigator.of(context).push(appRoute('post', {'id': post.id},
                  (_) => PostDetailScreen(post: post)));
            },
            onLongPress: canPin
                ? () =>
                    _showPinSheet(context, post, pinnedIds.contains(post.id))
                : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                switch (post.type) {
                  PostType.photo => PostImage(post: post),
                  _ when post.hasVideo => Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: post.videoThumb!,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              Container(color: Colors.black),
                        ),
                        const Center(
                          child: Icon(Icons.play_circle_fill_rounded,
                              color: Colors.white, size: 36),
                        ),
                      ],
                    ),
                  _ => Container(
                      color: context.appColors.surfaceHigh,
                      padding: const EdgeInsets.all(8),
                      child: Text(post.caption,
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12)),
                    ),
                },
                if (pinnedIds.contains(post.id)) const _PinBadge(),
                _CardStats(post: post),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SavedGrid extends StatelessWidget {
  const _SavedGrid();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Post>>(
      stream: PostService.savedPosts(),
      builder: (context, snap) {
        if (snap.hasError)
          return Center(
              child: Text('تعذر التحميل\n${snap.error}',
                  textAlign: TextAlign.center));
        if (!snap.hasData) return const AppLoading();
        final list = snap.data!;
        if (list.isEmpty) {
          return const EmptyState(
              icon: Icons.bookmark_border_rounded,
              title: 'قائمتك المحفوظة فارغة',
              message: 'احفظ المنشورات التي تريد الرجوع إليها لاحقاً.');
        }
        return _PostGrid(list: list);
      },
    );
  }
}


/// قائمة (⋮) في ملف مستخدم آخر: حظر / إلغاء الحظر، وإبلاغ.
class _ProfileMoreMenu extends StatefulWidget {
  final String uid;
  const _ProfileMoreMenu({required this.uid});

  @override
  State<_ProfileMoreMenu> createState() => _ProfileMoreMenuState();
}

class _ProfileMoreMenuState extends State<_ProfileMoreMenu> {
  late final Stream<ChatBlockState> _block =
      SocialService.blockState(widget.uid);

  Future<void> _toggleBlock(bool blockedByMe) async {
    final blocking = !blockedByMe;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(blocking ? 'حظر هذا الحساب؟' : 'إلغاء الحظر؟'),
        content: Text(blocking
            ? 'لن يتمكن من مراسلتك أو رؤية منشوراتك في ملفك، وسيتم إلغاء '
                'متابعتك له. يمكنك إلغاء الحظر في أي وقت.'
            : 'سيتمكن من مراسلتك مجدداً إذا كنتما تتابعان بعضكما.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(blocking ? 'حظر' : 'إلغاء الحظر'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await SocialService.setBlocked(widget.uid, blocking);
      PostService.notifyStatsChanged();
      messenger.showSnackBar(
        SnackBar(content: Text(blocking ? 'تم حظر الحساب' : 'تم إلغاء الحظر')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر تنفيذ العملية: $error')),
      );
    }
  }

  void _report() {
    final colors = context.appColors;
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
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
                child: Text('إبلاغ عن هذا الحساب',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: colors.text)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                    'اختر السبب الأقرب. لن يعرف صاحب الحساب أنك من أبلغ.',
                    style: TextStyle(fontSize: 12, color: colors.textDim)),
              ),
            ),
            for (final reason in SocialService.reportReasons.entries)
              ListTile(
                title: Text(reason.value),
                trailing: const Icon(Icons.chevron_left_rounded),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  try {
                    await SocialService.reportUser(widget.uid, reason.key);
                    messenger.showSnackBar(
                      const SnackBar(content: Text('تم إرسال البلاغ، شكراً لك')),
                    );
                  } catch (error) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('تعذر إرسال البلاغ: $error')),
                    );
                  }
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ChatBlockState>(
      stream: _block,
      builder: (context, snapshot) {
        final blockedByMe = snapshot.data?.blockedByMe ?? false;
        return PopupMenuButton<String>(
          tooltip: 'المزيد',
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (value) {
            if (value == 'report') {
              _report();
            } else {
              _toggleBlock(blockedByMe);
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'block',
              child: Row(children: [
                Icon(blockedByMe ? Icons.lock_open_rounded : Icons.block,
                    size: 20),
                const SizedBox(width: 12),
                Text(blockedByMe ? 'إلغاء الحظر' : 'حظر'),
              ]),
            ),
            const PopupMenuItem(
              value: 'report',
              child: Row(children: [
                Icon(Icons.flag_outlined, size: 20),
                SizedBox(width: 12),
                Text('إبلاغ'),
              ]),
            ),
          ],
        );
      },
    );
  }
}

String _compactCount(int n) {
  if (n >= 1000000) {
    final v = n / 1000000;
    return '${v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(1)}M'
        .replaceFirst('.0M', 'M');
  }
  if (n >= 1000) {
    final v = n / 1000;
    return '${v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(1)}K'
        .replaceFirst('.0K', 'K');
  }
  return '$n';
}

/// أعداد المشاهدات والإعجابات والتعليقات والمشاركات أسفل كرت الفيديو/المنشور.
class _CardStats extends StatelessWidget {
  final Post post;
  final bool showViews;
  const _CardStats({required this.post, this.showViews = false});

  Widget _item(Widget icon, int count) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(width: 2),
            Text(
              _compactCount(count),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(blurRadius: 4)],
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    const shadow = [Shadow(blurRadius: 4)];
    const size = 14.0;
    return PositionedDirectional(
      start: 0,
      end: 0,
      bottom: 0,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(6, 14, 6, 5),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Color(0x99000000), Colors.transparent],
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showViews)
                  _item(
                      const Icon(Icons.play_arrow_rounded,
                          size: 16, color: Colors.white, shadows: shadow),
                      post.views),
                _item(
                    const Icon(Icons.favorite_rounded,
                        size: size, color: Colors.white, shadows: shadow),
                    post.likes),
                _item(
                    const Icon(Icons.mode_comment_rounded,
                        size: size, color: Colors.white, shadows: shadow),
                    post.comments),
                _item(
                    Transform.flip(
                      flipX: true,
                      child: const Icon(Icons.reply_rounded,
                          size: 16, color: Colors.white, shadows: shadow),
                    ),
                    post.shares),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
