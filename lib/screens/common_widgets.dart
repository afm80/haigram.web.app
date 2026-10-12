import 'package:flutter/material.dart';

import '../services/post_service.dart';
import '../services/presence_service.dart';
import '../services/user_service.dart';
import '../theme.dart';
import 'post_widgets.dart' show timeAgo;
import 'profile_screen.dart';

/// يفتح ملف مستخدم (مثل تيك توك / إنستغرام).
void openProfile(BuildContext context, String uid) {
  if (uid.isEmpty) return;
  Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => UserProfileScreen(uid: uid)));
}

/// صورة المستخدم: صورته إن وُجدت وإلا أول حرف من اسمه.
class UserAvatar extends StatelessWidget {
  final String uid;
  final String fallbackName;
  final double radius;
  final VoidCallback? onTap;
  final bool showOnline;

  const UserAvatar(
      {super.key,
      required this.uid,
      this.fallbackName = '',
      this.radius = 20,
      this.onTap,
      this.showOnline = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: FutureBuilder<AppUser?>(
        future: UserService.profileOf(uid),
        builder: (context, s) {
          final u = s.data;
          final image = u?.avatarImage;
          final label = u != null
              ? u.initial
              : (fallbackName.isNotEmpty ? fallbackName[0].toUpperCase() : '?');
          final avatar = CircleAvatar(
            radius: radius,
            backgroundColor: AppColors.accent,
            backgroundImage: image,
            child: image == null
                ? Text(label,
                    style: TextStyle(
                        fontSize: radius * 0.85,
                        fontWeight: FontWeight.w700,
                        color: Colors.white))
                : null,
          );
          if (!showOnline || uid.isEmpty) return avatar;
          return StreamBuilder<bool>(
            stream: PresenceService.isOnline(uid),
            builder: (context, presence) => Stack(
              clipBehavior: Clip.none,
              children: [
                avatar,
                if (presence.data == true)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: radius * 0.48,
                      height: radius * 0.48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF31C75A),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: context.appColors.bg,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// نافذة التعليقات السفلية.
void showCommentsSheet(BuildContext context, Post post) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.appColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _CommentsSheet(post: post, outerContext: context),
  );
}

class _CommentsSheet extends StatefulWidget {
  final Post post;
  final BuildContext outerContext;
  const _CommentsSheet({required this.post, required this.outerContext});

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _text = TextEditingController();
  bool _sending = false;

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await PostService.addComment(widget.post.id, t);
      _text.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('تعذر إرسال التعليق: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final me = PostService.uidOrEmpty;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: h * 0.72,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: context.appColors.textDim,
                    borderRadius: BorderRadius.circular(2))),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('التعليقات',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            const Divider(height: 1, color: Color(0x22FFFFFF)),
            Expanded(
              child: StreamBuilder<List<Comment>>(
                stream: PostService.comments(widget.post.id),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(
                        child: Text('تعذر تحميل التعليقات\n${snap.error}',
                            textAlign: TextAlign.center));
                  }
                  if (!snap.hasData) {
                    return const AppLoading(message: 'جارٍ تحميل التعليقات...');
                  }
                  final list = snap.data!;
                  if (list.isEmpty) {
                    return const EmptyState(
                      icon: Icons.mode_comment_outlined,
                      title: 'لا توجد تعليقات بعد',
                      message: 'ابدأ المحادثة وكن أول من يعلّق.',
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final c = list[i];
                      final canDelete = c.uid == me || widget.post.uid == me;
                      void open() {
                        Navigator.pop(context);
                        openProfile(widget.outerContext, c.uid);
                      }

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            UserAvatar(
                                uid: c.uid,
                                fallbackName: c.username,
                                radius: 17,
                                onTap: open),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  GestureDetector(
                                    onTap: open,
                                    child: Row(
                                      children: [
                                        Flexible(
                                            child: Text(c.username,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 13))),
                                        const SizedBox(width: 8),
                                        Text(timeAgo(c.createdAt),
                                            style: TextStyle(
                                                color: context.appColors.textDim,
                                                fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(c.text,
                                      style: const TextStyle(height: 1.4)),
                                ],
                              ),
                            ),
                            if (canDelete)
                              GestureDetector(
                                onTap: () => PostService.deleteComment(
                                    widget.post.id, c.id),
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Icon(Icons.delete_outline_rounded,
                                      size: 20, color: context.appColors.textDim),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(height: 1, color: Color(0x22FFFFFF)),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    UserAvatar(
                        uid: me,
                        fallbackName: PostService.username,
                        radius: 17),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _text,
                        maxLength: 500,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(
                          hintText: 'أضف تعليقاً...',
                          counterText: '',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      onPressed: _sending ? null : _send,
                      icon: const Icon(Icons.send_rounded,
                          color: AppColors.accent),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
