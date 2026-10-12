import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../services/post_service.dart';
import '../services/user_service.dart';
import '../theme.dart';
import 'common_widgets.dart';
import 'post_widgets.dart';
import 'video_feed_screen.dart';

/// تبويب "حسابي": ملفي الشخصي.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
        child: ProfileView(uid: PostService.uidOrEmpty, isMe: true));
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
      ),
      body: SafeArea(child: ProfileView(uid: uid, isMe: isMe)),
    );
  }
}

/// محتوى الملف الشخصي المشترك: رأس بنمط إنستغرام/تيك توك + تبويبات المحتوى.
class ProfileView extends StatelessWidget {
  final String uid;
  final bool isMe;
  const ProfileView({super.key, required this.uid, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final tabs = <Tab>[
      const Tab(icon: Icon(Icons.grid_on_rounded)),
      const Tab(icon: Icon(Icons.video_library_outlined)),
      const Tab(icon: Icon(Icons.photo_library_outlined)),
      const Tab(icon: Icon(Icons.notes_rounded)),
      if (isMe) const Tab(icon: Icon(Icons.bookmark_border_rounded)),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverToBoxAdapter(child: _Header(uid: uid, isMe: isMe)),
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
            _ProfileGrid(uid: uid),
            _VideoGrid(uid: uid),
            _PhotoGrid(uid: uid),
            _TextList(uid: uid),
            if (isMe) const _SavedGrid(),
          ],
        ),
      ),
    );
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
  final bool isMe;
  const _Header({required this.uid, required this.isMe});

  Future<void> _confirmSignOut(BuildContext context) async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تسجيل الخروج؟'),
        content: const Text('هل تريد تسجيل الخروج من حسابك؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('تسجيل الخروج'),
          ),
        ],
      ),
    );
    if (shouldSignOut != true || !context.mounted) return;
    try {
      await FirebaseAuth.instance.signOut();
      UserService.me = null;
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تسجيل الخروج: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppUser?>(
      stream: UserService.profileStream(uid),
      builder: (context, snap) {
        final u = snap.data ?? (isMe ? UserService.me : null);
        if (u == null) {
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(32),
              child: EmptyState(
                  icon: Icons.person_off_outlined,
                  title: 'تعذر تحميل الملف الشخصي',
                  message: '${snap.error}'),
            );
          }
          return const Padding(
              padding: EdgeInsets.all(48),
              child: AppLoading(message: 'جارٍ تحميل الملف الشخصي...'));
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            children: [
              if (isMe)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: IconButton(
                    icon: const Icon(Icons.logout_rounded),
                    tooltip: 'تسجيل الخروج',
                    onPressed: () => _confirmSignOut(context),
                  ),
                ),
              Row(
                children: [
                  _avatar(u),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: _stat(
                              context, 'منشور', PostService.countPosts(uid)),
                        ),
                        Expanded(
                          child: _stat(
                            context,
                            'المتابعون',
                            PostService.countFollowers(uid),
                            onTap: () => _showFollowSheet(context, uid, 0),
                          ),
                        ),
                        Expanded(
                          child: _stat(
                            context,
                            isMe ? 'أتابع' : 'يتابع',
                            PostService.countFollowing(uid),
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
                  style: TextStyle(
                      fontSize: 14, color: context.appColors.textDim),
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
              const SizedBox(height: 16),
              if (isMe) _myButtons(context, u) else _otherButtons(context, u),
            ],
          ),
        );
      },
    );
  }

  Widget _avatar(AppUser u) {
    final image = u.avatarImage;
    return CircleAvatar(
      radius: 46,
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
  }

  Widget _myButtons(BuildContext context, AppUser u) {
    return Row(
      children: [
        Expanded(
          child: _pillButton(
              context,
              'تعديل الملف الشخصي',
              () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const EditProfileScreen()))),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _pillButton(context, 'نسخ الرابط', () async {
            await Clipboard.setData(ClipboardData(text: u.link));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم نسخ رابط الملف الشخصي')));
            }
          }),
        ),
      ],
    );
  }

  Widget _otherButtons(BuildContext context, AppUser u) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: FollowActionButton(uid: uid),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _pillButton(context, 'نسخ الرابط', () async {
            await Clipboard.setData(ClipboardData(text: u.link));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم نسخ رابط الملف الشخصي')));
            }
          }),
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

  Widget _stat(BuildContext context, String label, Future<int> value,
      {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          FutureBuilder<int>(
            future: value,
            builder: (_, snapshot) {
              if (snapshot.hasError) {
                return Tooltip(
                  message: 'تعذر تحميل الإحصائية: ${snapshot.error}',
                  child: const Text('—',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                );
              }
              if (!snapshot.hasData) {
                return SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.appColors.textDim,
                  ),
                );
              }
              return Text('${snapshot.data}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800));
            },
          ),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.appColors.textDim, fontSize: 12)),
        ],
      ),
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

  Future<void> _toggle(BuildContext context, bool following) async {
    try {
      await PostService.toggleFollow(uid, following);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تحديث المتابعة: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: PostService.isFollowing(uid),
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

        final following = snapshot.data!;
        return FilledButton.icon(
          onPressed: () => _toggle(context, following),
          icon: Icon(
            following ? Icons.person_remove_alt_1 : Icons.person_add_alt_1,
            size: compact ? 16 : 18,
          ),
          label: Text(
            following ? 'إلغاء المتابعة' : 'متابعة',
            style: TextStyle(fontSize: compact ? 10 : 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          style: FilledButton.styleFrom(
            minimumSize: compact ? const Size(132, 34) : const Size.fromHeight(42),
            padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 14),
            backgroundColor:
                following ? context.appColors.surfaceHigh : AppColors.accent,
            foregroundColor:
                following ? context.appColors.text : Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      },
    );
  }
}

/// قائمة المتابعين / أتابع: بحث داخلي، والضغط على أي مستخدم يفتح ملفه الشخصي.
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
            const TabBar(tabs: [Tab(text: 'المتابعون'), Tab(text: 'أتابع')]),
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
                return const Center(child: CircularProgressIndicator());
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
                    onTap: () {
                      Navigator.pop(context);
                      openProfile(widget.outerContext, u.uid);
                    },
                    leading: UserAvatar(
                        uid: u.uid, fallbackName: u.username, radius: 22),
                    title: Text(u.username,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: u.name.isEmpty
                        ? null
                        : Text(u.name,
                            style: TextStyle(color: context.appColors.textDim)),
                    trailing: isMe
                        ? null
                        : FollowActionButton(uid: u.uid, compact: true),
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
  late String? _photoB64 = UserService.me?.photoB64;
  bool _busy = false;
  String? _error;

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      // تصغير إلى 320px وجودة 70% فيصبح حجم الصورة بضع عشرات الكيلوبايت.
      final f = await ImagePicker().pickImage(
          source: source, maxWidth: 320, maxHeight: 320, imageQuality: 70);
      if (f == null) return;
      final Uint8List bytes = await f.readAsBytes();
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
                title: const Text('إزالة الصورة',
                    style: TextStyle(color: AppColors.accent2)),
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
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await UserService.updateProfile(
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
        actions: [
          TextButton(
            onPressed: _busy ? null : _save,
            child: const Text('حفظ',
                style: TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 16)),
          ),
        ],
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
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(_error!,
                      style: const TextStyle(color: AppColors.accent2))),
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

class _ProfileGrid extends StatelessWidget {
  final String uid;
  const _ProfileGrid({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Post>>(
      stream: PostService.profilePosts(uid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('تعذر تحميل المنشورات\n${snapshot.error}',
                textAlign: TextAlign.center),
          );
        }
        if (!snapshot.hasData) return const AppLoading();
        final posts = snapshot.data!;
        if (posts.isEmpty) {
          return const EmptyState(
            icon: Icons.grid_on_rounded,
            title: 'لا توجد منشورات بعد',
            message: 'ستظهر منشورات هذا الحساب هنا.',
          );
        }
        return _PostGrid(list: posts);
      },
    );
  }
}

class _VideoGrid extends StatelessWidget {
  final String uid;
  const _VideoGrid({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Post>>(
      stream: PostService.stream(PostType.video, uid: uid),
      builder: (context, snap) {
        if (snap.hasError)
          return Center(
              child: Text('تعذر التحميل\n${snap.error}',
                  textAlign: TextAlign.center));
        if (!snap.hasData) return const AppLoading();
        final list = snap.data!;
        if (list.isEmpty) {
          return const EmptyState(
              icon: Icons.play_arrow_rounded,
              title: 'لا توجد فيديوهات بعد',
              message: 'ستظهر فيديوهات هذا الحساب هنا.');
        }
        return GridView.builder(
          padding: const EdgeInsets.all(2),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
              childAspectRatio: 9 / 14),
          itemCount: list.length,
          itemBuilder: (_, i) => GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    VideoViewerScreen(posts: list, initialIndex: i))),
            child: Container(
              decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      colors: [Color(0xFF7C2D12), Color(0xFF431407)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter)),
              child: Stack(
                children: [
                  const Center(
                      child: Icon(Icons.play_circle_outline_rounded,
                          size: 34, color: Colors.white54)),
                  PositionedDirectional(
                    start: 6,
                    bottom: 6,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.play_arrow_outlined, size: 18),
                        Text('${list[i].views}',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
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
}

class _PhotoGrid extends StatelessWidget {
  final String uid;
  const _PhotoGrid({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Post>>(
      stream: PostService.stream(PostType.photo, uid: uid),
      builder: (context, snap) {
        if (snap.hasError)
          return Center(
              child: Text('تعذر التحميل\n${snap.error}',
                  textAlign: TextAlign.center));
        if (!snap.hasData) return const AppLoading();
        final list = snap.data!;
        if (list.isEmpty) {
          return const EmptyState(
              icon: Icons.photo_outlined,
              title: 'لا توجد صور بعد',
              message: 'ستظهر الصور والمنشورات المرئية هنا.');
        }
        return _PostGrid(list: list);
      },
    );
  }
}

class _PostGrid extends StatelessWidget {
  final List<Post> list;
  const _PostGrid({required this.list});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, mainAxisSpacing: 2, crossAxisSpacing: 2),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final p = list[i];
        return GestureDetector(
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => PostDetailScreen(post: p))),
          child: switch (p.type) {
            PostType.photo => PostImage(post: p, height: 140),
            PostType.video => Container(
                color: context.appColors.surfaceHigh,
                child: const Center(
                    child: Icon(Icons.play_circle_outline_rounded,
                        size: 34, color: Colors.white54)),
              ),
            _ => Container(
                color: context.appColors.surfaceHigh,
                padding: const EdgeInsets.all(8),
                child: Text(p.caption,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12)),
              ),
          },
        );
      },
    );
  }
}

class _TextList extends StatelessWidget {
  final String uid;
  const _TextList({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Post>>(
      stream: PostService.stream(PostType.text, uid: uid),
      builder: (context, snap) {
        if (snap.hasError)
          return Center(
              child: Text('تعذر التحميل\n${snap.error}',
                  textAlign: TextAlign.center));
        if (!snap.hasData) return const AppLoading();
        final list = snap.data!;
        if (list.isEmpty) {
          return const EmptyState(
              icon: Icons.notes_rounded,
              title: 'لا توجد خواطر بعد',
              message: 'ستظهر المنشورات النصية هنا.');
        }
        return ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, i) => PostCard(post: list[i]),
        );
      },
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
